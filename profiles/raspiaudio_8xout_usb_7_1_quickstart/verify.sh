#!/usr/bin/env bash
set -euo pipefail

EXPECTED_RATE="${EXPECTED_RATE:-48000}"
EXPECTED_CHANNELS="${EXPECTED_CHANNELS:-8}"

echo "== USB gadget =="
if ! ls /sys/class/udc/* >/dev/null 2>&1; then
  echo "No USB device controller found. Reboot and check the USB-C gadget cable."
else
  for udc in /sys/class/udc/*; do
    echo "UDC: $(basename "$udc")"
    for attr in state current_speed maximum_speed function; do
      [ -e "$udc/$attr" ] && printf "%s: " "$attr" && cat "$udc/$attr" || true
    done
  done
fi

echo
echo "== USB audio descriptor options =="
cat /etc/modprobe.d/usb_g_audio.conf 2>/dev/null || true

echo
echo "== ALSA cards =="
aplay -l || true
echo
arecord -l || true

echo
echo "== Active ALSA streams =="
found=0
for f in /proc/asound/card*/pcm*/sub*/hw_params; do
  [ -e "$f" ] || continue
  echo "--- $f"
  cat "$f"
  if grep -q "rate: $EXPECTED_RATE" "$f" && grep -q "channels: $EXPECTED_CHANNELS" "$f"; then
    found=1
  fi
done

echo
echo "== CamillaDSP =="
systemctl --no-pager --full status camilladsp.service 2>/dev/null | sed -n '1,80p' || true
echo
tail -n 100 /var/log/camilladsp/camilladsp.log 2>/dev/null || true

echo
echo "== Result =="
if [ "$found" -eq 1 ]; then
  echo "OK: found an active ${EXPECTED_CHANNELS}ch/${EXPECTED_RATE}Hz ALSA stream."
else
  echo "No active ${EXPECTED_CHANNELS}ch/${EXPECTED_RATE}Hz stream yet."
  echo "Start playback from the computer, then run this script again."
fi

stalls="$(tail -n 500 /var/log/camilladsp/camilladsp.log 2>/dev/null | grep -c 'PB: device stalled' || true)"
echo "Recent playback stalls in CamillaDSP log: $stalls"
