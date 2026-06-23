#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KERNEL_DIR="$PROJECT_DIR/kernel"
KDIR="${KDIR:-/lib/modules/$(uname -r)/build}"

if [[ ! -d "$KDIR" ]]; then
  echo "Missing kernel build directory: $KDIR" >&2
  echo "Install matching Raspberry Pi kernel headers first." >&2
  exit 1
fi

make -C "$KDIR" M="$KERNEL_DIR" modules
if command -v modinfo >/dev/null 2>&1; then
  modinfo "$KERNEL_DIR/raspiaudio_spdif_pio.ko"
elif [[ -x /usr/sbin/modinfo ]]; then
  /usr/sbin/modinfo "$KERNEL_DIR/raspiaudio_spdif_pio.ko"
else
  echo "Built $KERNEL_DIR/raspiaudio_spdif_pio.ko"
  echo "modinfo is not installed or not in PATH; skipping module metadata dump."
fi
