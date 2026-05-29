#!/usr/bin/env bash
set -euo pipefail

CARD="${1:-sndrpihifiberry}"
DEVICE="hw:CARD=${CARD},DEV=0"

echo "== System =="
hostname
uname -a
cat /etc/os-release | sed -n '1,8p'

echo
echo "== ALSA playback devices =="
aplay -l

echo
echo "== ALSA capture devices =="
arecord -l

echo
echo "== ALSA cards =="
cat /proc/asound/cards

echo
echo "== ALSA PCM =="
cat /proc/asound/pcm

echo
echo "== Hardware parameters for ${DEVICE} capture =="
timeout 4 arecord -D "$DEVICE" --dump-hw-params -f S32_LE -r 48000 -c 8 -d 1 /tmp/camilladsp_probe_capture.wav 2>&1 || true
rm -f /tmp/camilladsp_probe_capture.wav

echo
echo "== PipeWire/Pulse services =="
systemctl --user --no-pager --type=service --state=running 2>/dev/null | grep -E 'pipewire|pulse|wireplumber' || true
