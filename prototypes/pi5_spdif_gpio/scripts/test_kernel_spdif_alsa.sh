#!/usr/bin/env bash
set -euo pipefail

DEVICE="${SPDIF_ALSA_DEVICE:-hw:CARD=RASPISPDIF,DEV=0}"
DURATION="${SPDIF_TEST_SECONDS:-8}"
WAV_PATH="${SPDIF_TEST_WAV:-/tmp/raspiaudio_spdif_48k_s16_1khz.wav}"

if ! aplay -l | grep -q RASPISPDIF; then
  echo "RASPISPDIF ALSA card is not visible. Run install_kernel_spdif_on_pi5.sh first." >&2
  exit 1
fi

echo "Playing ${DURATION}s 1 kHz sine over ${DEVICE}"
timeout "$DURATION" speaker-test \
  -D "$DEVICE" \
  -c 2 \
  -r 48000 \
  -F S16_LE \
  -t sine \
  -f 1000 || [[ $? -eq 124 ]]

echo
echo "Playing ${DURATION}s 1 kHz S32_LE sine over ${DEVICE}"
timeout "$DURATION" speaker-test \
  -D "$DEVICE" \
  -c 2 \
  -r 48000 \
  -F S32_LE \
  -t sine \
  -f 1000 || [[ $? -eq 124 ]]

echo
echo "Generating a 4s stereo 48 kHz S16_LE WAV: ${WAV_PATH}"
python3 - "$WAV_PATH" <<'PY'
import math
import struct
import sys
import wave

path = sys.argv[1]
rate = 48000
seconds = 4
frequency = 1000.0
amplitude = int(32767 * 0.18)

with wave.open(path, "wb") as wav:
    wav.setnchannels(2)
    wav.setsampwidth(2)
    wav.setframerate(rate)
    for n in range(rate * seconds):
        sample = int(amplitude * math.sin(2.0 * math.pi * frequency * n / rate))
        wav.writeframesraw(struct.pack("<hh", sample, sample))
PY

echo "Playing WAV over ${DEVICE}"
timeout 8 aplay -D "$DEVICE" "$WAV_PATH"

echo
echo "Recent kernel log:"
dmesg | tail -40
