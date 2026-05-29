#!/usr/bin/env bash
set -euo pipefail

DEVICE="${DEVICE:-hw:CARD=sndrpihifiberry,DEV=0}"
CAMILLA="${CAMILLA:-/usr/local/bin/camilladsp}"
CONFIG="${CONFIG:-/etc/camilladsp/signalgen_500hz_out2_out3.yml}"
WORK="${WORK:-/tmp/camilladsp_signalgen_loopback}"
RATE="${RATE:-48000}"
FORMAT="${FORMAT:-S32_LE}"
DURATION="${DURATION:-7}"
FREQ="${FREQ:-500}"

mkdir -p "$WORK"
IN_WAV="$WORK/IN_record_camilladsp_signalgen_${FREQ}Hz_s32_8ch.wav"
LOG="$WORK/camilladsp_signalgen.log"
rm -f "$IN_WAV" "$LOG"

arecord -q -D "$DEVICE" -f "$FORMAT" -r "$RATE" -c 8 -d "$DURATION" "$IN_WAV" &
REC_PID=$!
sleep 1
timeout 5 "$CAMILLA" -l info -o "$LOG" "$CONFIG" >/dev/null 2>&1 || true
wait "$REC_PID"

python3 - <<PY
import math
import numpy as np
import wave

path = "${IN_WAV}"
freq = float("${FREQ}")

with wave.open(path, "rb") as w:
    rate = w.getframerate()
    ch = w.getnchannels()
    raw = w.readframes(w.getnframes())

x = np.frombuffer(raw, dtype="<i4").reshape(-1, ch).astype(np.float64) / (2**31)
seg = x[int(1.5 * rate):int(5.5 * rate)]
seg = seg - np.mean(seg, axis=0, keepdims=True)
rms = np.sqrt(np.mean(seg**2, axis=0))
peak = np.max(np.abs(seg), axis=0)

win = np.hanning(seg.shape[0])[:, None]
spec = np.fft.rfft(seg * win, axis=0)
freqs = np.fft.rfftfreq(seg.shape[0], 1 / rate)
mag = np.abs(spec)
mag[freqs < 20, :] = 0

target_band = (freqs >= freq - 3) & (freqs <= freq + 3)
target = np.max(mag[target_band, :], axis=0)
noise_band = (freqs >= 700) & (freqs <= 5000)
noise = np.median(mag[noise_band, :], axis=0) + 1e-30
snr = 20 * np.log10((target + 1e-30) / noise)
ref = max(float(np.max(target)), 1e-30)

print(f"recording {path}")
print("channel,rms_dbfs,peak_dbfs,500hz_rel_db,500hz_snr_db")
for i in range(ch):
    print(
        f"{i},"
        f"{20 * math.log10(rms[i] + 1e-30):.2f},"
        f"{20 * math.log10(peak[i] + 1e-30):.2f},"
        f"{20 * math.log10(target[i] / ref + 1e-30):.1f},"
        f"{snr[i]:.1f}"
    )

rank = np.argsort(target)[::-1]
print("strongest_inputs", ",".join(str(int(i)) for i in rank[:2]))
PY

echo
echo "Input WAV: $IN_WAV"
echo "CamillaDSP log: $LOG"
