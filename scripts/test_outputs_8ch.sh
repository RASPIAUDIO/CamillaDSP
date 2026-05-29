#!/usr/bin/env bash
set -euo pipefail

DEVICE="${1:-hw:CARD=sndrpihifiberry,DEV=0}"
RATE="${RATE:-48000}"
FORMAT="${FORMAT:-S32_LE}"

speaker-test -D "$DEVICE" -c 8 -r "$RATE" -F "$FORMAT" -t sine -f 440 -l 1
