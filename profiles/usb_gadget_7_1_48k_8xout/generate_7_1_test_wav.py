#!/usr/bin/env python3
"""Generate a Windows-friendly 7.1 WAV channel-identification file.

The file is written as WAVE_FORMAT_EXTENSIBLE with channel mask 0x63f:
FL, FR, FC, LFE, BL, BR, SL, SR.
"""

from __future__ import annotations

import argparse
import math
import struct
from pathlib import Path


CHANNELS = [
    ("FL_OUT1", 180.0),
    ("FR_OUT2", 220.0),
    ("FC_OUT3", 260.0),
    ("LFE_OUT4", 80.0),
    ("BL_OUT5", 320.0),
    ("BR_OUT6", 360.0),
    ("SL_OUT7", 400.0),
    ("SR_OUT8", 440.0),
]

CHANNEL_MASK_7_1 = 0x63F
PCM_SUBFORMAT_GUID = struct.pack(
    "<IHH8s",
    0x00000001,
    0x0000,
    0x0010,
    b"\x80\x00\x00\xaa\x00\x38\x9b\x71",
)


def write_wave_extensible(
    path: Path,
    rate: int,
    tone_seconds: float,
    gap_seconds: float,
    amplitude: float,
) -> None:
    channels = len(CHANNELS)
    bytes_per_sample = 4
    bits_per_sample = bytes_per_sample * 8
    block_align = channels * bytes_per_sample
    frames_per_tone = int(rate * tone_seconds)
    frames_per_gap = int(rate * gap_seconds)
    total_frames = (frames_per_tone + frames_per_gap) * channels

    data = bytearray(total_frames * block_align)
    max_i32 = int((2**31 - 1) * amplitude)
    frame_index = 0

    for channel_index, (_label, frequency) in enumerate(CHANNELS):
        for n in range(frames_per_tone):
            sample = int(max_i32 * math.sin(2.0 * math.pi * frequency * n / rate))
            offset = (frame_index * channels + channel_index) * bytes_per_sample
            data[offset : offset + bytes_per_sample] = struct.pack("<i", sample)
            frame_index += 1
        frame_index += frames_per_gap

    fmt_payload = b"".join(
        [
            struct.pack(
                "<HHIIHHH",
                0xFFFE,
                channels,
                rate,
                rate * block_align,
                block_align,
                bits_per_sample,
                22,
            ),
            struct.pack("<HI", bits_per_sample, CHANNEL_MASK_7_1),
            PCM_SUBFORMAT_GUID,
        ]
    )

    riff_size = 4 + (8 + len(fmt_payload)) + (8 + len(data))
    with path.open("wb") as f:
        f.write(b"RIFF")
        f.write(struct.pack("<I", riff_size))
        f.write(b"WAVE")
        f.write(b"fmt ")
        f.write(struct.pack("<I", len(fmt_payload)))
        f.write(fmt_payload)
        f.write(b"data")
        f.write(struct.pack("<I", len(data)))
        f.write(data)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "output",
        nargs="?",
        default="raspiaudio_7_1_channel_id_48k.wav",
        help="Output WAV path.",
    )
    parser.add_argument("--rate", type=int, default=48000)
    parser.add_argument("--tone-seconds", type=float, default=1.0)
    parser.add_argument("--gap-seconds", type=float, default=0.35)
    parser.add_argument("--amplitude", type=float, default=0.20)
    args = parser.parse_args()

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    write_wave_extensible(
        output,
        rate=args.rate,
        tone_seconds=args.tone_seconds,
        gap_seconds=args.gap_seconds,
        amplitude=args.amplitude,
    )

    print(f"Wrote {output}")
    print("Channel order: " + ", ".join(label for label, _freq in CHANNELS))
    print(f"Rate: {args.rate} Hz, layout mask: 0x{CHANNEL_MASK_7_1:x}")


if __name__ == "__main__":
    main()
