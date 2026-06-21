#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

echo "Checking shell scripts..."
bash -n scripts/build_on_pi5.sh
bash -n scripts/test_1khz_lock.sh
bash -n scripts/verify_local.sh

echo "Building offline S/PDIF encoder..."
make clean
make

echo "Generating 48 kHz / 1 kHz stereo BMC test stream..."
mkdir -p out
./build/spdif_gen \
  --rate 48000 \
  --tone 1000 \
  --seconds 1 \
  --amplitude-dbfs -12 \
  --output out/verify_48k_1khz_1s.bmc32 \
  --self-test

expected_bytes=768000
actual_bytes="$(wc -c < out/verify_48k_1khz_1s.bmc32 | tr -d '[:space:]')"
if [[ "$actual_bytes" != "$expected_bytes" ]]; then
  echo "Unexpected BMC output size: got $actual_bytes bytes, expected $expected_bytes" >&2
  exit 1
fi

if [[ -n "${PIOLIB_INC:-}" && -n "${PIOLIB_LIB:-}" ]]; then
  echo "Building RP1 PIO transmitter with PIOLib..."
  make pio PIOLIB_INC="$PIOLIB_INC" PIOLIB_LIB="$PIOLIB_LIB"
else
  echo "Skipping RP1 PIO transmitter build because PIOLIB_INC/PIOLIB_LIB are not set."
fi

rm -rf out
make clean
echo "Local verification OK."
