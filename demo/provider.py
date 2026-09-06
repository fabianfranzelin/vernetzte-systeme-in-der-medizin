#!/usr/bin/env python3
"""Wearable-simulator SDC provider.

Streams synthetic 3D-accelerometer data from a CSV file and exposes an
SDC-style API mirroring IEEE 11073-20701 semantics:

- GET  /mdib                     → descriptors (static structure)
- GET  /state                    → current state snapshot
- GET  /events?after=<seq>       → long-poll for EpisodicMetricReport events

A production deployment would replace this HTTP facade with the sdc11073
library (WS-Discovery + SOAP + WS-Eventing).  The information model,
however, mirrors BICEPS: MDS → VMD → Channel → Metric.

CC0-1.0.
"""

from __future__ import annotations

import argparse
import asyncio
import csv
import math
import time
from collections import deque
from pathlib import Path
from typing import Deque

import numpy as np
from fastapi import FastAPI, Query
from fastapi.responses import JSONResponse
import uvicorn


def _json_safe(obj):
    """Replace non-finite floats with None so strict JSON encoders accept them."""
    if isinstance(obj, float):
        return obj if math.isfinite(obj) else None
    if isinstance(obj, dict):
        return {k: _json_safe(v) for k, v in obj.items()}
    if isinstance(obj, (list, tuple)):
        return [_json_safe(v) for v in obj]
    return obj


# ---------- BICEPS-style information model (static descriptors) ----------

MDIB = {
    "mds": {
        "handle": "mds.wearable",
        "manufacturer": "Reutlingen Demo",
        "model": "gaitband-sim",
        "vmds": [
            {
                "handle": "vmd.gait",
                "channels": [
                    {
                        "handle": "channel.imu",
                        "metrics": [
                            {
                                "handle": "metric.cadence",
                                "kind": "NumericMetric",
                                "unit": "1/min",
                                "code": "MDC_ACT_STEP_RATE",
                                "description": "Step cadence",
                            },
                            {
                                "handle": "metric.accel",
                                "kind": "RealTimeSampleArrayMetric",
                                "unit": "g",
                                "code": "MDC_ACT_ACCEL_VEC",
                                "description": "3D acceleration",
                                "sample_rate_hz": 100.0,
                                "components": ["ax", "ay", "az"],
                            },
                        ],
                    }
                ],
            }
        ],
    }
}


# ---------- runtime state ----------

STATE = {
    "metric.cadence": {"value": None, "unit": "1/min", "ts": 0.0},
    "metric.accel": {"value": [None, None, None], "unit": "g", "ts": 0.0},
}

# In-memory event ring (would be WS-Eventing subscriptions in real SDC).
EVENTS: Deque[dict] = deque(maxlen=2000)
EVENT_SEQ = 0
EVENT_COND = asyncio.Condition()


def _push_event(evt: dict) -> None:
    global EVENT_SEQ
    EVENT_SEQ += 1
    evt = dict(evt, seq=EVENT_SEQ)
    EVENTS.append(evt)


# ---------- gait analysis ----------

def rolling_cadence(recent_az: np.ndarray, sample_rate_hz: float) -> float:
    """Estimate step cadence in steps/min from the last few seconds of az.

    Uses the peak of the magnitude spectrum in the plausible gait band
    (0.5-3.5 Hz), refined with quadratic interpolation around the peak so
    the estimate is not quantized to the FFT bin width.

    Returns 0.0 (physical meaning: no steps per minute → standing) when
    the signal energy is at noise level.
    """
    x = recent_az - np.mean(recent_az)
    n = len(x)
    if n < 128:
        return float("nan")
    # Energy gate: below this RMS the signal is at noise level (standing)
    # → report zero cadence so the trace visibly drops into the standing band.
    if float(np.sqrt(np.mean(x * x))) < 0.05:
        return 0.0
    spectrum = np.abs(np.fft.rfft(x * np.hanning(n)))
    freqs = np.fft.rfftfreq(n, d=1.0 / sample_rate_hz)
    band = (freqs >= 0.5) & (freqs <= 3.5)
    if not band.any():
        return 0.0
    band_idx = np.flatnonzero(band)
    local_peak = int(np.argmax(spectrum[band]))
    k = band_idx[local_peak]
    # Quadratic (parabolic) interpolation around the peak bin for sub-bin
    # accuracy.  Formula: delta = 0.5 * (a - c) / (a - 2b + c).
    if 0 < k < len(spectrum) - 1:
        a, b, c = spectrum[k - 1], spectrum[k], spectrum[k + 1]
        denom = (a - 2 * b + c)
        delta = 0.5 * (a - c) / denom if denom != 0 else 0.0
    else:
        delta = 0.0
    bin_width = freqs[1] - freqs[0]
    peak_freq = freqs[k] + delta * bin_width
    return float(peak_freq * 60.0)


# ---------- data pump ----------

