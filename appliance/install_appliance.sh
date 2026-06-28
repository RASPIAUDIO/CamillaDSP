#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  exec sudo -E bash "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

HARDWARE="${RASPIAUDIO_HARDWARE:-8xout}"
ACTIVE_MODE="${RASPIAUDIO_ACTIVE_MODE:-usb_7_1_to_8out}"
SAMPLE_RATE="${RASPIAUDIO_SAMPLE_RATE:-48000}"
ADC_DRIVER_OPTION="${RASPIAUDIO_ADC_DRIVER_OPTION:-}"
INSTALL_SPDIF_DRIVER="${INSTALL_SPDIF_DRIVER:-1}"
REBOOT_NOW="${REBOOT_NOW:-0}"

install_packages() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y \
    avahi-daemon \
    ca-certificates \
    curl \
    git \
    nginx \
    python3 \
    raspberrypi-kernel-headers \
    tar \
    wget \
    zip \
    alsa-utils \
    ffmpeg
}

install_system_user() {
  if ! getent passwd raspiaudio >/dev/null; then
    useradd --system --home /var/lib/raspiaudio --create-home --groups audio raspiaudio
  fi
  usermod -aG audio raspiaudio || true
}

install_base_audio_stack() {
  INSTALL_GUI=1 REBOOT_NOW=0 RASPIAUDIO_USER=raspiaudio \
    "$REPO_DIR/profiles/raspiaudio_8xout_usb_7_1_quickstart/install.sh"
}

install_profiles() {
  install -d -o raspiaudio -g audio -m 0775 /etc/camilladsp /etc/camilladsp/coeffs
  install -m 0644 -o raspiaudio -g audio "$REPO_DIR"/configs/*.yml /etc/camilladsp/
  python3 "$REPO_DIR/scripts/generate_fir_load_coeffs.py" \
    /etc/camilladsp/coeffs/fir_load_4096_taps.txt
  chown -R raspiaudio:audio /etc/camilladsp
}

install_spdif_driver() {
  [ "$INSTALL_SPDIF_DRIVER" = "1" ] || return 0
  if [ -d /sys/firmware/devicetree/base ] && command -v uname >/dev/null 2>&1; then
    "$REPO_DIR/prototypes/pi5_spdif_gpio/scripts/install_kernel_spdif_on_pi5.sh" || {
      echo "Warning: S/PDIF driver install failed; optical mode can be installed later." >&2
    }
  else
    echo "Skipping S/PDIF driver install outside a running Raspberry Pi system."
  fi
}

install_appliance_files() {
  install -d -m 0755 /usr/local/sbin /opt/raspiaudio-web /etc/raspiaudio
  install -m 0755 "$SCRIPT_DIR/bin/raspiaudio-mode" /usr/local/sbin/raspiaudio-mode
  install -m 0755 "$SCRIPT_DIR/bin/raspiaudio-diagnostics" /usr/local/sbin/raspiaudio-diagnostics
  install -m 0755 "$SCRIPT_DIR/bin/raspiaudio-test-audio" /usr/local/sbin/raspiaudio-test-audio
  install -m 0755 "$SCRIPT_DIR/web/raspiaudio_web.py" /opt/raspiaudio-web/raspiaudio_web.py

  cat >/etc/raspiaudio/box.conf <<EOF
hardware=${HARDWARE}
active_mode=${ACTIVE_MODE}
sample_rate=${SAMPLE_RATE}
# For 8xIN+8xOUT images, set this to the exact driver option that enables ADC
# input loading in the hifiberry-dac8x based RASPIAUDIO overlay.
adc_driver_option=${ADC_DRIVER_OPTION}
EOF
}

install_services() {
  install -m 0644 "$SCRIPT_DIR/systemd/camilladsp-appliance.service" /etc/systemd/system/camilladsp.service
  install -m 0644 "$SCRIPT_DIR/systemd/raspiaudio-web.service" /etc/systemd/system/raspiaudio-web.service

  rm -f /etc/nginx/sites-enabled/default
  install -m 0644 "$SCRIPT_DIR/nginx/raspiaudio.conf" /etc/nginx/sites-available/raspiaudio.conf
  ln -sfn /etc/nginx/sites-available/raspiaudio.conf /etc/nginx/sites-enabled/raspiaudio.conf

  systemctl daemon-reload
  systemctl enable avahi-daemon nginx camilladsp.service camillagui.service raspiaudio-web.service >/dev/null
}

configure_hostname() {
  hostnamectl set-hostname raspiaudio || true
}

activate_default_mode() {
  /usr/local/sbin/raspiaudio-mode apply-hardware
  /usr/local/sbin/raspiaudio-mode set "$ACTIVE_MODE"
}

restart_services() {
  systemctl restart avahi-daemon || true
  systemctl restart nginx || true
  systemctl restart camilladsp.service || true
  systemctl restart camillagui.service || true
  systemctl restart raspiaudio-web.service || true
}

print_summary() {
  cat <<EOF

RASPIAUDIO CamillaDSP Box appliance install complete.

Open:
  http://raspiaudio.local/

Advanced CamillaDSP editor:
  http://raspiaudio.local:5005/gui/index.html

Current mode:
  $(/usr/local/sbin/raspiaudio-mode status 2>/dev/null || true)

A reboot is recommended before host USB audio testing.
EOF
}

main() {
  case "$HARDWARE" in
    8xout|8xin8xout) ;;
    *) echo "RASPIAUDIO_HARDWARE must be 8xout or 8xin8xout." >&2; exit 1 ;;
  esac

  install_packages
  install_system_user
  install_base_audio_stack
  install_profiles
  install_spdif_driver
  install_appliance_files
  install_services
  configure_hostname
  activate_default_mode
  restart_services
  print_summary

  if [ "$REBOOT_NOW" = "1" ]; then
    reboot
  fi
}

main "$@"
