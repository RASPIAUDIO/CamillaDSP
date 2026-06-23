#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PIOLIB_BUILD="$PROJECT_DIR/third_party/piolib-build"
GPIO="${SPDIF_GPIO:-12}"
DMA_BUFFERS="${SPDIF_DMA_BUFFERS:-4}"
CHUNK_FRAMES="${SPDIF_CHUNK_FRAMES:-0}"

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 file.wav" >&2
  echo "Set SPDIF_GPIO=12, SPDIF_DMA_BUFFERS=4, or SPDIF_CHUNK_FRAMES=48000 to override defaults." >&2
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
echo "DMA buffers: ${DMA_BUFFERS}, chunk frames: ${CHUNK_FRAMES}"

LD_LIBRARY_PATH="$PIOLIB_BUILD${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
  "$PROJECT_DIR/build/spdif_pi5_pio_tx" \
  --gpio "$GPIO" \
  --pio-clock-hz 100000000 \
  --mode wav \
  --input "$INPUT" \
  --chunk-frames "$CHUNK_FRAMES" \
  --dma-buffers "$DMA_BUFFERS"