async def stream_samples(csv_path: Path, sample_rate_hz: float,
                         speedup: float) -> None:
    """Read the CSV row by row, update STATE, emit episodic reports."""
    samples = []
    with csv_path.open() as f:
        reader = csv.reader(f)
        next(reader)  # header
        for row in reader:
            samples.append((float(row[0]), float(row[1]),
                            float(row[2]), float(row[3])))

    if not samples:
        raise SystemExit(f"No samples in {csv_path}")

    window_size = int(sample_rate_hz * 5)  # 5-second sliding window
    window: Deque[float] = deque(maxlen=window_size)

    dt = 1.0 / (sample_rate_hz * speedup)
    stream_batch_interval = 0.1  # emit one report every 100 ms
    last_cadence_emit = 0.0
    last_stream_emit = 0.0

    # Batched sample buffer for RealTimeSampleArrayMetricState.  Every 100 ms
    # we flush all buffered samples as a single report --- Nyquist-preserving
    # transport of the full 100 Hz stream at a 10 Hz report rate.
    accel_batch: list[tuple[float, float, float]] = []
    batch_t_start: float | None = None

    idx = 0
    while True:
        t, ax, ay, az = samples[idx % len(samples)]
        window.append(az)
        now = time.time()

        STATE["metric.accel"] = {
            "value": [ax, ay, az], "unit": "g", "ts": now,
        }

        # Buffer every sample (no decimation, no aliasing).
        if batch_t_start is None:
            batch_t_start = now
        accel_batch.append((ax, ay, az))

        # Flush the buffered samples as one RealTimeSampleArray report.
        if now - last_stream_emit > stream_batch_interval and accel_batch:
            async with EVENT_COND:
                _push_event({
                    "type": "RealTimeSampleArrayReport",
                    "handle": "metric.accel",
                    "samples": accel_batch,
                    "components": ["ax", "ay", "az"],
                    "unit": "g",
                    "sample_rate_hz": sample_rate_hz,
                    "t_start": batch_t_start,
                })
                EVENT_COND.notify_all()
            accel_batch = []
            batch_t_start = None
            last_stream_emit = now

        # Emit cadence at 1 Hz.
        if now - last_cadence_emit > 1.0 and len(window) >= window_size:
            cadence = rolling_cadence(np.array(window), sample_rate_hz)
            STATE["metric.cadence"] = {
                "value": cadence, "unit": "1/min", "ts": now,
            }
            async with EVENT_COND:
                _push_event({
                    "type": "EpisodicMetricReport",
                    "handle": "metric.cadence",
                    "value": cadence,
                    "unit": "1/min",
                    "ts": now,
                })
                EVENT_COND.notify_all()
            last_cadence_emit = now

        idx += 1
        await asyncio.sleep(dt)


# ---------- HTTP facade (SDC-style semantics) ----------

app = FastAPI(title="SDC Wearable Provider")


@app.get("/mdib")
async def get_mdib() -> JSONResponse:
    """Return the static MDIB (BICEPS descriptors)."""
    return JSONResponse(_json_safe(MDIB))


@app.get("/state")
async def get_state() -> JSONResponse:
    """Return the current state snapshot for all metrics."""
    return JSONResponse({"seq": EVENT_SEQ, "state": _json_safe(STATE)})


@app.get("/events")
async def get_events(after: int = Query(0, ge=0),
                     timeout: float = Query(15.0, gt=0, le=60.0)):
    """Long-poll for events since sequence number `after`.

    Mirrors WS-Eventing / EpisodicMetricReport delivery.
    """
    async with EVENT_COND:
        pending = [e for e in EVENTS if e["seq"] > after]
        if pending:
            return _json_safe({"seq": EVENT_SEQ, "events": pending})
        try:
            await asyncio.wait_for(EVENT_COND.wait(), timeout=timeout)
        except asyncio.TimeoutError:
            return _json_safe({"seq": EVENT_SEQ, "events": []})
        pending = [e for e in EVENTS if e["seq"] > after]
        return _json_safe({"seq": EVENT_SEQ, "events": pending})


@app.get("/")
async def root() -> dict:
    return {
        "role": "SDC Provider",
        "device": MDIB["mds"]["model"],
        "endpoints": ["/mdib", "/state", "/events"],
    }


# ---------- lifespan ----------

@app.on_event("startup")
async def _startup() -> None:
    csv_path = Path(app.state.csv_path)
    if not csv_path.exists():
        raise SystemExit(f"CSV not found: {csv_path}. Run `make data` first.")
    asyncio.create_task(stream_samples(csv_path,
                                        app.state.sample_rate_hz,
                                        app.state.speedup))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data", type=Path, required=True,
                        help="Synthetic gait CSV.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=7010)
    parser.add_argument("--rate", type=float, default=100.0,
                        help="Nominal sample rate of the CSV (Hz).")
    parser.add_argument("--speedup", type=float, default=1.0,
                        help="Playback speed multiplier.")
    args = parser.parse_args()

    app.state.csv_path = args.data
    app.state.sample_rate_hz = args.rate
    app.state.speedup = args.speedup

    uvicorn.run(app, host=args.host, port=args.port, log_level="warning")


if __name__ == "__main__":
    main()
