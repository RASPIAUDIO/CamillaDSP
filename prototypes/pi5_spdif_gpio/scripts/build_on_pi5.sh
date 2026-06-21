#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UTILS_DIR="$PROJECT_DIR/third_party/raspberrypi-utils"
PIOLIB_BUILD="$PROJECT_DIR/third_party/piolib-build"

sudo apt update
sudo apt install -y build-essential cmake git

if [ ! -e /dev/pio0 ]; then
  cat >&2 <<'MSG'

/dev/pio0 is not present.
Update Raspberry Pi OS, kernel, and EEPROM on a Raspberry Pi 5, then reboot:

  sudo apt update
  sudo apt full-upgrade -y
  sudo raspi-config
  # Advanced Options -> Bootloader Version -> Latest
  sudo reboot

MSG
fi

mkdir -p "$PROJECT_DIR/third_party"
if [ ! -d "$UTILS_DIR/.git" ]; then
  git clone --depth 1 https://github.com/raspberrypi/utils.git "$UTILS_DIR"
fi

cmake -S "$UTILS_DIR/piolib" -B "$PIOLIB_BUILD" -DBUILD_SHARED_LIBS=1 -DCMAKE_BUILD_TYPE=Release
cmake --build "$PIOLIB_BUILD" -j"$(nproc)"

make -C "$PROJECT_DIR" clean
make -C "$PROJECT_DIR"
make -C "$PROJECT_DIR" pio PIOLIB_INC="$UTILS_DIR/piolib/include" PIOLIB_LIB="$PIOLIB_BUILD"

mkdir -p "$PROJECT_DIR/out"
"$PROJECT_DIR/build/spdif_gen" \
  --rate 48000 \
  --tone 1000 \
  --seconds 1 \
  --amplitude-dbfs -12 \
  --output "$PROJECT_DIR/out/spdif_48k_1khz_1s.bmc32" \
  --self-test

cat <<MSG

Build complete.

Test command:
  cd "$PROJECT_DIR"
  LD_LIBRARY_PATH="$PIOLIB_BUILD" ./build/spdif_pi5_pio_tx --gpio 21 --rate 48000 --tone 1000 --seconds 10 --amplitude-dbfs -12

MSG
