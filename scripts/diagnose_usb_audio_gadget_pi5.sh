#!/usr/bin/env bash
set -euo pipefail

echo "== Model =="
tr -d '\0' </proc/device-tree/model 2>/dev/null || true
echo

echo "== Boot config =="
grep -nE 'otg_mode|dwc2|xmos|dtoverlay=|dtparam=i2s' /boot/firmware/config.txt 2>/dev/null || true
echo

echo "== Modules =="
lsmod | grep -E 'dwc2|g_audio|u_audio|usb_f_uac|libcomposite|g_ether|u_ether' || true
echo

echo "== UDC =="
if ! ls /sys/class/udc/* >/dev/null 2>&1; then
  echo "No UDC. Check dtoverlay=dwc2,dr_mode=peripheral under [all], then reboot."
else
  for udc in /sys/class/udc/*; do
    echo "UDC: $(basename "$udc")"
    for attr in state current_speed maximum_speed function is_selfpowered; do
      [ -e "$udc/$attr" ] && printf "%s=" "$attr" && cat "$udc/$attr" || true
    done
  done
fi
echo

echo "== ALSA =="
cat /proc/asound/cards 2>/dev/null || true
echo
arecord -l 2>/dev/null || true
echo
aplay -l 2>/dev/null || true
echo

echo "== CamillaDSP =="
systemctl --no-pager --plain status camilladsp.service 2>/dev/null | sed -n '1,80p' || true
echo
tail -n 80 /var/log/camilladsp/camilladsp.log 2>/dev/null || true
echo

echo "== Interpretation =="
state="$(cat /sys/class/udc/*/state 2>/dev/null | head -n1 || true)"
if [ "$state" = "not attached" ]; then
  echo "The Pi gadget is ready but no USB host is attached."
  echo "Check the USB-C data path: direct data cable or a splitter that passes data and host VBUS/CC."
elif [ -n "$state" ]; then
  echo "UDC state is: $state"
  echo "If Windows still does not show the device, inspect VID/PID and Windows Device Manager."
fi
