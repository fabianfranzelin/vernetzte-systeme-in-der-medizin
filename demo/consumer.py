#!/usr/bin/env python3
"""Clinic-side SDC consumer + dashboard.

Subscribes to the wearable provider's EpisodicMetricReport stream, keeps
a rolling in-memory view, and serves a small self-contained HTML dashboard
on http://localhost:8000/.

CC0-1.0.
"""

from __future__ import annotations

import argparse
import asyncio
import time
from collections import deque
from pathlib import Path
from typing import Deque

import httpx
from fastapi import FastAPI
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
import uvicorn


HERE = Path(__file__).resolve().parent


# ---------- rolling views ----------

class RollingWindow:
    def __init__(self, seconds: float = 30.0):
        self.seconds = seconds
        self.samples: Deque[tuple[float, float]] = deque()

    def _evict(self, now: float) -> None:
        cutoff = now - self.seconds
        while self.samples and self.samples[0][0] < cutoff:
            self.samples.popleft()

    def add(self, t: float, v: float) -> None:
        if v != v:  # NaN
            return
        self.samples.append((t, v))
        self._evict(t)

    def as_lists(self) -> tuple[list[float], list[float]]:
        # Expire against wall-clock too, so stale points disappear even when
        # no new samples arrive (e.g. during the standing phase where the
        # provider stops emitting cadence).
        self._evict(time.time())
        if not self.samples:
            return [], []
        ts, vs = zip(*self.samples)
        return list(ts), list(vs)


CADENCE = RollingWindow(seconds=10.0)
ACCEL_Z = RollingWindow(seconds=10.0)

STATUS = {
    "connected": False,
    "provider_url": "",
    "last_seq": 0,
    "last_update": 0.0,
    "mdib": None,
}


# ---------- SDC-style subscription client ----------

async def subscribe_loop(provider_url: str) -> None:
    """Perform the SDC-style GetMdib + long-poll subscription."""
    async with httpx.AsyncClient(timeout=20.0) as client:
        while True:
            try:
                # GetMdib.
                r = await client.get(f"{provider_url}/mdib")
                r.raise_for_status()
                STATUS["mdib"] = r.json()
                STATUS["connected"] = True

                # Long-poll for EpisodicMetricReports.
                last_seq = 0
                while True:
                    r = await client.get(
                        f"{provider_url}/events",
                        params={"after": last_seq, "timeout": 15.0},
                    )
                    r.raise_for_status()
                    payload = r.json()
                    for evt in payload.get("events", []):
                        _handle_event(evt)
                        last_seq = max(last_seq, evt["seq"])
                    STATUS["last_seq"] = last_seq
                    STATUS["last_update"] = time.time()
            except Exception as exc:
                STATUS["connected"] = False
                print(f"[consumer] provider unreachable ({exc}); retry in 2s")
                await asyncio.sleep(2.0)


def _handle_event(evt: dict) -> None:
    etype = evt.get("type")
    handle = evt.get("handle")

    if etype == "EpisodicMetricReport" and handle == "metric.cadence":
        ts = evt.get("ts", time.time())
        val = evt.get("value")
        if val is None:
            return  # provider signalled "no reading" (e.g. standing)
        try:
            CADENCE.add(ts, float(val))
        except (TypeError, ValueError):
            pass
        return

    if etype == "RealTimeSampleArrayReport" and handle == "metric.accel":
        # BICEPS RealTimeSampleArrayMetricState: one report carries a batch
        # of consecutive samples at a declared sample rate.  Reconstruct the
        # per-sample timestamp from t_start + i / sample_rate_hz so the full
        # 100 Hz stream is preserved end-to-end (Nyquist-safe).
        t_start = evt.get("t_start", time.time())
        rate = float(evt.get("sample_rate_hz", 100.0))
        step = 1.0 / rate if rate > 0 else 0.01
        for i, sample in enumerate(evt.get("samples", [])):
            try:
                az = float(sample[2])
            except (TypeError, ValueError, IndexError):
                continue
            ACCEL_Z.add(t_start + i * step, az)
        return


# ---------- dashboard API ----------

app = FastAPI(title="Clinic Dashboard")


@app.get("/api/status")
async def api_status() -> JSONResponse:
    return JSONResponse({
        "connected": STATUS["connected"],
        "provider_url": STATUS["provider_url"],
        "last_seq": STATUS["last_seq"],
        "last_update": STATUS["last_update"],
        "device": (STATUS["mdib"] or {}).get("mds", {}).get("model"),
    })


@app.get("/api/cadence")
async def api_cadence() -> JSONResponse:
    ts, vs = CADENCE.as_lists()
    latest = vs[-1] if vs else None
    return JSONResponse({"t": ts, "v": vs, "latest": latest})


@app.get("/api/accel")
async def api_accel() -> JSONResponse:
    ts, vs = ACCEL_Z.as_lists()
    return JSONResponse({"t": ts, "v": vs})


@app.get("/")
async def index() -> FileResponse:
    return FileResponse(HERE / "dashboard" / "index.html")


@app.get("/mini")
async def mini() -> FileResponse:
    return FileResponse(HERE / "dashboard" / "mini.html")


app.mount("/static", StaticFiles(directory=HERE / "dashboard"), name="static")


# ---------- lifespan ----------

@app.on_event("startup")
async def _startup() -> None:
    STATUS["provider_url"] = app.state.provider_url
    asyncio.create_task(subscribe_loop(app.state.provider_url))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--provider", default="http://127.0.0.1:7010",
                        help="Provider base URL")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8000)
    args = parser.parse_args()

    app.state.provider_url = args.provider

    print(f"Consumer connecting to {args.provider}")
    print(f"Dashboard on http://localhost:{args.port}/")
    uvicorn.run(app, host=args.host, port=args.port, log_level="warning")


if __name__ == "__main__":
    main()
