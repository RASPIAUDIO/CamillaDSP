#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PIOLIB_BUILD="$PROJECT_DIR/third_party/piolib-build"

GPIO="${SPDIF_LED_GPIO:-44}"
LED_NAME="${SPDIF_LED_NAME:-PWR}"
DURATION="${SPDIF_LED_SECONDS:-5}"

LED_PATH="/sys/class/leds/${LED_NAME}"
ORIGINAL_TRIGGER=""
ORIGINAL_BRIGHTNESS=""

sudo_write() {
  local value="$1"
  local path="$2"
  printf '%s' "$value" | sudo tee "$path" >/dev/null
}

restore_led() {
  if [ -n "$ORIGINAL_TRIGGER" ] && [ -e "$LED_PATH/trigger" ]; then
    sudo_write "$ORIGINAL_TRIGGER" "$LED_PATH/trigger" || true
  fi
  if [ -n "$ORIGINAL_BRIGHTNESS" ] && [ -e "$LED_PATH/brightness" ]; then
    sudo_write "$ORIGINAL_BRIGHTNESS" "$LED_PATH/brightness" || true
  fi
}

if [ ! -e /dev/pio0 ]; then
  echo "Missing /dev/pio0. This test requires Raspberry Pi 5 RP1 PIO support." >&2
  exit 1
fi

if [ ! -x "$PROJECT_DIR/build/spdif_pi5_pio_tx" ]; then
  echo "Missing build/spdif_pi5_pio_tx. Run ./scripts/build_on_pi5.sh first." >&2
  exit 1
fi

if [ ! -d "$LED_PATH" ]; then
  echo "Missing ${LED_PATH}." >&2
  echo "This script targets the Raspberry Pi 5 PWR LED, normally exposed as /sys/class/leds/PWR." >&2
  echo "Override with SPDIF_LED_NAME=<name> if your OS uses another LED name." >&2
  exit 1
fi

if [ -e "$LED_PATH/trigger" ]; then
  ORIGINAL_TRIGGER="$(sed -n 's/.*\[\([^]]*\)\].*/\1/p' "$LED_PATH/trigger" || true)"
fi
if [ -e "$LED_PATH/brightness" ]; then
  ORIGINAL_BRIGHTNESS="$(cat "$LED_PATH/brightness" || true)"
fi

trap restore_led EXIT INT TERM

echo "Temporarily taking over ${LED_NAME} LED on GPIO${GPIO}."
echo "This is only a visual lab test. It is not a compliant TOSLINK output."

if [ -e "$LED_PATH/trigger" ]; then
  sudo_write none "$LED_PATH/trigger"
fi

echo "Visible LED check: three slow blinks."
for _ in 1 2 3; do
  sudo_write 1 "$LED_PATH/brightness"
  sleep 0.20
  sudo_write 0 "$LED_PATH/brightness"
  sleep 0.20
done

echo "Sending a ${DURATION}s 48 kHz stereo S/PDIF BMC stream to GPIO${GPIO}."
echo "The LED may look steady or dim because the carrier is 6.144 MHz."

LD_LIBRARY_PATH="$PIOLIB_BUILD${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
  "$PROJECT_DIR/build/spdif_pi5_pio_tx" \
  --gpio "$GPIO" \
  --rate 48000 \
  --pio-clock-hz 200000000 \
  --mode tone \
  --tone 1000 \
  --seconds "$DURATION" \
  --amplitude-dbfs -18 \
  --chunk-frames 0

echo "Restoring ${LED_NAME} LED trigger."
