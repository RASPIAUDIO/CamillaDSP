#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run with sudo."
  exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAMILLA_CONFIG_DIR="${CAMILLA_CONFIG_DIR:-/etc/camilladsp}"
CAMILLA_COEFF_DIR="${CAMILLA_COEFF_DIR:-/etc/camilladsp/coeffs}"
CAMILLA_BIN="${CAMILLA_BIN:-/usr/local/bin/camilladsp}"

install -d -m 0755 "$CAMILLA_CONFIG_DIR" "$CAMILLA_COEFF_DIR"

install -m 0644 \
  "$REPO_DIR/configs/usb_gadget_8ch_48k_front_lr_to_spdif_optical_stereo.yml" \
  "$REPO_DIR/configs/usb_gadget_8ch_48k_front_lr_to_spdif_optical_stereo_fir_load.yml" \
  "$REPO_DIR/configs/usb_gadget_2ch_48k_to_spdif_optical_stereo.yml" \
  "$REPO_DIR/configs/usb_gadget_2ch_48k_to_spdif_optical_stereo_fir_load.yml" \
  "$REPO_DIR/configs/signalgen_1khz_48k_to_spdif_optical_fir_load.yml" \
  "$CAMILLA_CONFIG_DIR/"

python3 "$REPO_DIR/scripts/generate_fir_load_coeffs.py" \
  "$CAMILLA_COEFF_DIR/fir_load_4096_taps.txt"

if [ -x "$CAMILLA_BIN" ]; then
  "$CAMILLA_BIN" -c "$CAMILLA_CONFIG_DIR/usb_gadget_8ch_48k_front_lr_to_spdif_optical_stereo.yml"
  "$CAMILLA_BIN" -c "$CAMILLA_CONFIG_DIR/usb_gadget_8ch_48k_front_lr_to_spdif_optical_stereo_fir_load.yml"
  "$CAMILLA_BIN" -c "$CAMILLA_CONFIG_DIR/usb_gadget_2ch_48k_to_spdif_optical_stereo.yml"
  "$CAMILLA_BIN" -c "$CAMILLA_CONFIG_DIR/usb_gadget_2ch_48k_to_spdif_optical_stereo_fir_load.yml"
  "$CAMILLA_BIN" -c "$CAMILLA_CONFIG_DIR/signalgen_1khz_48k_to_spdif_optical_fir_load.yml"
else
  echo "Warning: $CAMILLA_BIN not found; profiles were installed but not validated."
fi

echo "Installed CamillaDSP optical S/PDIF profiles in $CAMILLA_CONFIG_DIR"
echo "Installed FIR coefficients in $CAMILLA_COEFF_DIR"
