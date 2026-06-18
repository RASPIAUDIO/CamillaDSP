#!/usr/bin/env bash
set -euo pipefail

SAMPLE_RATE="${SAMPLE_RATE:-48000}"
CHANNEL_MASK="${CHANNEL_MASK:-0x63f}"
SAMPLE_SIZE_BYTES="${SAMPLE_SIZE_BYTES:-4}"
PRODUCT_ID="${PRODUCT_ID:-0x0108}"
PRODUCT_SUFFIX="${PRODUCT_SUFFIX:-7_1_48k}"
OUTPUT_CARD="${OUTPUT_CARD:-XMOSDevice}"
OUTPUT_DEV="${OUTPUT_DEV:-0}"
PI_USER="${SUDO_USER:-$USER}"
CAMILLA_CONFIG_DIR="${CAMILLA_CONFIG_DIR:-/home/${PI_USER}/myCamillaDSP/configs}"
CAMILLA_CURRENT="${CAMILLA_CURRENT:-$CAMILLA_CONFIG_DIR/current.yml}"
CAMILLA_TARGET="${CAMILLA_TARGET:-$CAMILLA_CONFIG_DIR/usb_gadget_7_1_${SAMPLE_RATE}_to_8xout.yml}"
CAMILLA_BIN="${CAMILLA_BIN:-/usr/local/bin/camilladsp}"
BOOT_CONFIG="${BOOT_CONFIG:-/boot/firmware/config.txt}"
BACKUP_DIR="/root/codex-backups/usb-gadget-7-1-${SAMPLE_RATE}-$(date +%Y%m%d-%H%M%S)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/camilladsp_usb_7_1_48k_to_8xout.yml"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run with sudo."
  exit 1
fi

if [ ! -f "$BOOT_CONFIG" ]; then
  echo "Missing $BOOT_CONFIG"
  exit 1
fi

if [ ! -f "$TEMPLATE" ]; then
  echo "Missing template: $TEMPLATE"
  exit 1
fi

case "$SAMPLE_RATE" in
  44100|48000|88200|96000|176400|192000) ;;
  *)
    echo "Refusing unusual SAMPLE_RATE=$SAMPLE_RATE"
    echo "Set SAMPLE_RATE to one of: 44100, 48000, 88200, 96000, 176400, 192000."
    exit 1
    ;;
esac

mkdir -p "$BACKUP_DIR" "$CAMILLA_CONFIG_DIR" /var/log/camilladsp

for file in \
  "$BOOT_CONFIG" \
  /etc/modules \
  /etc/modules-load.d/modules.conf \
  /etc/modprobe.d/usb_g_audio.conf \
  /etc/systemd/system/camilladsp.service \
  "$CAMILLA_CURRENT"; do
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
        out.append("dtoverlay=dwc2,dr_mode=peripheral # RASPIAUDIO USB Audio Gadget 7.1")
        inserted = True

if not inserted:
    out.append("[all]")
    out.append("dtoverlay=dwc2,dr_mode=peripheral # RASPIAUDIO USB Audio Gadget 7.1")

p.write_text("\n".join(out) + "\n")
PY

cat >/etc/modules <<'EOF'
# /etc/modules: kernel modules to load at boot time.
# Minimal RASPIAUDIO USB Audio Gadget setup.

i2c-dev
dwc2
g_audio
EOF

if [ "$(readlink -f /etc/modules)" != "$(readlink -f /etc/modules-load.d/modules.conf 2>/dev/null || true)" ]; then
  cp /etc/modules /etc/modules-load.d/modules.conf
fi

cat >/etc/modprobe.d/usb_g_audio.conf <<EOF
# RASPIAUDIO USB Audio Gadget 7.1 profile.
# Gadget-side ALSA capture = host-side speaker/playback endpoint.
# c_chmask=${CHANNEL_MASK}: 7.1 FL,FR,FC,LFE,BL,BR,SL,SR.
# c_ssize=${SAMPLE_SIZE_BYTES}: S32_LE when set to 4. c_srate=${SAMPLE_RATE}: fixed sample rate.
# p_chmask=0: no Pi-to-host microphone endpoint in this profile.
# idVendor/idProduct are lab values; use a real VID/PID for product.
options g_audio c_srate=${SAMPLE_RATE} c_ssize=${SAMPLE_SIZE_BYTES} c_chmask=${CHANNEL_MASK} p_chmask=0 iManufacturer=RASPIAUDIO iProduct=RASPIAUDIO_USB_DSP_${PRODUCT_SUFFIX} iSerialNumber=RASPIAUDIO-PI5-${PRODUCT_SUFFIX} idVendor=0x1d6b idProduct=${PRODUCT_ID}
EOF

python3 - "$TEMPLATE" "$CAMILLA_TARGET" "$SAMPLE_RATE" "$OUTPUT_CARD" "$OUTPUT_DEV" <<'PY'
from pathlib import Path
import sys

src, dst, rate, card, dev = sys.argv[1:]
text = Path(src).read_text()
text = text.replace('samplerate: 48000', f'samplerate: {rate}')
text = text.replace('chunksize: 256', 'chunksize: 256')
text = text.replace('target_level: 768', 'target_level: 768')
text = text.replace('device: "hw:CARD=XMOSDevice,DEV=0"', f'device: "hw:CARD={card},DEV={dev}"')
text = text.replace('7.1 48k', f'7.1 {int(rate)//1000}k')
text = text.replace('48k to 8xOUT', f'{int(rate)//1000}k to 8xOUT')
Path(dst).write_text(text)
PY

cp "$CAMILLA_TARGET" "$CAMILLA_CURRENT"
owner="${SUDO_USER:-root}"
if id "$owner" >/dev/null 2>&1; then
  chown "$owner:$owner" "$CAMILLA_TARGET" "$CAMILLA_CURRENT"
fi

if [ -x "$CAMILLA_BIN" ]; then
  if "$CAMILLA_BIN" --help 2>&1 | grep -q -- "--check"; then
    "$CAMILLA_BIN" --check "$CAMILLA_CURRENT"
  else
    echo "Warning: $CAMILLA_BIN has no --check option; config was written but not validated here."
  fi
else
  echo "Warning: $CAMILLA_BIN not found; CamillaDSP config was written but not validated."
fi

if [ -f /etc/systemd/system/camilladsp.service ]; then
  python3 - "$CAMILLA_CURRENT" <<'PY'
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
  systemctl restart camilladsp.service || true
fi

echo "Backup: $BACKUP_DIR"
echo "Gadget: /etc/modprobe.d/usb_g_audio.conf"
echo "CamillaDSP target: $CAMILLA_TARGET"
echo "CamillaDSP current: $CAMILLA_CURRENT"
echo "Reboot is required for the USB descriptor to be re-enumerated by the host."
