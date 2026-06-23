#!/usr/bin/env bash
set -euo pipefail

DEVICE="${SPDIF_ALSA_DEVICE:-hw:CARD=RASPISPDIF,DEV=0}"
LOOPS="${SPDIF_STRESS_LOOPS:-50}"
LOOP_SECONDS="${SPDIF_STRESS_LOOP_SECONDS:-2}"
LONG_SECONDS="${SPDIF_STRESS_LONG_SECONDS:-1800}"
SKIP_LONG="${SPDIF_STRESS_SKIP_LONG:-0}"

if ! aplay -l | grep -q RASPISPDIF; then
  echo "RASPISPDIF ALSA card is not visible. Run install_kernel_spdif_on_pi5.sh first." >&2
  exit 1
fi

echo "Start/stop stress: ${LOOPS} loops, ${LOOP_SECONDS}s each, device ${DEVICE}"
for i in $(seq 1 "$LOOPS"); do
  printf 'Loop %s/%s\r' "$i" "$LOOPS"
  set +e
  timeout "$LOOP_SECONDS" speaker-test \
    -D "$DEVICE" \
    -c 2 \
    -r 48000 \
    -F S16_LE \
    -t sine \
    -f 1000 >/tmp/raspiaudio_spdif_stress.log 2>&1
  rc=$?
  set -e
  if [ "$rc" -ne 124 ]; then
    echo
    echo "speaker-test failed in loop ${i} with rc=${rc}" >&2
    cat /tmp/raspiaudio_spdif_stress.log >&2
    dmesg | tail -80 >&2
    exit 1
  fi
done
echo
echo "Start/stop stress passed."

if [ "$SKIP_LONG" = "1" ]; then
  echo "Skipping long stress because SPDIF_STRESS_SKIP_LONG=1."
  exit 0
fi

echo "Long run stress: ${LONG_SECONDS}s. Stop with Ctrl+C."
set +e
timeout "$LONG_SECONDS" speaker-test \
  -D "$DEVICE" \
  -c 2 \
  -r 48000 \
  -F S16_LE \
  -t sine \
  -f 1000 >/tmp/raspiaudio_spdif_long.log 2>&1
rc=$?
set -e
if [ "$rc" -ne 124 ]; then
  echo "long speaker-test failed with rc=${rc}" >&2
  cat /tmp/raspiaudio_spdif_long.log >&2
  dmesg | tail -120 >&2
  exit 1
fi

echo "Long stress completed."
echo
echo "Recent driver-related kernel log:"
dmesg | grep -i -E 'raspiaudio_spdif|rp1|pio|dma|underrun|error' | tail -80 || true
