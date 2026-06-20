#!/usr/bin/env bash
set -euo pipefail

CAMILLA_VERSION="${CAMILLA_VERSION:-4.1.3}"
CAMILLA_GUI_VERSION="${CAMILLA_GUI_VERSION:-4.1.0}"
INSTALL_GUI="${INSTALL_GUI:-1}"
SAMPLE_RATE="${SAMPLE_RATE:-48000}"
CHANNEL_MASK="${CHANNEL_MASK:-0x63f}"
SAMPLE_SIZE_BYTES="${SAMPLE_SIZE_BYTES:-4}"
PRODUCT_ID="${PRODUCT_ID:-0x0108}"
PRODUCT_SUFFIX="${PRODUCT_SUFFIX:-7_1_48k}"
REBOOT_NOW="${REBOOT_NOW:-ask}"
OUTPUT_DEVICE="${OUTPUT_DEVICE:-}"
BOOT_CONFIG="${BOOT_CONFIG:-/boot/firmware/config.txt}"

if [ "$(id -u)" -ne 0 ]; then
  exec sudo -E bash "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

DEFAULT_USER="${SUDO_USER:-}"
if [ -z "$DEFAULT_USER" ] || [ "$DEFAULT_USER" = "root" ]; then
  DEFAULT_USER="$(getent passwd 1000 | cut -d: -f1 || true)"
fi
TARGET_USER="${RASPIAUDIO_USER:-$DEFAULT_USER}"
if [ -z "$TARGET_USER" ] || ! getent passwd "$TARGET_USER" >/dev/null; then
  echo "Set RASPIAUDIO_USER to the Linux user that should run CamillaDSP." >&2
  exit 1
fi
TARGET_GROUP="$(id -gn "$TARGET_USER")"

CONFIG_DIR="/etc/camilladsp"
COEFF_DIR="$CONFIG_DIR/coeffs"
STATEFILE="/var/lib/camilladsp/statefile.yml"
LOG_FILE="/var/log/camilladsp/camilladsp.log"
CURRENT_CONFIG="$CONFIG_DIR/raspiaudio_usb_7_1_48k_passthrough.yml"
BACKUP_DIR="/root/raspiaudio-camilladsp-backups/quickstart-$(date +%Y%m%d-%H%M%S)"

download() {
  local url="$1"
  local dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fL "$url" -o "$dest"
  else
    wget -O "$dest" "$url"
  fi
}

install_packages() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y ca-certificates curl wget tar gzip alsa-utils python3 git
}

backup_file() {
  local file="$1"
  [ -e "$file" ] || return 0
  mkdir -p "$BACKUP_DIR"
  cp -a "$file" "$BACKUP_DIR/$(echo "$file" | tr / _).bak"
}

configure_boot() {
  if [ ! -f "$BOOT_CONFIG" ]; then
    if [ -f /boot/config.txt ]; then
      BOOT_CONFIG="/boot/config.txt"
    else
      echo "Missing Raspberry Pi boot config. Expected /boot/firmware/config.txt." >&2
      exit 1
    fi
  fi

  backup_file "$BOOT_CONFIG"
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
        out.append("#" + line.lstrip("#") + " # disabled duplicate/stale by RASPIAUDIO installer")
        continue

    out.append(line)
    if stripped == "[all]" and not inserted:
        out.append("dtoverlay=dwc2,dr_mode=peripheral # RASPIAUDIO USB Audio 7.1 gadget")
        inserted = True

if not inserted:
    out.append("[all]")
    out.append("dtoverlay=dwc2,dr_mode=peripheral # RASPIAUDIO USB Audio 7.1 gadget")

p.write_text("\n".join(out) + "\n")
PY
}

