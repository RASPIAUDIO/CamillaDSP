#!/usr/bin/env bash
set -euo pipefail

VERSION="${CAMILLA_VERSION:-4.1.3}"
DEFAULT_USER="${SUDO_USER:-$(id -un)}"
if [ "$DEFAULT_USER" = "root" ]; then
  DEFAULT_USER="$(getent passwd 1000 | cut -d: -f1 || true)"
fi
USER_NAME="${CAMILLA_USER:-$DEFAULT_USER}"
if [ -z "$USER_NAME" ] || ! getent passwd "$USER_NAME" >/dev/null; then
  echo "Set CAMILLA_USER to the Linux user that should run CamillaDSP." >&2
  exit 1
fi
USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
LOCAL_BIN="${USER_HOME}/camilladsp/bin/camilladsp"
DOWNLOAD_DIR="${USER_HOME}/camilladsp/downloads"
URL="https://github.com/HEnquist/camilladsp/releases/download/v${VERSION}/camilladsp-linux-aarch64.tar.gz"
SERVICE_TMP="$(mktemp)"
cleanup() {
  rm -f "$SERVICE_TMP"
}
trap cleanup EXIT

if ! sudo -v; then
  echo "sudo access is required for the global installation." >&2
  exit 1
fi

if [ ! -x "$LOCAL_BIN" ]; then
  mkdir -p "$DOWNLOAD_DIR" "${USER_HOME}/camilladsp/bin"
  wget -O "${DOWNLOAD_DIR}/camilladsp-linux-aarch64-v${VERSION}.tar.gz" "$URL"
  tar -xzf "${DOWNLOAD_DIR}/camilladsp-linux-aarch64-v${VERSION}.tar.gz" -C "${USER_HOME}/camilladsp/bin"
  chmod +x "$LOCAL_BIN"
fi

sudo install -m 0755 "$LOCAL_BIN" /usr/local/bin/camilladsp
sudo install -d -m 0755 /etc/camilladsp
sudo install -m 0644 configs/*.yml /etc/camilladsp/
sudo install -d -o "$USER_NAME" -g audio -m 0755 /var/log/camilladsp
sudo install -d -o "$USER_NAME" -g audio -m 0755 /var/lib/camilladsp
sed "s/^User=.*/User=${USER_NAME}/" systemd/camilladsp.service > "$SERVICE_TMP"
sudo install -m 0644 "$SERVICE_TMP" /etc/systemd/system/camilladsp.service
sudo systemctl daemon-reload

/usr/local/bin/camilladsp --version
/usr/local/bin/camilladsp --check /etc/camilladsp/8in_8out_passthrough.yml
/usr/local/bin/camilladsp --check /etc/camilladsp/8in_8out_gain_test.yml

echo
echo "Global CamillaDSP installation complete."
echo "Start it with: sudo systemctl start camilladsp.service"
