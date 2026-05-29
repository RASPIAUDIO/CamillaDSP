#!/usr/bin/env bash
set -euo pipefail

VERSION="${CAMILLA_VERSION:-4.1.3}"
BASE_DIR="${CAMILLA_HOME:-$HOME/camilladsp}"
BIN_DIR="$BASE_DIR/bin"
DOWNLOAD_DIR="$BASE_DIR/downloads"
URL="https://github.com/HEnquist/camilladsp/releases/download/v${VERSION}/camilladsp-linux-aarch64.tar.gz"

mkdir -p "$BIN_DIR" "$DOWNLOAD_DIR" "$BASE_DIR/configs" "$BASE_DIR/logs"

echo "Installing CamillaDSP ${VERSION} in ${BASE_DIR}"
wget -O "$DOWNLOAD_DIR/camilladsp-linux-aarch64-v${VERSION}.tar.gz" "$URL"
tar -xzf "$DOWNLOAD_DIR/camilladsp-linux-aarch64-v${VERSION}.tar.gz" -C "$BIN_DIR"
chmod +x "$BIN_DIR/camilladsp"

"$BIN_DIR/camilladsp" --version

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    echo
    echo "Add this line to ~/.profile or ~/.bashrc if needed:"
    echo "export PATH=\"$BIN_DIR:\$PATH\""
    ;;
esac
