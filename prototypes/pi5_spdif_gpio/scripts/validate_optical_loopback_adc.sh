#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SPDIF_DEVICE="${SPDIF_ALSA_DEVICE:-hw:CARD=RASPISPDIF,DEV=0}"
ADC_DEVICE="${ADC_DEVICE:-hw:CARD=sndrpihifiberry,DEV=0}"
ADC_CHANNELS="${ADC_CHANNELS:-8}"
ADC_FORMAT="${ADC_FORMAT:-S32_LE}"
ADC_ANALYSIS_BITS="${ADC_ANALYSIS_BITS:-32}"
RATE="${RATE:-48000}"
PRE_ROLL_SECONDS="${PRE_ROLL_SECONDS:-1}"
POST_ROLL_SECONDS="${POST_ROLL_SECONDS:-1}"
ARTIFACT_DIR="${ARTIFACT_DIR:-$PROJECT_DIR/out/optical_loopback_$(date +%Y%m%d_%H%M%S)}"

TEST_WAV="$ARTIFACT_DIR/spdif_optical_test_48k.wav"
CAPTURE_RAW="$ARTIFACT_DIR/adc_capture_${ADC_CHANNELS}ch_${ADC_FORMAT}.raw"
SUMMARY="$ARTIFACT_DIR/summary.txt"
METRICS="$ARTIFACT_DIR/channel_metrics.csv"
ARECORD_LOG="$ARTIFACT_DIR/arecord.log"
APLAY_LOG="$ARTIFACT_DIR/aplay.log"
DMESG_LOG="$ARTIFACT_DIR/dmesg_spdif.log"

if ! aplay -l | grep -q RASPISPDIF; then
  echo "RASPISPDIF ALSA card is not visible. Run install_kernel_spdif_on_pi5.sh first." >&2
  exit 1
fi

if ! arecord -l | grep -q -E 'sndrpihifiberry|8x|ADC|capture'; then
  echo "No obvious ADC capture card was found in arecord -l." >&2
  echo "Continuing anyway with ADC_DEVICE=${ADC_DEVICE}." >&2
fi

mkdir -p "$ARTIFACT_DIR"

python3 - "$TEST_WAV" "$RATE" <<'PY'
import math
import struct
import sys
import wave

path = sys.argv[1]
rate = int(sys.argv[2])

segments = [
    ("silence", 1.0),
    ("marker", 0.03),
    ("silence", 0.47),
    ("both_1khz", 5.0),
    ("silence", 0.5),
    ("left_1khz", 2.0),
    ("right_1khz", 2.0),
    ("silence", 1.0),
]

def sine(n, freq, amp):
    return int(32767 * amp * math.sin(2.0 * math.pi * freq * n / rate))

with wave.open(path, "wb") as wav:
    wav.setnchannels(2)
    wav.setsampwidth(2)
    wav.setframerate(rate)
    n = 0
    for name, seconds in segments:
        frames = int(round(seconds * rate))
        for _ in range(frames):
            if name == "marker":
                left = right = sine(n, 4000.0, 0.70)
            elif name == "both_1khz":
                left = right = sine(n, 1000.0, 0.18)
            elif name == "left_1khz":
                left = sine(n, 1000.0, 0.18)
                right = 0
            elif name == "right_1khz":
                left = 0
                right = sine(n, 1000.0, 0.18)
            else:
                left = right = 0
            wav.writeframesraw(struct.pack("<hh", left, right))
            n += 1
PY

TEST_SECONDS="$(python3 - "$TEST_WAV" <<'PY'
import sys
import wave
with wave.open(sys.argv[1], "rb") as wav:
    print(wav.getnframes() / wav.getframerate())
PY
)"

CAPTURE_SECONDS="$(python3 - "$TEST_SECONDS" "$PRE_ROLL_SECONDS" "$POST_ROLL_SECONDS" <<'PY'
import math
import sys
print(int(math.ceil(float(sys.argv[1]) + float(sys.argv[2]) + float(sys.argv[3]))))
PY
)"

echo "Optical loopback validation"
echo "  S/PDIF output: ${SPDIF_DEVICE}"
echo "  ADC capture:   ${ADC_DEVICE}, ${ADC_CHANNELS}ch, ${ADC_FORMAT}, ${RATE} Hz"
echo "  ADC analysis:  ${ADC_ANALYSIS_BITS}-bit full scale"
echo "  Artifacts:     ${ARTIFACT_DIR}"
echo
echo "Hardware path expected:"
echo "  GPIO12 -> TOSLINK transmitter -> optical cable -> TOSLINK-to-analog converter -> ADC inputs"
echo

(dmesg -C >/dev/null 2>&1 || true)

arecord \
  -D "$ADC_DEVICE" \
  -c "$ADC_CHANNELS" \
  -r "$RATE" \
  -f "$ADC_FORMAT" \
  -t raw \
  -d "$CAPTURE_SECONDS" \
  "$CAPTURE_RAW" >"$ARECORD_LOG" 2>&1 &
REC_PID=$!

