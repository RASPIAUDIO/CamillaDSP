#!/usr/bin/env bash
set -euo pipefail

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

if lsmod | grep -q "^${MODULE_NAME}[[:space:]]"; then
  if ! sudo modprobe -r "$MODULE_NAME" 2>/dev/null; then
    if [[ "${FORCE_AUDIO_STOP:-0}" = "1" ]]; then
      echo "${MODULE_NAME} is busy; stopping user PipeWire/WirePlumber and retrying."
      stop_user_audio_services
      sudo modprobe -r "$MODULE_NAME"
    else
      echo "${MODULE_NAME} is busy and was not unloaded." >&2
      echo "Close ALSA clients or retry with FORCE_AUDIO_STOP=1." >&2
      sudo fuser -v /dev/snd/* >&2 || true
      exit 1
    fi
  fi
fi

if lsmod | grep -q "^${MODULE_NAME}[[:space:]]"; then
  echo "${MODULE_NAME} is still loaded; refusing to remove ${MODULE_PATH}." >&2
  exit 1
fi

sudo rm -f "$MODULE_PATH"
sudo depmod
echo "Removed ${MODULE_NAME}."