configure_modules() {
  backup_file /etc/modules-load.d/raspiaudio-usb-audio.conf
  backup_file /etc/modprobe.d/usb_g_audio.conf

  cat >/etc/modules-load.d/raspiaudio-usb-audio.conf <<'EOF'
i2c-dev
dwc2
g_audio
EOF

  cat >/etc/modprobe.d/usb_g_audio.conf <<EOF
# RASPIAUDIO USB Audio Gadget 7.1 profile.
# Pi ALSA capture = audio sent by the USB host to the Raspberry Pi.
# c_chmask=${CHANNEL_MASK}: 7.1 FL,FR,FC,LFE,BL,BR,SL,SR.
# c_ssize=${SAMPLE_SIZE_BYTES}: S32_LE when set to 4. c_srate=${SAMPLE_RATE}: fixed sample rate.
# p_chmask=0: no microphone endpoint from Pi back to the host.
# idVendor/idProduct are lab values; use a real VID/PID for a commercial product.
options g_audio c_srate=${SAMPLE_RATE} c_ssize=${SAMPLE_SIZE_BYTES} c_chmask=${CHANNEL_MASK} p_chmask=0 iManufacturer=RASPIAUDIO iProduct=RASPIAUDIO_8xOUT_USB_DSP_${PRODUCT_SUFFIX} iSerialNumber=RASPIAUDIO-PI5-${PRODUCT_SUFFIX} idVendor=0x1d6b idProduct=${PRODUCT_ID}
EOF
}

install_camilladsp() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    aarch64|arm64) bundle_arch="aarch64" ;;
    armv7l|armv7*) bundle_arch="armv7" ;;
    armv6l|armv6*) bundle_arch="armv6" ;;
    x86_64|amd64) bundle_arch="amd64" ;;
    *)
      echo "Unsupported architecture for CamillaDSP bundle: $arch" >&2
      exit 1
      ;;
  esac

  local work url archive
  work="$(mktemp -d)"
  url="https://github.com/HEnquist/camilladsp/releases/download/v${CAMILLA_VERSION}/camilladsp-linux-${bundle_arch}.tar.gz"
  archive="$work/camilladsp.tar.gz"
  download "$url" "$archive"
  tar -xzf "$archive" -C "$work"
  install -m 0755 "$work/camilladsp" /usr/local/bin/camilladsp
  rm -rf "$work"
}

detect_output_device() {
  if [ -n "$OUTPUT_DEVICE" ]; then
    echo "$OUTPUT_DEVICE"
    return 0
  fi

  python3 <<'PY'
import re
import subprocess
import sys

try:
    text = subprocess.check_output(["aplay", "-l"], text=True, stderr=subprocess.DEVNULL)
except Exception:
    text = ""

candidates = []
for line in text.splitlines():
    m = re.search(r"card\s+(\d+):\s*([^\s\[]+).*device\s+(\d+):", line)
    if not m:
        continue
    card_no, card_name, dev_no = m.groups()
    lower = line.lower()
    if "hdmi" in lower or "vc4" in lower or "uac2" in lower or "gadget" in lower:
        continue
    score = 0
    if any(token in lower for token in ("raspiaudio", "hifiberry", "dac8", "sndrpi")):
        score += 10
    candidates.append((score, card_name, dev_no, card_no, line))

if candidates:
    candidates.sort(reverse=True)
    _, card_name, dev_no, _, _ = candidates[0]
    print(f"hw:CARD={card_name},DEV={dev_no}")
else:
    print("hw:CARD=sndrpihifiberry,DEV=0")
    print("WARNING: no non-HDMI ALSA playback card was detected; using the usual RASPIAUDIO fallback.", file=sys.stderr)
PY
}

