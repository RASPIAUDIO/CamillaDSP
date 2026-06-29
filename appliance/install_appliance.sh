#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  exec sudo -E bash "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

HARDWARE="${RASPIAUDIO_HARDWARE:-auto}"
ACTIVE_MODE="${RASPIAUDIO_ACTIVE_MODE:-usb_7_1_to_8out}"
SAMPLE_RATE="${RASPIAUDIO_SAMPLE_RATE:-48000}"
ADC_DRIVER_OPTION="${RASPIAUDIO_ADC_DRIVER_OPTION:-}"
INSTALL_SPDIF_DRIVER="${INSTALL_SPDIF_DRIVER:-1}"
REBOOT_NOW="${REBOOT_NOW:-0}"
IMAGE_BUILD="${RASPIAUDIO_IMAGE_BUILD:-0}"

systemctl_enable() {
  systemctl enable "$@" >/dev/null 2>&1 || {
    if [ "$IMAGE_BUILD" = "1" ]; then
      echo "Warning: systemctl enable failed in image build context: $*" >&2
      return 0
    fi
    return 1
  }
}

systemctl_daemon_reload() {
  [ "$IMAGE_BUILD" = "1" ] && return 0
  systemctl daemon-reload
}

systemctl_restart() {
  [ "$IMAGE_BUILD" = "1" ] && return 0
  systemctl restart "$@" || true
}

set_local_hostname_files() {
  local name="$1"
  printf '%s\n' "$name" >/etc/hostname
  if [ -f /etc/hosts ]; then
    if grep -qE '^127\.0\.1\.1[[:space:]]+' /etc/hosts; then
      sed -i -E "s/^127\.0\.1\.1[[:space:]].*/127.0.1.1\t${name}/" /etc/hosts
    else
      printf '127.0.1.1\t%s\n' "$name" >>/etc/hosts
    fi
  fi
}

install_packages() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y \
    avahi-daemon \
    build-essential \
    ca-certificates \
    curl \
    git \
    kmod \
    linux-headers-rpi-2712 \
    nginx \
    python3 \
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
  [ "$INSTALL_SPDIF_DRIVER" = "0" ] && return 0
  install -d -m 0755 /opt/raspiaudio-spdif-gpio
  cp -a "$REPO_DIR/prototypes/pi5_spdif_gpio/kernel" /opt/raspiaudio-spdif-gpio/
  install -m 0755 "$SCRIPT_DIR/bin/raspiaudio-install-spdif-driver" /usr/local/sbin/raspiaudio-install-spdif-driver
  install -m 0644 "$SCRIPT_DIR/systemd/raspiaudio-spdif-firstboot.service" /etc/systemd/system/raspiaudio-spdif-firstboot.service
  install -m 0644 "$SCRIPT_DIR/systemd/raspiaudio-spdif.service" /etc/systemd/system/raspiaudio-spdif.service

  if [ "$IMAGE_BUILD" = "1" ] || [ "$INSTALL_SPDIF_DRIVER" = "defer" ]; then
    systemctl_enable raspiaudio-spdif-firstboot.service raspiaudio-spdif.service
    return 0
  fi

  if [ -d /sys/firmware/devicetree/base ] && command -v uname >/dev/null 2>&1; then
    /usr/local/sbin/raspiaudio-install-spdif-driver || {
      echo "Warning: S/PDIF driver install failed; optical mode can be installed later." >&2
      systemctl_enable raspiaudio-spdif-firstboot.service
    }
  else
    echo "Deferring S/PDIF driver install until first Raspberry Pi boot."
    systemctl_enable raspiaudio-spdif-firstboot.service
  fi
}

install_version_file() {
  local version="${RASPIAUDIO_RELEASE_VERSION:-}"
  if [ -z "$version" ] && [ -f "$SCRIPT_DIR/VERSION" ]; then
    version="$(cat "$SCRIPT_DIR/VERSION")"
  fi
  [ -n "$version" ] || version="unknown"
  printf '%s\n' "$version" >/etc/raspiaudio/version
}

