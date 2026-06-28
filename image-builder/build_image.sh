#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RPI_IMAGE_GEN_DIR="${RPI_IMAGE_GEN_DIR:-$HOME/rpi-image-gen}"
CONFIG="${RPI_IMAGE_GEN_CONFIG:-$SCRIPT_DIR/config/raspiaudio-dspbox-pi5.yaml}"
SOURCE_DIR="$SCRIPT_DIR/source"
SOURCE_ARCHIVE="$SOURCE_DIR/raspiaudio-camilladsp.tar"
IMAGE_NAME="${RASPIAUDIO_IMAGE_NAME:-raspiaudio-dspbox-pi5}"
CREATE_XZ="${CREATE_XZ:-1}"
XZ_PRESET="${XZ_PRESET:--6}"

if [ "${PREPARE_ONLY:-0}" != "1" ] && [ ! -x "$RPI_IMAGE_GEN_DIR/rpi-image-gen" ]; then
  cat >&2 <<EOF
Missing rpi-image-gen executable:
  $RPI_IMAGE_GEN_DIR/rpi-image-gen

Install it first:
  git clone https://github.com/raspberrypi/rpi-image-gen.git ~/rpi-image-gen
  cd ~/rpi-image-gen
  sudo ./install_deps.sh

Or set:
  RPI_IMAGE_GEN_DIR=/path/to/rpi-image-gen
EOF
  exit 1
fi

install -d -m 0755 "$SOURCE_DIR"
rm -f "$SOURCE_ARCHIVE"

if git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [ -n "$(git -C "$REPO_DIR" status --porcelain)" ]; then
    echo "Warning: building from committed Git HEAD; uncommitted files are not included." >&2
  fi
  git -C "$REPO_DIR" archive --format=tar --output="$SOURCE_ARCHIVE" HEAD
else
  tar \
    --exclude-vcs \
    --exclude='./artifacts' \
    --exclude='./image-builder/source' \
    --exclude='./image-builder/source/*' \
    --exclude='./image-builder/output' \
    --exclude='./*.img' \
    --exclude='./*.img.xz' \
    -C "$REPO_DIR" \
    -cf "$SOURCE_ARCHIVE" .
fi

echo "Prepared source archive:"
ls -lh "$SOURCE_ARCHIVE"

if [ "${PREPARE_ONLY:-0}" = "1" ]; then
  echo "PREPARE_ONLY=1 set; skipping rpi-image-gen build."
  exit 0
fi

echo "Building image with rpi-image-gen..."
cd "$RPI_IMAGE_GEN_DIR"
./rpi-image-gen build -S "$SCRIPT_DIR" -c "$CONFIG"

ARTEFACT_VERSION="$(git -C "$RPI_IMAGE_GEN_DIR" describe --tags --always --dirty 2>/dev/null || date +%Y-%m-%d)"
DEPLOY_DIR="$RPI_IMAGE_GEN_DIR/work/deploy-$ARTEFACT_VERSION"
RAW_IMAGE="$RPI_IMAGE_GEN_DIR/work/image-$IMAGE_NAME/$IMAGE_NAME.img"
XZ_IMAGE="$DEPLOY_DIR/$IMAGE_NAME-$ARTEFACT_VERSION.img.xz"

if [ "$CREATE_XZ" != "0" ]; then
  if [ ! -f "$RAW_IMAGE" ]; then
    echo "Cannot create .img.xz; raw image was not found: $RAW_IMAGE" >&2
    exit 1
  fi
  command -v xz >/dev/null 2>&1 || {
    echo "Cannot create .img.xz; install xz-utils first." >&2
    exit 1
  }
  install -d -m 0755 "$DEPLOY_DIR"
  echo "Creating Raspberry Pi Imager artefact:"
  echo "  $XZ_IMAGE"
  xz -T0 "$XZ_PRESET" -c "$RAW_IMAGE" >"$XZ_IMAGE"
  sha256sum "$XZ_IMAGE" >"$XZ_IMAGE.sha256"
  if [ -f "$DEPLOY_DIR/$IMAGE_NAME.img.zst" ]; then
    sha256sum "$DEPLOY_DIR/$IMAGE_NAME.img.zst" >"$DEPLOY_DIR/$IMAGE_NAME.img.zst.sha256"
  fi
fi

cat <<EOF

Build finished.

Release artefacts:
  $DEPLOY_DIR/
EOF
