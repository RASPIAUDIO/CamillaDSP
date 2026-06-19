#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/profiles/raspiaudio_8xout_usb_7_1_quickstart/install.sh" "$@"