cleanup() {
  if kill -0 "$REC_PID" >/dev/null 2>&1; then
    kill "$REC_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

sleep "$PRE_ROLL_SECONDS"
aplay -D "$SPDIF_DEVICE" "$TEST_WAV" >"$APLAY_LOG" 2>&1
wait "$REC_PID"
trap - EXIT

(dmesg | grep -i -E 'raspiaudio_spdif|rp1|pio|dma|underrun|xrun|error' >"$DMESG_LOG" || true)

python3 - "$CAPTURE_RAW" "$ADC_CHANNELS" "$ADC_FORMAT" "$ADC_ANALYSIS_BITS" "$RATE" "$PRE_ROLL_SECONDS" "$SUMMARY" "$METRICS" <<'PY'
import csv
import math
import os
import struct
import sys

raw_path = sys.argv[1]
channels = int(sys.argv[2])
fmt = sys.argv[3]
analysis_bits = int(sys.argv[4])
rate = int(sys.argv[5])
pre_roll = float(sys.argv[6])
summary_path = sys.argv[7]
metrics_path = sys.argv[8]

if fmt == "S32_LE":
    width = 4
    unpack = struct.Struct("<i").unpack_from
    scale = float(2 ** (analysis_bits - 1))
elif fmt == "S16_LE":
    width = 2
    unpack = struct.Struct("<h").unpack_from
    scale = float(2**15)
else:
    raise SystemExit(f"Unsupported ADC_FORMAT for analysis: {fmt}")

frame_bytes = channels * width
data = open(raw_path, "rb").read()
frames = len(data) // frame_bytes
if frames <= 0:
    raise SystemExit("Capture is empty")

def sample(ch, frame):
    offset = frame * frame_bytes + ch * width
    return unpack(data, offset)[0] / scale

def window_bounds(start_s, end_s, latency_s=0.0):
    start = max(0, int(round((pre_roll + start_s + latency_s) * rate)))
    end = min(frames, int(round((pre_roll + end_s + latency_s) * rate)))
    return start, max(start, end)

def rms_for(ch, start, end):
    if end <= start:
        return 0.0
    acc = 0.0
    count = 0
    for frame in range(start, end):
        v = sample(ch, frame)
        acc += v * v
        count += 1
    return math.sqrt(acc / count) if count else 0.0

def peak_for(ch, start, end):
    peak = 0.0
    for frame in range(start, end):
        v = abs(sample(ch, frame))
        if v > peak:
            peak = v
    return peak

def dbfs(value):
    return 20.0 * math.log10(max(value, 1e-12))

rows = []
for ch in range(channels):
    peak = peak_for(ch, 0, frames)
    threshold = max(0.01, peak * 0.45)
    search_start = max(0, int((pre_roll + 0.85) * rate))
    search_end = min(frames, int((pre_roll + 1.20) * rate))
    marker = None
    for frame in range(search_start, search_end):
        if abs(sample(ch, frame)) >= threshold:
            marker = frame
            break

    expected_marker = int(round((pre_roll + 1.0) * rate))
    latency_s = None if marker is None else (marker - expected_marker) / rate
    align = 0.0 if latency_s is None else latency_s

    both_start, both_end = window_bounds(1.5, 6.5, align)
    left_start, left_end = window_bounds(7.0, 9.0, align)
    right_start, right_end = window_bounds(9.0, 11.0, align)

    both_rms = rms_for(ch, both_start, both_end)
    left_rms = rms_for(ch, left_start, left_end)
    right_rms = rms_for(ch, right_start, right_end)

    block = int(0.05 * rate)
    block_rms = []
    pos = both_start
    while pos + block <= both_end:
        block_rms.append(rms_for(ch, pos, pos + block))
        pos += block
    sorted_blocks = sorted(block_rms)
    median = sorted_blocks[len(sorted_blocks) // 2] if sorted_blocks else 0.0
    dropouts = sum(1 for value in block_rms if median > 0 and value < median * 0.25)

    rows.append({
        "channel": ch,
        "peak_dbfs": f"{dbfs(peak):.1f}",
        "both_tone_rms_dbfs": f"{dbfs(both_rms):.1f}",
        "left_segment_rms_dbfs": f"{dbfs(left_rms):.1f}",
        "right_segment_rms_dbfs": f"{dbfs(right_rms):.1f}",
        "marker_found": "yes" if marker is not None else "no",
        "latency_ms": "" if latency_s is None else f"{latency_s * 1000.0:.2f}",
        "dropout_blocks_50ms": dropouts,
    })

with open(metrics_path, "w", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
    writer.writeheader()
    writer.writerows(rows)

active = [row for row in rows if float(row["both_tone_rms_dbfs"]) > -70.0]
best = sorted(active, key=lambda row: float(row["both_tone_rms_dbfs"]), reverse=True)[:4]
dropout_total = sum(int(row["dropout_blocks_50ms"]) for row in active)

with open(summary_path, "w") as handle:
    handle.write("Optical S/PDIF loopback ADC summary\n")
    handle.write(f"ADC analysis full-scale bits: {analysis_bits}\n")
    handle.write(f"Capture frames: {frames}\n")
    handle.write(f"Capture seconds: {frames / rate:.3f}\n")
    handle.write(f"Active channels over -70 dBFS: {[row['channel'] for row in active]}\n")
    handle.write(f"Total 50 ms dropout blocks on active channels: {dropout_total}\n")
    handle.write("\nStrongest channels:\n")
    for row in best:
        handle.write(
            f"  IN{row['channel']}: both={row['both_tone_rms_dbfs']} dBFS, "
            f"Lseg={row['left_segment_rms_dbfs']} dBFS, "
            f"Rseg={row['right_segment_rms_dbfs']} dBFS, "
            f"latency={row['latency_ms'] or 'n/a'} ms, "
            f"dropouts={row['dropout_blocks_50ms']}\n"
        )

print(open(summary_path).read())
print(f"Metrics CSV: {metrics_path}")
PY

echo "Logs:"
echo "  $ARECORD_LOG"
echo "  $APLAY_LOG"
echo "  $DMESG_LOG"
