#!/usr/bin/env python3
"""Generate a synthetic 3D-accelerometer gait dataset.

Simulates a wearable inertial sensor worn on the belt (a fictional
"GaitBand" IMU) recording a patient at ~100 Hz cycling through activity
phases:

    standing → walking → running → walking → standing → (loop)

The signal is a superposition of:
- gait fundamental at phase-dependent cadence f_c,
- gait harmonic at 2*f_c,
- slow postural sway,
- Gaussian noise,
- an activity envelope that modulates amplitude (still while standing).

Deterministic under a fixed seed --- CC0-1.0, no real patient data.
"""

from __future__ import annotations

import argparse
import csv
from pathlib import Path

import numpy as np


# Activity phases: (label, duration_s, cadence_hz, amplitude_factor)
# 0 Hz cadence = standing still.
PHASES = [
    ("standing", 8.0, 0.0, 0.05),
    ("walking",  20.0, 1.8, 1.0),
    ("running",  15.0, 2.8, 1.6),
    ("walking",  20.0, 1.8, 1.0),
    ("standing", 8.0, 0.0, 0.05),
]

# Fraction of each phase's duration used for a smooth ramp into the next
# phase (blends cadence + amplitude to avoid discontinuities).
RAMP_FRAC = 0.15


def _phase_schedule(total_s: float) -> tuple[np.ndarray, np.ndarray]:
    """Build per-cycle cumulative phase-boundary times and cycle length."""
    durations = np.array([p[1] for p in PHASES])
    boundaries = np.concatenate([[0.0], np.cumsum(durations)])
    return boundaries, durations.sum()


def _interpolate(t_in_cycle: float,
                 boundaries: np.ndarray) -> tuple[float, float]:
    """Return (cadence_hz, amplitude_factor) at time t within one cycle.

    Between adjacent phases, blend smoothly over a fraction RAMP_FRAC of
    the shorter neighbour so cadence and amplitude change without jumps.
    """
    for i, (_, dur, cad, amp) in enumerate(PHASES):
        t_start = boundaries[i]
        t_end = boundaries[i + 1]
        if not (t_start <= t_in_cycle < t_end):
            continue
        # Distance from the boundary as a fraction of this phase.
        t_local = t_in_cycle - t_start
        prev = PHASES[i - 1] if i > 0 else PHASES[-1]
        nxt = PHASES[(i + 1) % len(PHASES)]
        ramp = RAMP_FRAC * dur
        if t_local < ramp:
            # Ramping in from previous phase.
            u = 0.5 - 0.5 * np.cos(np.pi * (t_local / ramp))
            return (prev[2] * (1 - u) + cad * u,
                    prev[3] * (1 - u) + amp * u)
        if t_local > dur - ramp:
            # Ramping out into next phase.
            u = 0.5 - 0.5 * np.cos(np.pi * ((dur - t_local) / ramp))
            return (nxt[2] * (1 - u) + cad * u,
                    nxt[3] * (1 - u) + amp * u)
        return cad, amp
    # Should not happen (t_in_cycle is taken mod cycle_len).
    return PHASES[-1][2], PHASES[-1][3]


def generate(duration_s: float = 300.0,
             sample_rate_hz: float = 100.0,
             seed: int = 42) -> np.ndarray:
    """Return an (N, 4) array: t, ax, ay, az [g]."""
    rng = np.random.default_rng(seed)
    t = np.arange(0.0, duration_s, 1.0 / sample_rate_hz)
    boundaries, cycle_len = _phase_schedule(duration_s)

    # Per-sample cadence and amplitude from the phase schedule (with jitter).
    cadence = np.empty_like(t)
    amplitude = np.empty_like(t)
    for i, ti in enumerate(t):
        cad, amp = _interpolate(ti % cycle_len, boundaries)
        cadence[i] = cad
        amplitude[i] = amp

    # Small realistic wobble on top of the schedule.
    cadence_jitter = 0.05 * np.sin(2 * np.pi * 0.15 * t)
    cadence = np.clip(cadence + cadence_jitter * (cadence > 0.1), 0.0, None)

    # Phase = integral of instantaneous angular frequency.
    phase = 2 * np.pi * np.cumsum(cadence) / sample_rate_hz

    # Vertical (az): dominant gait component + gravity offset.
    az = 1.0 + amplitude * (0.35 * np.sin(phase) + 0.12 * np.sin(2 * phase))

    # Anterior-posterior (ax): smaller, phase-shifted.
    ax = amplitude * (0.18 * np.sin(phase + np.pi / 3)
                      + 0.06 * np.sin(2 * phase))

    # Medio-lateral (ay): smallest, half-cadence sway.
    ay = amplitude * (0.10 * np.sin(phase / 2) + 0.04 * np.sin(phase))

    # Postural sway (low-frequency drift, present even while standing).
    sway = 0.03 * np.sin(2 * np.pi * 0.1 * t)
    ax += sway
    ay += sway * 0.7

    # Sensor noise (constant across activities).
    ax += rng.normal(0, 0.02, size=t.shape)
    ay += rng.normal(0, 0.02, size=t.shape)
    az += rng.normal(0, 0.02, size=t.shape)

    return np.column_stack([t, ax, ay, az])


def write_csv(data: np.ndarray, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["t_s", "ax_g", "ay_g", "az_g"])
        for row in data:
            writer.writerow([f"{row[0]:.3f}",
                             f"{row[1]:.5f}",
                             f"{row[2]:.5f}",
                             f"{row[3]:.5f}"])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path,
                        default=Path("data/gaitband-sample.csv"))
    parser.add_argument("--duration", type=float, default=300.0,
                        help="seconds of synthetic data (default 300)")
    parser.add_argument("--rate", type=float, default=100.0,
                        help="sample rate in Hz (default 100)")
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    data = generate(args.duration, args.rate, args.seed)
    write_csv(data, args.output)
    cycle = sum(p[1] for p in PHASES)
    labels = " → ".join(p[0] for p in PHASES)
    print(f"Wrote {len(data)} samples to {args.output}")
    print(f"Activity cycle ({cycle:.0f} s): {labels} → (loop)")


if __name__ == "__main__":
    main()
