#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KERNEL_DIR="$PROJECT_DIR/kernel"
MODULE_NAME="raspiaudio_spdif_pio"
MODULE_PATH="/lib/modules/$(uname -r)/extra/${MODULE_NAME}.ko"

stop_user_audio_services() {
  local user="${SUDO_USER:-${USER:-}}"
  local uid=""

  if [[ -n "$user" ]] && uid="$(id -u "$user" 2>/dev/null)"; then
    sudo -u "$user" XDG_RUNTIME_DIR="/run/user/$uid" \
      systemctl --user stop wireplumber pipewire pipewire-pulse 2>/dev/null || true
  fi
}

unload_existing_module() {
  if ! lsmod | grep -q "^${MODULE_NAME}[[:space:]]"; then
    return 0
  fi

  if sudo modprobe -r "$MODULE_NAME" 2>/dev/null; then
    return 0
  fi

  if [[ "${FORCE_AUDIO_STOP:-0}" = "1" ]]; then
    echo "${MODULE_NAME} is busy; stopping user PipeWire/WirePlumber and retrying."
    stop_user_audio_services
    sudo modprobe -r "$MODULE_NAME"
    return 0
  fi

  echo "${MODULE_NAME} is already loaded and busy." >&2
  echo "Close ALSA clients or retry with FORCE_AUDIO_STOP=1." >&2
  sudo fuser -v /dev/snd/* >&2 || true
  exit 1
}

"$SCRIPT_DIR/build_kernel_spdif_on_pi5.sh"

unload_existing_module
sudo install -D -m 0644 "$KERNEL_DIR/${MODULE_NAME}.ko" "$MODULE_PATH"
sudo depmod
sudo modprobe rp1-pio
sudo modprobe "$MODULE_NAME" \
  gpio="${SPDIF_GPIO:-12}" \
  drive_ma="${SPDIF_DRIVE_MA:-8}" \
  zero_on_underrun="${SPDIF_ZERO_ON_UNDERRUN:-1}"

aplay -l | sed -n '/RASPISPDIF/,+2p'
echo "Installed ${MODULE_NAME}. Test with:"
echo "  $SCRIPT_DIR/test_kernel_spdif_alsa.sh"
