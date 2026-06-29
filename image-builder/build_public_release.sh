#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

VERSION="${RASPIAUDIO_RELEASE_VERSION:-}"
if [ -z "$VERSION" ]; then
  VERSION="$(tr -d '\r\n' <"$REPO_DIR/appliance/VERSION")"
fi

BASE_URL="${RASPIAUDIO_PUBLIC_BASE_URL:-https://raspiaudio.com/camilladsp-box}"
IMAGE_BASE_URL="${RASPIAUDIO_IMAGE_BASE_URL:-${BASE_URL%/}/downloads}"
RPI_IMAGE_GEN_DIR="${RPI_IMAGE_GEN_DIR:-$HOME/rpi-image-gen}"
IMAGE_NAME="${RASPIAUDIO_IMAGE_NAME:-raspiaudio-dspbox-pi5}"
PREPARE_ONLY="${PREPARE_ONLY:-0}"
SKIP_BUILD=0
IMAGE_PATH="${RASPIAUDIO_RELEASE_IMAGE:-}"
RAW_IMAGE_PATH="${RASPIAUDIO_RAW_IMAGE:-}"
IMAGER_JSON_PATH="${RASPIAUDIO_IMAGER_JSON:-}"

usage() {
  cat <<EOF
Usage:
  image-builder/build_public_release.sh [options]

Builds the Raspberry Pi image, stages it into public/camilladsp-box, then
creates a strict upload ZIP.

Options:
  --version YYYY.MM.DD         Release version, default: appliance/VERSION
  --base-url URL               Public page URL, default: $BASE_URL
  --rpi-image-gen-dir PATH     rpi-image-gen checkout, default: $RPI_IMAGE_GEN_DIR
  --skip-build                 Stage/package an already built image
  --image PATH                 Existing .img.xz when using --skip-build
  --raw-image PATH             Optional raw .img for exact Imager extract hash
  --imager-json PATH           Optional pre-generated Imager repository JSON
  --prepare-only               Only prepare image-builder/source archive
  -h, --help                   Show this help

Environment equivalents are also supported:
  RASPIAUDIO_RELEASE_VERSION, RASPIAUDIO_PUBLIC_BASE_URL,
  RPI_IMAGE_GEN_DIR, RASPIAUDIO_RELEASE_IMAGE, RASPIAUDIO_RAW_IMAGE,
  RASPIAUDIO_IMAGER_JSON, PREPARE_ONLY.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      VERSION="${2:?missing version}"
      shift 2
      ;;
    --base-url)
      BASE_URL="${2:?missing URL}"
      IMAGE_BASE_URL="${BASE_URL%/}/downloads"
      shift 2
      ;;
    --rpi-image-gen-dir)
      RPI_IMAGE_GEN_DIR="${2:?missing path}"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --image)
      IMAGE_PATH="${2:?missing image path}"
      shift 2
      ;;
    --raw-image)
      RAW_IMAGE_PATH="${2:?missing raw image path}"
      shift 2
      ;;
    --imager-json)
      IMAGER_JSON_PATH="${2:?missing Imager JSON path}"
      shift 2
      ;;
    --prepare-only)
      PREPARE_ONLY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

case "$VERSION" in
  ????\.??\.??) ;;
  *)
    echo "Release version must look like YYYY.MM.DD, got: $VERSION" >&2
    exit 1
    ;;
esac

echo "RASPIAUDIO CamillaDSP Box public release"
echo "Version: $VERSION"
echo "Public page: ${BASE_URL%/}/"
echo

if [ "$SKIP_BUILD" != "1" ]; then
  echo "Step 1/3: build image"
  RASPIAUDIO_RELEASE_VERSION="$VERSION" \
  RASPIAUDIO_IMAGE_BASE_URL="$IMAGE_BASE_URL" \
  RPI_IMAGE_GEN_DIR="$RPI_IMAGE_GEN_DIR" \
  PREPARE_ONLY="$PREPARE_ONLY" \
    "$SCRIPT_DIR/build_image.sh"

  if [ "$PREPARE_ONLY" = "1" ]; then
    echo
    echo "Prepare-only complete. Source archive is ready for rpi-image-gen."
    exit 0
  fi
elif [ -z "$IMAGE_PATH" ]; then
  echo "When using --skip-build, pass --image /path/to/$IMAGE_NAME-$VERSION.img.xz." >&2
  exit 1
fi

if [ -z "$IMAGE_PATH" ]; then
  if [ ! -d "$RPI_IMAGE_GEN_DIR/work" ]; then
    echo "Cannot find rpi-image-gen work directory: $RPI_IMAGE_GEN_DIR/work" >&2
    exit 1
  fi
  IMAGE_PATH="$(
    find "$RPI_IMAGE_GEN_DIR/work" -type f -path "*/deploy-*/*" -name "$IMAGE_NAME-$VERSION.img.xz" -printf '%T@ %p\n' |
      sort -nr |
      sed -n '1s/^[^ ]* //p'
  )"
fi

if [ -z "$IMAGE_PATH" ] || [ ! -f "$IMAGE_PATH" ]; then
  echo "Release image not found. Pass --image /path/to/$IMAGE_NAME-$VERSION.img.xz." >&2
  exit 1
fi

if [ -z "$RAW_IMAGE_PATH" ] && [ -f "$RPI_IMAGE_GEN_DIR/work/image-$IMAGE_NAME/$IMAGE_NAME.img" ]; then
  RAW_IMAGE_PATH="$RPI_IMAGE_GEN_DIR/work/image-$IMAGE_NAME/$IMAGE_NAME.img"
fi

if [ -z "$IMAGER_JSON_PATH" ]; then
  candidate="$(dirname "$IMAGE_PATH")/raspiaudio-imager-repository-$VERSION.json"
  if [ -f "$candidate" ]; then
    IMAGER_JSON_PATH="$candidate"
  fi
fi

echo
echo "Step 2/3: stage public files"
stage_cmd=(
  python3 "$REPO_DIR/image-builder/stage_public_release.py"
  --image "$IMAGE_PATH"
  --version "$VERSION"
  --base-url "$BASE_URL"
)
if [ -n "$RAW_IMAGE_PATH" ]; then
  stage_cmd+=(--raw-image "$RAW_IMAGE_PATH")
fi
if [ -n "$IMAGER_JSON_PATH" ]; then
  stage_cmd+=(--imager-json "$IMAGER_JSON_PATH")
fi
"${stage_cmd[@]}"

echo
echo "Step 3/3: package strict upload ZIP"
python3 "$REPO_DIR/scripts/package_public_camilladsp_box.py" \
  --strict \
  --package "$REPO_DIR/artifacts/camilladsp-box-public-$VERSION.zip"

cat <<EOF

Release package ready:
  $REPO_DIR/artifacts/camilladsp-box-public-$VERSION.zip

Upload the ZIP contents to:
  ${BASE_URL%/}/

Then verify the live site:
  python3 scripts/validate_public_camilladsp_box.py --base-url ${BASE_URL%/}

Do not claim a public release until a fresh flash of this exact image has passed
raspiaudio-validate-release and the manual output/USB/TOSLINK checks.
EOF
