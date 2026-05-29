#!/usr/bin/env bash
set -euo pipefail

DEVICE="${DEVICE:-hw:CARD=sndrpihifiberry,DEV=0}"
RATE="${RATE:-48000}"
FORMAT="${FORMAT:-S32_LE}"
OUT_LEFT="${OUT_LEFT:-2}"
OUT_RIGHT="${OUT_RIGHT:-3}"
FREQ_LEFT="${FREQ_LEFT:-500}"
FREQ_RIGHT="${FREQ_RIGHT:-1000}"
AMP="${AMP:-0.125}"
WORK="${WORK:-/tmp/raspiaudio_loopback_dual_tone}"

mkdir -p "$WORK"

python3 - <<PY
import numpy as np
import wave

rate = int("${RATE}")
duration = 5.0
channels = 8
amp = float("${AMP}")
out_left = int("${OUT_LEFT}")
out_right = int("${OUT_RIGHT}")
freq_left = float("${FREQ_LEFT}")
freq_right = float("${FREQ_RIGHT}")

n = int(rate * duration)
t = np.arange(n) / rate
data = np.zeros((n, channels), dtype=np.int32)
data[:, out_left] = (amp * np.sin(2 * np.pi * freq_left * t) * (2**31 - 1)).astype(np.int32)
data[:, out_right] = (amp * np.sin(2 * np.pi * freq_right * t) * (2**31 - 1)).astype(np.int32)

path = "${WORK}/OUT_play_out${OUT_LEFT}_${FREQ_LEFT}Hz_out${OUT_RIGHT}_${FREQ_RIGHT}Hz_s32_8ch.wav"
with wave.open(path, "wb") as w:
    w.setnchannels(channels)
    w.setsampwidth(4)
    w.setframerate(rate)
    w.writeframes(data.reshape(-1).astype("<i4").tobytes())
print(path)
PY

OUT_WAV="$WORK/OUT_play_out${OUT_LEFT}_${FREQ_LEFT}Hz_out${OUT_RIGHT}_${FREQ_RIGHT}Hz_s32_8ch.wav"
IN_WAV="$WORK/IN_record_out${OUT_LEFT}_${FREQ_LEFT}Hz_out${OUT_RIGHT}_${FREQ_RIGHT}Hz_s32_8ch.wav"
rm -f "$IN_WAV"

arecord -q -D "$DEVICE" -f "$FORMAT" -r "$RATE" -c 8 -d 7 "$IN_WAV" &
REC_PID=$!
sleep 1
aplay -q -D "$DEVICE" "$OUT_WAV"
wait "$REC_PID"

python3 - <<PY
import math
import numpy as np
import wave

path = "${IN_WAV}"
freq_left = float("${FREQ_LEFT}")
freq_right = float("${FREQ_RIGHT}")

with wave.open(path, "rb") as w:
    rate = w.getframerate()
    ch = w.getnchannels()
    raw = w.readframes(w.getnframes())

x = np.frombuffer(raw, dtype="<i4").reshape(-1, ch).astype(np.float64) / (2**31)
seg = x[int(1.5 * rate):int(5.5 * rate)]
seg = seg - np.mean(seg, axis=0, keepdims=True)
win = np.hanning(seg.shape[0])[:, None]
spec = np.fft.rfft(seg * win, axis=0)
freqs = np.fft.rfftfreq(seg.shape[0], 1 / rate)
mag = np.abs(spec)

def band_level(freq):
    band = (freqs >= freq - 3) & (freqs <= freq + 3)
    return np.max(mag[band, :], axis=0)

left = band_level(freq_left)
right = band_level(freq_right)
rms = np.sqrt(np.mean(seg**2, axis=0))
peak = np.max(np.abs(seg), axis=0)
ref = max(np.max(left), np.max(right), 1e-30)

print(f"recording {path}")
print("channel,rms_dbfs,peak_dbfs,left_freq_rel_db,right_freq_rel_db")
for i in range(ch):
    print(
        f"{i},"
        f"{20 * math.log10(rms[i] + 1e-30):.2f},"
        f"{20 * math.log10(peak[i] + 1e-30):.2f},"
        f"{20 * math.log10(left[i] / ref + 1e-30):.1f},"
        f"{20 * math.log10(right[i] / ref + 1e-30):.1f}"
    )

print("best_left_input", int(np.argmax(left)))
print("best_right_input", int(np.argmax(right)))
PY

echo
echo "Output WAV: $OUT_WAV"
echo "Input WAV:  $IN_WAV"
