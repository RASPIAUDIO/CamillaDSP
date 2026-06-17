#!/usr/bin/env bash
set -euo pipefail

OUTPUT_CARD="${OUTPUT_CARD:-XMOSDevice}"
OUTPUT_DEV="${OUTPUT_DEV:-0}"
CAMILLA_CONFIG_DIR="${CAMILLA_CONFIG_DIR:-/home/${SUDO_USER:-$USER}/myCamillaDSP/configs}"
CAMILLA_CONFIG="${CAMILLA_CONFIG:-$CAMILLA_CONFIG_DIR/usb_gadget_2ch_48k_to_${OUTPUT_CARD}.yml}"
CAMILLA_BIN="${CAMILLA_BIN:-/usr/local/bin/camilladsp}"
BOOT_CONFIG="${BOOT_CONFIG:-/boot/firmware/config.txt}"
BACKUP_DIR="/root/codex-backups/usb-audio-gadget-$(date +%Y%m%d-%H%M%S)"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run with sudo."
  exit 1
fi

if [ ! -f "$BOOT_CONFIG" ]; then
  echo "Missing $BOOT_CONFIG"
  exit 1
fi

mkdir -p "$BACKUP_DIR" "$CAMILLA_CONFIG_DIR" /var/log/camilladsp

for file in \
  "$BOOT_CONFIG" \
  /etc/modules \
  /etc/modules-load.d/modules.conf \
  /etc/modprobe.d/usb_g_audio.conf \
  /etc/systemd/system/camilladsp.service; do
  [ -e "$file" ] && cp -a "$file" "$BACKUP_DIR/$(echo "$file" | tr / _).bak"
done

python3 - "$BOOT_CONFIG" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
lines = p.read_text().splitlines()
out = []
inserted = False

for line in lines:
    stripped = line.strip()

    if stripped.startswith("otg_mode=1"):
        out.append("#" + line + " # disabled for USB Audio gadget device mode")
        continue

    if stripped.startswith("dtoverlay=dwc2") or stripped.startswith("#dtoverlay=dwc2"):
        out.append("#" + line.lstrip("#") + " # disabled duplicate/stale by USB Audio gadget setup")
        continue

    out.append(line)

    if stripped == "[all]" and not inserted:
        out.append("dtoverlay=dwc2,dr_mode=peripheral # RASPIAUDIO USB Audio Gadget 2ch")
        inserted = True

if not inserted:
    out.append("[all]")
    out.append("dtoverlay=dwc2,dr_mode=peripheral # RASPIAUDIO USB Audio Gadget 2ch")

p.write_text("\n".join(out) + "\n")
PY

cat >/etc/modules <<'EOF'
# /etc/modules: kernel modules to load at boot time.
# Minimal RASPIAUDIO USB Audio Gadget setup.

i2c-dev
dwc2
g_audio
EOF

cp /etc/modules /etc/modules-load.d/modules.conf

cat >/etc/modprobe.d/usb_g_audio.conf <<'EOF'
# RASPIAUDIO USB Audio Gadget prototype.
# Gadget-side ALSA capture = host-side speaker/playback endpoint.
# c_chmask=3: stereo L/R. c_ssize=4: S32_LE. c_srate=48000: fixed 48 kHz.
# p_chmask=0: no microphone endpoint from Pi back to the host for this first 2-channel test.
# idVendor/idProduct use Linux gadget defaults for lab validation only; use a real VID/PID for product.
options g_audio c_srate=48000 c_ssize=4 c_chmask=3 p_chmask=0 iManufacturer=RASPIAUDIO iProduct=RASPIAUDIO_USB_DSP_2ch iSerialNumber=RASPIAUDIO-PI5-2CH idVendor=0x1d6b idProduct=0x0101
EOF

cat >"$CAMILLA_CONFIG" <<EOF
---
title: "RASPIAUDIO USB Audio Gadget 2ch 48k to ${OUTPUT_CARD}"
description: "Host USB-C audio output -> Raspberry Pi UAC2Gadget stereo ALSA capture -> CamillaDSP -> ${OUTPUT_CARD} playback. Fixed 48 kHz / S32_LE."

devices:
  samplerate: 48000
  chunksize: 256
  target_level: 768
  adjust_period: 10
  capture:
    type: Alsa
    channels: 2
    device: "hw:CARD=UAC2Gadget,DEV=0"
    format: S32_LE
  playback:
    type: Alsa
    channels: 2
    device: "hw:CARD=${OUTPUT_CARD},DEV=${OUTPUT_DEV}"
    format: S32_LE

mixers:
  passthrough_2x2:
    channels:
      in: 2
      out: 2
    mapping:
      - dest: 0
        sources:
          - channel: 0
            gain: 0
            inverted: false
      - dest: 1
        sources:
          - channel: 1
            gain: 0
            inverted: false

pipeline:
  - type: Mixer
    name: passthrough_2x2
EOF

owner="${SUDO_USER:-root}"
if id "$owner" >/dev/null 2>&1; then
  chown "$owner:$owner" "$CAMILLA_CONFIG"
fi

if [ -x "$CAMILLA_BIN" ]; then
  "$CAMILLA_BIN" -c "$CAMILLA_CONFIG"
else
  echo "Warning: $CAMILLA_BIN not found; CamillaDSP config was written but not validated."
fi

if [ -f /etc/systemd/system/camilladsp.service ]; then
  python3 - "$CAMILLA_CONFIG" <<'PY'
from pathlib import Path
import sys

service = Path("/etc/systemd/system/camilladsp.service")
config = sys.argv[1]
text = service.read_text()

if "After=systemd-modules-load.service sound.target" not in text:
    text = text.replace("After=sound.target", "After=systemd-modules-load.service sound.target")

lines = []
for line in text.splitlines():
    if line.startswith("ExecStart="):
        line = (
            "ExecStart=/usr/local/bin/camilladsp -l info "
            "-o /var/log/camilladsp/camilladsp.log -w -p 1234 "
            "-s /home/rosco/myCamillaDSP/statefile.yml "
            + config
        )
    lines.append(line)

service.write_text("\n".join(lines) + "\n")
PY
  systemctl daemon-reload
  systemctl enable camilladsp.service >/dev/null
fi

systemctl disable --now raspiaudio-radio.service raspiaudio-radio-boot.service >/dev/null 2>&1 || true

echo "Backup: $BACKUP_DIR"
echo "Wrote: $CAMILLA_CONFIG"
echo "Reboot, then run: ./scripts/diagnose_usb_audio_gadget_pi5.sh"
