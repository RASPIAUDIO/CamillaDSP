#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PIOLIB_BUILD="$PROJECT_DIR/third_party/piolib-build"
GPIO="${1:-12}"

if [ ! -e /dev/pio0 ]; then
  echo "Missing /dev/pio0. This test requires Raspberry Pi 5 RP1 PIO support." >&2
  exit 1
fi

if [ ! -x "$PROJECT_DIR/build/spdif_pi5_pio_tx" ]; then
  echo "Missing build/spdif_pi5_pio_tx. Run ./scripts/build_on_pi5.sh first." >&2
  exit 1
fi

echo "Connect GPIO${GPIO} through a safe prototype output stage to a S/PDIF receiver."
echo "The receiver should lock as PCM 48 kHz and play a 2 second 1 kHz sine."

LD_LIBRARY_PATH="$PIOLIB_BUILD${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
  "$PROJECT_DIR/build/spdif_pi5_pio_tx" \
  --gpio "$GPIO" \
  --rate 48000 \
  --pio-clock-hz 200000000 \
  --mode tone \
  --tone 1000 \
  --seconds 2 \
  --amplitude-dbfs -18 \
  --chunk-frames 0
