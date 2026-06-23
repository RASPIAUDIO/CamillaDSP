#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PIOLIB_BUILD="$PROJECT_DIR/third_party/piolib-build"
GPIO="${SPDIF_GPIO:-12}"

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 file.wav" >&2
  echo "Set SPDIF_GPIO=12 to override the output pin." >&2
  exit 2
fi

INPUT="$1"

if [ ! -e /dev/pio0 ]; then
  echo "Missing /dev/pio0. This test requires Raspberry Pi 5 RP1 PIO support." >&2
  exit 1
fi

if [ ! -x "$PROJECT_DIR/build/spdif_pi5_pio_tx" ]; then
  echo "Missing build/spdif_pi5_pio_tx. Run ./scripts/build_on_pi5.sh first." >&2
  exit 1
fi

echo "Playing WAV over S/PDIF on GPIO${GPIO}: $INPUT"

LD_LIBRARY_PATH="$PIOLIB_BUILD${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
  "$PROJECT_DIR/build/spdif_pi5_pio_tx" \
  --gpio "$GPIO" \
  --pio-clock-hz 100000000 \
  --mode wav \
  --input "$INPUT" \
  --chunk-frames 0
