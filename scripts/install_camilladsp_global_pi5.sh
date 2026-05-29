#!/usr/bin/env bash
set -euo pipefail

VERSION="${CAMILLA_VERSION:-4.1.3}"
USER_NAME="${CAMILLA_USER:-ros}"
USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
LOCAL_BIN="${USER_HOME}/camilladsp/bin/camilladsp"
DOWNLOAD_DIR="${USER_HOME}/camilladsp/downloads"
URL="https://github.com/HEnquist/camilladsp/releases/download/v${VERSION}/camilladsp-linux-aarch64.tar.gz"

if ! sudo -n true 2>/dev/null; then
  echo "Passwordless sudo is required for the global installation." >&2
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
sudo install -m 0644 systemd/camilladsp.service /etc/systemd/system/camilladsp.service
sudo systemctl daemon-reload

/usr/local/bin/camilladsp --version
/usr/local/bin/camilladsp --check /etc/camilladsp/8in_8out_passthrough.yml
/usr/local/bin/camilladsp --check /etc/camilladsp/8in_8out_gain_test.yml

echo
echo "Global CamillaDSP installation complete."
echo "Start it with: sudo systemctl start camilladsp.service"