install_appliance_files() {
  install -d -m 0755 /usr/local/sbin /opt/raspiaudio-web /etc/raspiaudio
  install -m 0755 "$SCRIPT_DIR/bin/raspiaudio-mode" /usr/local/sbin/raspiaudio-mode
  install -m 0755 "$SCRIPT_DIR/bin/raspiaudio-health" /usr/local/sbin/raspiaudio-health
  install -m 0755 "$SCRIPT_DIR/bin/raspiaudio-diagnostics" /usr/local/sbin/raspiaudio-diagnostics
  install -m 0755 "$SCRIPT_DIR/bin/raspiaudio-fix-audio" /usr/local/sbin/raspiaudio-fix-audio
  install -m 0755 "$SCRIPT_DIR/bin/raspiaudio-restart-usb-gadget" /usr/local/sbin/raspiaudio-restart-usb-gadget
  install -m 0755 "$SCRIPT_DIR/bin/raspiaudio-test-audio" /usr/local/sbin/raspiaudio-test-audio
  install -m 0755 "$SCRIPT_DIR/bin/raspiaudio-update-system" /usr/local/sbin/raspiaudio-update-system
  install -m 0755 "$SCRIPT_DIR/bin/raspiaudio-validate-release" /usr/local/sbin/raspiaudio-validate-release
  install -m 0755 "$SCRIPT_DIR/bin/raspiaudio-dev-update" /usr/local/sbin/raspiaudio-dev-update
  install -m 0755 "$SCRIPT_DIR/web/raspiaudio_web.py" /opt/raspiaudio-web/raspiaudio_web.py
  install_version_file

  cat >/etc/raspiaudio/box.conf <<EOF
hardware=${HARDWARE}
active_mode=${ACTIVE_MODE}
sample_rate=${SAMPLE_RATE}
# Hardware can be auto, 8xout or 8xin8xout.
# Auto mode relies on the hifiberry-dac8x overlay/driver:
# the official overlay exposes hasadc-gpio on GPIO5 active-low, and
# the resulting ALSA capture card tells us whether ADC is present.
#
# Legacy optional driver option. Leave empty unless a lab driver explicitly
# requires a module option to expose the ADC path.
adc_driver_option=${ADC_DRIVER_OPTION}
EOF
}

install_services() {
  install -m 0644 "$SCRIPT_DIR/systemd/camilladsp-appliance.service" /etc/systemd/system/camilladsp.service
  install -m 0644 "$SCRIPT_DIR/systemd/raspiaudio-web.service" /etc/systemd/system/raspiaudio-web.service

  rm -f /etc/nginx/sites-enabled/default
  install -m 0644 "$SCRIPT_DIR/nginx/raspiaudio.conf" /etc/nginx/sites-available/raspiaudio.conf
  ln -sfn /etc/nginx/sites-available/raspiaudio.conf /etc/nginx/sites-enabled/raspiaudio.conf

  systemctl_daemon_reload
  systemctl_enable avahi-daemon nginx raspiaudio-spdif.service camilladsp.service camillagui.service raspiaudio-web.service
}

configure_hostname() {
  set_local_hostname_files raspiaudio
  if [ "$IMAGE_BUILD" != "1" ]; then
    hostnamectl set-hostname raspiaudio || true
  fi
}

activate_default_mode() {
  /usr/local/sbin/raspiaudio-mode apply-hardware
  /usr/local/sbin/raspiaudio-mode set "$ACTIVE_MODE"
}

restart_services() {
  systemctl_restart avahi-daemon
  systemctl_restart nginx
  systemctl_restart raspiaudio-spdif.service
  systemctl_restart camilladsp.service
  systemctl_restart camillagui.service
  systemctl_restart raspiaudio-web.service
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
    auto|8xout|8xin8xout) ;;
    *) echo "RASPIAUDIO_HARDWARE must be auto, 8xout or 8xin8xout." >&2; exit 1 ;;
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
