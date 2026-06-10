#!/usr/bin/env bash
set -euo pipefail

VERSION="${CAMILLA_GUI_VERSION:-4.1.0}"
DEFAULT_USER="${SUDO_USER:-$(id -un)}"
if [ "$DEFAULT_USER" = "root" ]; then
  DEFAULT_USER="$(getent passwd 1000 | cut -d: -f1 || true)"
fi
USER_NAME="${CAMILLA_USER:-$DEFAULT_USER}"
if [ -z "$USER_NAME" ] || ! getent passwd "$USER_NAME" >/dev/null; then
  echo "Set CAMILLA_USER to the Linux user that should run CamillaGUI." >&2
  exit 1
fi
USER_GROUP="$(id -gn "$USER_NAME")"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="${CAMILLA_CONFIG_DIR:-${REPO_DIR}/configs}"
COEFF_DIR="${CAMILLA_COEFF_DIR:-${REPO_DIR}/coeffs}"
STATEFILE="${CAMILLA_STATEFILE:-/var/lib/camilladsp/statefile.yml}"
LOG_FILE="${CAMILLA_LOG_FILE:-/var/log/camilladsp/camilladsp.log}"
INSTALL_DIR="/opt/camillagui-backend-v${VERSION}"
LINK_DIR="/opt/camillagui-backend"
WORK_DIR="$(mktemp -d)"
SERVICE_TMP="$(mktemp)"

cleanup() {
  rm -rf "$WORK_DIR"
  rm -f "$SERVICE_TMP"
}
trap cleanup EXIT

if ! sudo -v; then
  echo "sudo access is required for the CamillaGUI installation." >&2
  exit 1
fi

case "$(uname -m)" in
  aarch64|arm64)
    BUNDLE_ARCH="aarch64"
    ;;
  armv7l|armv7*)
    BUNDLE_ARCH="armv7"
    ;;
  armv6l|armv6*)
    BUNDLE_ARCH="armv6"
    ;;
  x86_64|amd64)
    BUNDLE_ARCH="amd64"
    ;;
  *)
    echo "Unsupported architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

URL="https://github.com/HEnquist/camillagui-backend/releases/download/v${VERSION}/bundle_linux_${BUNDLE_ARCH}.tar.gz"

mkdir -p "$CONFIG_DIR" "$COEFF_DIR"
sudo chown -R "$USER_NAME:$USER_GROUP" "$CONFIG_DIR" "$COEFF_DIR"
sudo install -d -o "$USER_NAME" -g audio -m 0755 /var/log/camilladsp /var/lib/camilladsp

cd "$WORK_DIR"
if command -v curl >/dev/null 2>&1; then
  curl -fL "$URL" -o camillagui-backend.tar.gz
else
  wget -O camillagui-backend.tar.gz "$URL"
fi

tar -xzf camillagui-backend.tar.gz
test -x camillagui_backend/camillagui_backend

sudo rm -rf "$INSTALL_DIR"
sudo install -d -m 0755 "$INSTALL_DIR"
sudo cp -a camillagui_backend/. "$INSTALL_DIR"/
sudo chown -R root:root "$INSTALL_DIR"
sudo ln -sfn "$INSTALL_DIR" "$LINK_DIR"

sudo tee "$INSTALL_DIR/_internal/config/camillagui.yml" >/dev/null <<YAML
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
default_config: "${CONFIG_DIR}/8in_8out_passthrough.yml"
statefile_path: "${STATEFILE}"
log_file: "${LOG_FILE}"
supported_capture_types: ["Alsa", "File", "Stdin", "SignalGenerator"]
supported_playback_types: ["Alsa", "File", "Stdout"]
YAML

sed "s/^User=.*/User=${USER_NAME}/" "${REPO_DIR}/systemd/camillagui.service" > "$SERVICE_TMP"
sudo install -m 0644 "$SERVICE_TMP" /etc/systemd/system/camillagui.service
sudo systemctl daemon-reload
sudo systemctl enable --now camillagui.service

echo
echo "CamillaGUI installation complete."
echo "Open: http://$(hostname -I | awk '{print $1}'):5005/gui/index.html"
echo
echo "For live control, CamillaDSP must run with websocket enabled:"
echo "sudo systemctl start camilladsp.service"