write_camilla_config() {
  local playback_device="$1"
  install -d -o "$TARGET_USER" -g audio -m 0775 "$CONFIG_DIR" "$COEFF_DIR"
  install -d -o "$TARGET_USER" -g audio -m 0755 /var/lib/camilladsp /var/log/camilladsp

  cat >"$CURRENT_CONFIG" <<EOF
---
title: "RASPIAUDIO USB 7.1 48k to 8xOUT passthrough"
description: "USB host 7.1 playback -> Raspberry Pi USB audio gadget capture -> CamillaDSP -> RASPIAUDIO 8xOUT analog outputs. Direct one-to-one routing."

devices:
  samplerate: ${SAMPLE_RATE}
  chunksize: 256
  queuelimit: 8
  target_level: 768
  adjust_period: 1
  enable_rate_adjust: true
  capture:
    type: Alsa
    channels: 8
    device: "hw:CARD=UAC2Gadget,DEV=0"
    format: S32_LE
  playback:
    type: Alsa
    channels: 8
    device: "${playback_device}"
    format: S32_LE

mixers:
  usb_7_1_to_8xout_passthrough:
    channels:
      in: 8
      out: 8
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
      - dest: 2
        sources:
          - channel: 2
            gain: 0
            inverted: false
      - dest: 3
        sources:
          - channel: 3
            gain: 0
            inverted: false
      - dest: 4
        sources:
          - channel: 4
            gain: 0
            inverted: false
      - dest: 5
        sources:
          - channel: 5
            gain: 0
            inverted: false
      - dest: 6
        sources:
          - channel: 6
            gain: 0
            inverted: false
      - dest: 7
        sources:
          - channel: 7
            gain: 0
            inverted: false

pipeline:
  - type: Mixer
    name: usb_7_1_to_8xout_passthrough
EOF

  chown "$TARGET_USER:audio" "$CURRENT_CONFIG"
  if compgen -G "$REPO_DIR/configs/*.yml" >/dev/null; then
    install -m 0644 -o "$TARGET_USER" -g audio "$REPO_DIR"/configs/*.yml "$CONFIG_DIR"/
    python3 - "$CONFIG_DIR" "$playback_device" <<'PY'
import pathlib
import sys

config_dir = pathlib.Path(sys.argv[1])
playback_device = sys.argv[2]
new = f'device: "{playback_device}"'

for path in config_dir.glob("*.yml"):
    text = path.read_text(encoding="utf-8")
    updated = text.replace('device: "hw:CARD=sndrpihifiberry,DEV=0"', new)
    updated = updated.replace("device: hw:CARD=sndrpihifiberry,DEV=0", new)
    if updated != text:
        path.write_text(updated, encoding="utf-8")
PY
    echo "Installed example CamillaDSP profiles in $CONFIG_DIR"
  fi

  if /usr/local/bin/camilladsp --help 2>&1 | grep -q -- "--check"; then
    /usr/local/bin/camilladsp --check "$CURRENT_CONFIG"
  else
    echo "CamillaDSP has no --check option in this build; skipping config validation."
  fi
}

write_camilladsp_service() {
  backup_file /etc/systemd/system/camilladsp.service
  cat >/etc/systemd/system/camilladsp.service <<EOF
[Unit]
Description=CamillaDSP audio processor for RASPIAUDIO 8xOUT USB 7.1
After=systemd-modules-load.service sound.target
Wants=sound.target

[Service]
Type=simple
User=${TARGET_USER}
Group=audio
SupplementaryGroups=audio
StateDirectory=camilladsp
LogsDirectory=camilladsp
ExecStart=/usr/local/bin/camilladsp -l info -o ${LOG_FILE} -w -p 1234 -s ${STATEFILE} ${CURRENT_CONFIG}
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable camilladsp.service >/dev/null
}

install_camillagui() {
  [ "$INSTALL_GUI" = "1" ] || return 0

  local arch bundle_arch work url archive install_dir link_dir
  arch="$(uname -m)"
  case "$arch" in
    aarch64|arm64) bundle_arch="aarch64" ;;
    armv7l|armv7*) bundle_arch="armv7" ;;
    armv6l|armv6*) bundle_arch="armv6" ;;
    x86_64|amd64) bundle_arch="amd64" ;;
    *) echo "Skipping CamillaGUI on unsupported architecture: $arch"; return 0 ;;
  esac

  work="$(mktemp -d)"
  url="https://github.com/HEnquist/camillagui-backend/releases/download/v${CAMILLA_GUI_VERSION}/bundle_linux_${bundle_arch}.tar.gz"
  archive="$work/camillagui-backend.tar.gz"
  install_dir="/opt/camillagui-backend-v${CAMILLA_GUI_VERSION}"
  link_dir="/opt/camillagui-backend"

  download "$url" "$archive"
  tar -xzf "$archive" -C "$work"
  test -x "$work/camillagui_backend/camillagui_backend"

  rm -rf "$install_dir"
  install -d -m 0755 "$install_dir"
  cp -a "$work/camillagui_backend/." "$install_dir"/
  chown -R root:root "$install_dir"
  ln -sfn "$install_dir" "$link_dir"
  rm -rf "$work"

  cat >"$install_dir/_internal/config/camillagui.yml" <<EOF
---
camilla_host: "127.0.0.1"
camilla_port: 1234
bind_address: "0.0.0.0"
port: 5005
ssl_certificate: null
ssl_private_key: null
gui_config_file: null
config_dir: "${CONFIG_DIR}"
coeff_dir: "${COEFF_DIR}"
default_config: "${CURRENT_CONFIG}"
statefile_path: "${STATEFILE}"
log_file: "${LOG_FILE}"
supported_capture_types: ["Alsa", "File", "Stdin", "SignalGenerator"]
supported_playback_types: ["Alsa", "File", "Stdout"]
EOF

  backup_file /etc/systemd/system/camillagui.service
  cat >/etc/systemd/system/camillagui.service <<EOF
[Unit]
Description=CamillaDSP GUI backend
After=network-online.target camilladsp.service
Wants=network-online.target

[Service]
Type=simple
User=${TARGET_USER}
Group=audio
WorkingDirectory=${link_dir}
ExecStart=${link_dir}/camillagui_backend
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable camillagui.service >/dev/null
}

finish_services() {
  usermod -aG audio "$TARGET_USER" || true
  systemctl disable --now raspiaudio-radio.service raspiaudio-radio-boot.service >/dev/null 2>&1 || true
  systemctl restart camilladsp.service || true
  if [ "$INSTALL_GUI" = "1" ]; then
    systemctl restart camillagui.service || true
  fi
}

print_summary() {
  local ip
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  echo
  echo "RASPIAUDIO USB 7.1 installer complete."
  echo "Backup directory: $BACKUP_DIR"
  echo "CamillaDSP config: $CURRENT_CONFIG"
  echo "USB gadget config: /etc/modprobe.d/usb_g_audio.conf"
  echo "A reboot is required before Windows/macOS/Linux sees the new USB 7.1 device."
  echo
  echo "After reboot, connect the USB-C gadget cable to the computer and open:"
  if [ -n "$ip" ]; then
    echo "  http://$ip:5005/gui/index.html"
  else
    echo "  http://<raspberry-pi-ip>:5005/gui/index.html"
  fi
  echo
  echo "Verification command:"
  echo "  cd $REPO_DIR"
  echo "  ./profiles/raspiaudio_8xout_usb_7_1_quickstart/verify.sh"
}

main() {
  mkdir -p "$BACKUP_DIR"
  install_packages
  configure_boot
  configure_modules
  install_camilladsp
  playback_device="$(detect_output_device)"
  echo "Detected the RASPIAUDIO ALSA playback device for CamillaDSP."
  write_camilla_config "$playback_device"
  write_camilladsp_service
  install_camillagui
  finish_services
  print_summary

  case "$REBOOT_NOW" in
    1|yes|YES|true|TRUE)
      reboot
      ;;
    ask)
      if [ -t 0 ]; then
        printf "Reboot now? [Y/n] "
        read -r answer
        case "$answer" in
          n|N|no|NO) echo "Reboot later with: sudo reboot" ;;
          *) reboot ;;
        esac
      else
        echo "Reboot later with: sudo reboot"
      fi
      ;;
    *)
      echo "Reboot later with: sudo reboot"
      ;;
  esac
}

main "$@"
