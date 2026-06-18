#!/usr/bin/env bash
set -euo pipefail

EXPECTED_RATE="${EXPECTED_RATE:-48000}"
EXPECTED_CHANNELS="${EXPECTED_CHANNELS:-8}"
UDC="${UDC:-1000480000.usb}"

echo "== USB gadget =="
if [ -d "/sys/class/udc/$UDC" ]; then
  printf "state: "
  cat "/sys/class/udc/$UDC/state" || true
  printf "function: "
  cat "/sys/class/udc/$UDC/function" || true
  printf "speed: "
  cat "/sys/class/udc/$UDC/current_speed" || true
else
  echo "Missing /sys/class/udc/$UDC"
fi

echo
echo "== g_audio options =="
cat /etc/modprobe.d/usb_g_audio.conf

echo
echo "== ALSA cards =="
arecord -l || true
aplay -l || true

echo
echo "== Active hw_params =="
found=0
for f in /proc/asound/card*/pcm*/sub*/hw_params; do
  [ -e "$f" ] || continue
  if grep -q "rate: $EXPECTED_RATE" "$f" && grep -q "channels: $EXPECTED_CHANNELS" "$f"; then
    found=1
  fi
  echo "--- $f"
  cat "$f"
done

echo
echo "== CamillaDSP service =="
systemctl --no-pager --full status camilladsp.service || true

echo
echo "== Expected stream =="
bits_per_second=$((EXPECTED_RATE * EXPECTED_CHANNELS * 32))
bytes_per_second=$((bits_per_second / 8))
echo "${EXPECTED_RATE} Hz * ${EXPECTED_CHANNELS} channels * 32 bits = ${bits_per_second} bit/s = ${bytes_per_second} byte/s"

if [ "$found" -eq 1 ]; then
  echo "OK: found active ${EXPECTED_CHANNELS}ch/${EXPECTED_RATE}Hz ALSA stream."
else
  echo "No active ${EXPECTED_CHANNELS}ch/${EXPECTED_RATE}Hz stream found yet."
  echo "Start playback from the USB host, then rerun this script."
fi
