#!/usr/bin/env bash
set -euo pipefail

DEVICE="${1:-hw:CARD=sndrpihifiberry,DEV=0}"
RATE="${RATE:-48000}"
FORMAT="${FORMAT:-S32_LE}"
DURATION="${DURATION:-5}"
OUT="${OUT:-/tmp/camilladsp_8ch_capture.wav}"

arecord -D "$DEVICE" -f "$FORMAT" -r "$RATE" -c 8 -d "$DURATION" "$OUT"
ls -lh "$OUT"
file "$OUT" 2>/dev/null || true
