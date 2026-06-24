#!/usr/bin/env python3
"""Generate a deterministic FIR file for CamillaDSP convolution load tests."""

from __future__ import annotations

import math
import sys
from pathlib import Path


DEFAULT_OUTPUT = Path("/etc/camilladsp/coeffs/fir_load_4096_taps.txt")
SAMPLE_RATE_HZ = 48000.0
TAP_COUNT = 4096
CUTOFF_HZ = 18000.0


def blackman(index: int, total: int) -> float:
    if total <= 1:
        return 1.0
    phase = 2.0 * math.pi * index / (total - 1)
    return 0.42 - 0.5 * math.cos(phase) + 0.08 * math.cos(2.0 * phase)


def sinc(value: float) -> float:
    if abs(value) < 1e-12:
        return 1.0
    return math.sin(math.pi * value) / (math.pi * value)


def generate_taps() -> list[float]:
    cutoff_cycles = CUTOFF_HZ / SAMPLE_RATE_HZ
    midpoint = (TAP_COUNT - 1) / 2.0
    taps = []

    for index in range(TAP_COUNT):
        centered = index - midpoint
        tap = 2.0 * cutoff_cycles * sinc(2.0 * cutoff_cycles * centered)
        tap *= blackman(index, TAP_COUNT)
        taps.append(tap)

    total = sum(taps)
    if abs(total) < 1e-12:
        raise RuntimeError("Generated FIR has zero DC gain")

    return [tap / total for tap in taps]


def main() -> int:
    output = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_OUTPUT
    output.parent.mkdir(parents=True, exist_ok=True)

    taps = generate_taps()
    output.write_text("".join(f"{tap:.12e}\n" for tap in taps), encoding="ascii")

    print(f"Wrote {len(taps)} FIR taps to {output}")
    print(f"Sample rate: {SAMPLE_RATE_HZ:.0f} Hz, cutoff: {CUTOFF_HZ:.0f} Hz")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
