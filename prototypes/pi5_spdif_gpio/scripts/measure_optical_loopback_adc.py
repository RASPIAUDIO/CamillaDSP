#!/usr/bin/env python3
"""
Advanced optical S/PDIF loopback measurement for Raspberry Pi 5.

This measures the complete lab chain:

    RASPISPDIF -> GPIO/TOSLINK TX -> optical converter DAC -> 8xIN ADC

It is useful for continuity, mapping, latency, dropouts, crosstalk, and a rough
audio-chain sanity check. It is not a standalone S/PDIF jitter or codec spec
measurement.
"""

from __future__ import annotations

import array
import csv
import datetime as dt
import math
import os
from pathlib import Path
import struct
import subprocess
import sys
import time
import wave


RATE = int(os.environ.get("RATE", "48000"))
ADC_CHANNELS = int(os.environ.get("ADC_CHANNELS", "8"))
ADC_FORMAT = os.environ.get("ADC_FORMAT", "S32_LE")
SPDIF_DEVICE = os.environ.get("SPDIF_ALSA_DEVICE", "hw:CARD=RASPISPDIF,DEV=0")
ADC_DEVICE = os.environ.get("ADC_DEVICE", "hw:CARD=sndrpihifiberry,DEV=0")
PROJECT_DIR = Path(__file__).resolve().parents[1]
ARTIFACT_DIR = Path(
    os.environ.get(
        "ARTIFACT_DIR",
        str(PROJECT_DIR / "out" / ("advanced_optical_loopback_" + dt.datetime.now().strftime("%Y%m%d_%H%M%S"))),
    )
)

if ADC_FORMAT != "S32_LE":
    raise SystemExit("This advanced analyzer currently expects ADC_FORMAT=S32_LE")

FULL_SCALE = float(2**31)
CAPTURE_PRE_SECONDS = 1.0
CAPTURE_POST_SECONDS = 1.0


def dbfs(value: float) -> float:
    return 20.0 * math.log10(max(abs(value), 1e-15))


class Timeline:
    def __init__(self) -> None:
        self.segments: list[dict[str, float | str]] = []

    def add(self, name: str, seconds: float, freq: float = 0.0, amp: float = 0.0, mode: str = "both") -> None:
        start = sum(float(seg["seconds"]) for seg in self.segments)
        self.segments.append(
            {
                "name": name,
                "start": start,
                "seconds": seconds,
                "freq": freq,
                "amp": amp,
                "mode": mode,
            }
        )

    def find(self, name: str) -> dict[str, float | str]:
        for seg in self.segments:
            if seg["name"] == name:
                return seg
        raise KeyError(name)

    @property
    def seconds(self) -> float:
        return sum(float(seg["seconds"]) for seg in self.segments)


def build_timeline() -> Timeline:
    timeline = Timeline()
    timeline.add("initial_silence", 1.00)
    timeline.add("latency_marker_4k", 0.05, 4000.0, 0.70, "both")
    timeline.add("settle_silence", 0.45)
    timeline.add("both_1k_10s", 10.0, 1000.0, 0.18, "both")
    timeline.add("gap_after_both", 0.20)
    timeline.add("left_1k_3s", 3.0, 1000.0, 0.18, "left")
    timeline.add("gap_after_left", 0.20)
    timeline.add("right_1k_3s", 3.0, 1000.0, 0.18, "right")
    timeline.add("gap_after_right", 0.50)
    for freq in (20, 30, 40, 50, 80, 100, 200, 500, 1000, 2000, 5000, 10000, 15000, 20000):
        timeline.add(f"tone_{freq}Hz", 0.80, float(freq), 0.18, "both")
    timeline.add("final_silence", 1.0)
    return timeline


def sine(frame: int, freq: float, amp: float) -> int:
    value = 32767.0 * amp * math.sin(2.0 * math.pi * freq * frame / RATE)
    return int(max(-32767, min(32767, round(value))))


def write_test_wav(path: Path, timeline: Timeline) -> None:
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(2)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        frame_index = 0
        for seg in timeline.segments:
            frames = int(round(float(seg["seconds"]) * RATE))
            freq = float(seg["freq"])
            amp = float(seg["amp"])
            mode = str(seg["mode"])
            for _ in range(frames):
                if freq > 0.0 and amp > 0.0:
                    value = sine(frame_index, freq, amp)
                    if mode == "left":
                        left, right = value, 0
                    elif mode == "right":
                        left, right = 0, value
                    else:
                        left = right = value
                else:
                    left = right = 0
                wav.writeframesraw(struct.pack("<hh", left, right))
                frame_index += 1


def read_capture(path: Path) -> tuple[array.array, int]:
    raw = path.read_bytes()
    values = array.array("i")
    values.frombytes(raw[: len(raw) - (len(raw) % 4)])
    if sys.byteorder != "little":
        values.byteswap()
    frames = len(values) // ADC_CHANNELS
    return values, frames


class Analyzer:
    def __init__(self, values: array.array, frames: int) -> None:
        self.values = values
        self.frames = frames

    def sample(self, channel: int, frame: int) -> float:
        return self.values[frame * ADC_CHANNELS + channel] / FULL_SCALE

    def capture_bounds(self, start_seconds: float, end_seconds: float) -> tuple[int, int]:
        start = max(0, min(self.frames, int(round(start_seconds * RATE))))
        end = max(start, min(self.frames, int(round(end_seconds * RATE))))
        return start, end

    def wav_bounds(self, start_seconds: float, end_seconds: float, latency_seconds: float = 0.0, trim: float = 0.0) -> tuple[int, int]:
        start = CAPTURE_PRE_SECONDS + start_seconds + latency_seconds + trim
        end = CAPTURE_PRE_SECONDS + end_seconds + latency_seconds - trim
        return self.capture_bounds(start, end)

    def mean(self, channel: int, start: int, end: int) -> float:
        if end <= start:
            return 0.0
        acc = 0.0
        for frame in range(start, end):
            acc += self.sample(channel, frame)
        return acc / (end - start)

    def rms(self, channel: int, start: int, end: int, remove_dc: bool = True) -> float:
        if end <= start:
            return 0.0
        dc = self.mean(channel, start, end) if remove_dc else 0.0
        acc = 0.0
        for frame in range(start, end):
            value = self.sample(channel, frame) - dc
            acc += value * value
        return math.sqrt(acc / (end - start))

    def peak(self, channel: int, start: int, end: int) -> tuple[float, int]:
        peak = 0.0
        peak_frame = start
        for frame in range(start, end):
            value = abs(self.sample(channel, frame))
            if value > peak:
                peak = value
                peak_frame = frame
        return peak, peak_frame

    def estimate_frequency(self, channel: int, start: int, end: int, fallback: float) -> float:
        if end <= start + 4:
            return fallback
        dc = self.mean(channel, start, end)
        crossings: list[float] = []
        previous = self.sample(channel, start) - dc
        for frame in range(start + 1, end):
            current = self.sample(channel, frame) - dc
            if previous < 0.0 <= current:
                denom = current - previous
                fraction = (-previous / denom) if denom else 0.0
                crossings.append((frame - 1 + fraction) / RATE)
            previous = current
        if len(crossings) < 4:
            return fallback
        periods = [crossings[index + 1] - crossings[index] for index in range(len(crossings) - 1)]
        periods = sorted(periods)
        trim = max(1, len(periods) // 20)
        stable = periods[trim:-trim] if len(periods) > 2 * trim else periods
        avg_period = sum(stable) / len(stable)
        return 1.0 / avg_period if avg_period > 0.0 else fallback

    def projected_rms(self, channel: int, start: int, end: int, freq: float) -> float:
        count = end - start
        if count <= 8:
            return 0.0
        dc = self.mean(channel, start, end)
        sine_sum = 0.0
        cosine_sum = 0.0
        omega = 2.0 * math.pi * freq / RATE
        for index, frame in enumerate(range(start, end)):
            value = self.sample(channel, frame) - dc
            phase = omega * index
            sine_sum += value * math.sin(phase)
            cosine_sum += value * math.cos(phase)
        peak_amp = 2.0 * math.sqrt(sine_sum * sine_sum + cosine_sum * cosine_sum) / count
        return peak_amp / math.sqrt(2.0)

    def thd(self, channel: int, start: int, end: int, fundamental_freq: float) -> tuple[float, float]:
        fundamental = self.projected_rms(channel, start, end, fundamental_freq)
        harmonic_sq = 0.0
        for multiple in range(2, 6):
            harmonic_freq = fundamental_freq * multiple
            if harmonic_freq < RATE / 2:
                harmonic = self.projected_rms(channel, start, end, harmonic_freq)
                harmonic_sq += harmonic * harmonic
        thd_ratio = math.sqrt(harmonic_sq) / fundamental if fundamental > 0 else 0.0
        return fundamental, thd_ratio


def run_capture(test_wav: Path, capture_raw: Path, arecord_log: Path, aplay_log: Path, dmesg_log: Path, seconds: int) -> None:
    subprocess.run(["dmesg", "-C"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    with arecord_log.open("wb") as log:
        recorder = subprocess.Popen(
            [
                "arecord",
                "-D",
                ADC_DEVICE,
                "-c",
                str(ADC_CHANNELS),
                "-r",
                str(RATE),
                "-f",
                ADC_FORMAT,
                "-t",
                "raw",
                "-d",
                str(seconds),
                str(capture_raw),
            ],
            stdout=log,
            stderr=subprocess.STDOUT,
        )
    time.sleep(CAPTURE_PRE_SECONDS)
    with aplay_log.open("wb") as log:
        subprocess.run(["aplay", "-D", SPDIF_DEVICE, str(test_wav)], stdout=log, stderr=subprocess.STDOUT, check=True)
    recorder.wait(timeout=seconds + 10)
    if recorder.returncode:
        raise SystemExit(f"arecord failed with {recorder.returncode}; see {arecord_log}")
    with dmesg_log.open("w", encoding="utf-8") as log:
        subprocess.run(
            ["bash", "-lc", "dmesg | grep -i -E 'raspiaudio_spdif|rp1|pio|dma|underrun|xrun|error' || true"],
            stdout=log,
            stderr=subprocess.STDOUT,
        )


def main() -> int:
    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)
    timeline = build_timeline()

    test_wav = ARTIFACT_DIR / "advanced_spdif_optical_test_48k.wav"
    capture_raw = ARTIFACT_DIR / f"adc_capture_{ADC_CHANNELS}ch_{ADC_FORMAT}.raw"
    summary_path = ARTIFACT_DIR / "summary.txt"
    metrics_path = ARTIFACT_DIR / "metrics.csv"
    frequency_path = ARTIFACT_DIR / "frequency_response.csv"
    arecord_log = ARTIFACT_DIR / "arecord.log"
    aplay_log = ARTIFACT_DIR / "aplay.log"
    dmesg_log = ARTIFACT_DIR / "dmesg_spdif.log"

    write_test_wav(test_wav, timeline)
    capture_seconds = int(math.ceil(CAPTURE_PRE_SECONDS + timeline.seconds + CAPTURE_POST_SECONDS))

    print("Advanced optical loopback measurement")
    print(f"  S/PDIF output: {SPDIF_DEVICE}")
    print(f"  ADC capture:   {ADC_DEVICE}, {ADC_CHANNELS}ch, {ADC_FORMAT}, {RATE} Hz")
    print(f"  Artifacts:     {ARTIFACT_DIR}")
    print()

    run_capture(test_wav, capture_raw, arecord_log, aplay_log, dmesg_log, capture_seconds)

    values, frames = read_capture(capture_raw)
    analyzer = Analyzer(values, frames)

    marker = timeline.find("latency_marker_4k")
    marker_expected = CAPTURE_PRE_SECONDS + float(marker["start"])
    marker_start, marker_end = analyzer.capture_bounds(marker_expected - 0.05, marker_expected + 0.15)

    both = timeline.find("both_1k_10s")
    left = timeline.find("left_1k_3s")
    right = timeline.find("right_1k_3s")
    rough_start, rough_end = analyzer.wav_bounds(float(both["start"]), float(both["start"]) + float(both["seconds"]), 0.0, 0.25)

    active_candidates = []
    for channel in range(ADC_CHANNELS):
        level = analyzer.rms(channel, rough_start, rough_end)
        if dbfs(level) > -70.0:
            active_candidates.append(channel)

    latency_by_channel: dict[int, float] = {}
    for channel in active_candidates:
        marker_peak, _ = analyzer.peak(channel, marker_start, marker_end)
        threshold = max(0.05, marker_peak * 0.35)
        found = None
        for frame in range(marker_start, marker_end):
            if abs(analyzer.sample(channel, frame)) >= threshold:
                found = frame
                break
        if found is not None:
            latency_by_channel[channel] = found / RATE - marker_expected

    mean_latency = sum(latency_by_channel.values()) / len(latency_by_channel) if latency_by_channel else 0.0

    rows = []
    for channel in range(ADC_CHANNELS):
        b0, b1 = analyzer.wav_bounds(float(both["start"]), float(both["start"]) + float(both["seconds"]), mean_latency, 0.25)
        l0, l1 = analyzer.wav_bounds(float(left["start"]), float(left["start"]) + float(left["seconds"]), mean_latency, 0.15)
        r0, r1 = analyzer.wav_bounds(float(right["start"]), float(right["start"]) + float(right["seconds"]), mean_latency, 0.15)
        pre0, pre1 = analyzer.capture_bounds(0.10, 0.90)
        idle0, idle1 = analyzer.wav_bounds(0.10, 0.90, mean_latency)

        both_rms = analyzer.rms(channel, b0, b1)
        left_rms = analyzer.rms(channel, l0, l1)
        right_rms = analyzer.rms(channel, r0, r1)
        pre_noise = analyzer.rms(channel, pre0, pre1)
        stream_idle = analyzer.rms(channel, idle0, idle1)
        peak, _ = analyzer.peak(channel, 0, frames)

        block = int(0.05 * RATE)
        block_levels = []
        pos = b0
        while pos + block <= b1:
            block_levels.append(analyzer.rms(channel, pos, pos + block))
            pos += block
        sorted_blocks = sorted(block_levels)
        median = sorted_blocks[len(sorted_blocks) // 2] if sorted_blocks else 0.0
        dropouts = sum(1 for value in block_levels if median > 0.0 and value < median * 0.25)
        drift = 20.0 * math.log10(max(block_levels) / max(min(block_levels), 1e-15)) if block_levels else 0.0

        center_start, center_end = analyzer.wav_bounds(float(both["start"]) + 2.0, float(both["start"]) + 4.0, mean_latency)
        estimated_freq = analyzer.estimate_frequency(channel, center_start, center_end, 1000.0)
        fundamental, thd_ratio = analyzer.thd(channel, center_start, center_end, estimated_freq)

        rows.append(
            {
                "channel": channel,
                "peak_dbfs": dbfs(peak),
                "pre_play_noise_dbfs": dbfs(pre_noise),
                "stream_idle_dbfs": dbfs(stream_idle),
                "both_1k_dbfs": dbfs(both_rms),
                "left_1k_dbfs": dbfs(left_rms),
                "right_1k_dbfs": dbfs(right_rms),
                "latency_ms": latency_by_channel.get(channel, None) * 1000.0 if channel in latency_by_channel else None,
                "estimated_1k_freq_hz": estimated_freq,
                "fundamental_1k_dbfs": dbfs(fundamental),
                "thd_2_to_5_db": dbfs(thd_ratio),
                "dropout_blocks_50ms": dropouts,
                "block_level_drift_db": drift,
            }
        )

    active = sorted([row for row in rows if row["both_1k_dbfs"] > -70.0], key=lambda row: row["both_1k_dbfs"], reverse=True)
    active_channels = [int(row["channel"]) for row in active]
    left_channel = max(active, key=lambda row: row["left_1k_dbfs"] - row["right_1k_dbfs"])["channel"] if active else None
    right_channel = max(active, key=lambda row: row["right_1k_dbfs"] - row["left_1k_dbfs"])["channel"] if active else None

    frequency_rows = []
    for row in active[:2]:
        channel = int(row["channel"])
        freq_ratio = float(row["estimated_1k_freq_hz"]) / 1000.0
        levels = []
        for seg in timeline.segments:
            name = str(seg["name"])
            if not name.startswith("tone_"):
                continue
            freq = float(seg["freq"])
            start, end = analyzer.wav_bounds(float(seg["start"]), float(seg["start"]) + float(seg["seconds"]), mean_latency, 0.12)
            level = analyzer.projected_rms(channel, start, end, freq * freq_ratio)
            levels.append((freq, level))
        ref = next((level for freq, level in levels if int(freq) == 1000), None)
        for freq, level in levels:
            relative = 20.0 * math.log10(max(level, 1e-15) / max(ref or level, 1e-15))
            frequency_rows.append(
                {
                    "channel": channel,
                    "freq_hz": int(freq),
                    "level_dbfs": dbfs(level),
                    "relative_to_1k_db": relative,
                }
            )

    with metrics_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        for row in rows:
            writer.writerow(
                {
                    key: "" if value is None else f"{value:.3f}" if isinstance(value, float) else value
                    for key, value in row.items()
                }
            )

    with frequency_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=["channel", "freq_hz", "level_dbfs", "relative_to_1k_db"])
        writer.writeheader()
        for row in frequency_rows:
            writer.writerow(
                {
                    "channel": row["channel"],
                    "freq_hz": row["freq_hz"],
                    "level_dbfs": f"{row['level_dbfs']:.2f}",
                    "relative_to_1k_db": f"{row['relative_to_1k_db']:.2f}",
                }
            )

    frequency_summary = []
    for channel in active_channels[:2]:
        values_for_channel = [
            row["relative_to_1k_db"]
            for row in frequency_rows
            if row["channel"] == channel and 30 <= row["freq_hz"] <= 15000
        ]
        if values_for_channel:
            frequency_summary.append(
                (channel, min(values_for_channel), max(values_for_channel), max(values_for_channel) - min(values_for_channel))
            )

    with summary_path.open("w", encoding="utf-8") as handle:
        handle.write("Advanced optical S/PDIF loopback summary\n")
        handle.write(f"Artifact directory: {ARTIFACT_DIR}\n")
        handle.write(f"Capture seconds: {frames / RATE:.3f}\n")
        handle.write(f"Active channels over -70 dBFS: {active_channels}\n")
        handle.write(f"Inferred left channel: IN{left_channel}\n" if left_channel is not None else "Inferred left channel: n/a\n")
        handle.write(f"Inferred right channel: IN{right_channel}\n" if right_channel is not None else "Inferred right channel: n/a\n")
        if latency_by_channel:
            latencies = [value * 1000.0 for value in latency_by_channel.values()]
            handle.write(f"Latency active-channel mean: {sum(latencies) / len(latencies):.3f} ms\n")
            handle.write(f"Latency active-channel spread: {max(latencies) - min(latencies):.3f} ms\n")
        handle.write("\nActive channel metrics:\n")
        for row in active[:2]:
            channel = row["channel"]
            if channel == left_channel:
                role = "left"
                crosstalk = row["right_1k_dbfs"] - row["left_1k_dbfs"]
            elif channel == right_channel:
                role = "right"
                crosstalk = row["left_1k_dbfs"] - row["right_1k_dbfs"]
            else:
                role = "active"
                crosstalk = 0.0
            handle.write(
                f"  IN{channel} ({role}): 1k={row['both_1k_dbfs']:.1f} dBFS, "
                f"pre-play noise={row['pre_play_noise_dbfs']:.1f} dBFS, "
                f"stream idle={row['stream_idle_dbfs']:.1f} dBFS, "
                f"THD~{row['thd_2_to_5_db']:.1f} dB, "
                f"crosstalk~{crosstalk:.1f} dB, "
                f"dropouts={row['dropout_blocks_50ms']}, "
                f"block drift={row['block_level_drift_db']:.3f} dB\n"
            )
        handle.write("\nFrequency response, relative to 1 kHz stepped tone:\n")
        for channel, low, high, span in frequency_summary:
            handle.write(f"  IN{channel}: 30 Hz..15 kHz min={low:.2f} dB max={high:.2f} dB span={span:.2f} dB\n")
        handle.write("\nInterpretation:\n")
        handle.write("- Publish dropout, mapping, loopback latency, crosstalk, level stability, and frequency-response sanity results.\n")
        handle.write("- Treat THD as a rough chain measurement: it includes the optical DAC/converter and ADC.\n")
        handle.write("- Do not publish SNR, THD+N, jitter, or S/PDIF compliance from this loopback alone.\n")

    print(summary_path.read_text(encoding="utf-8"))
    print(f"Metrics CSV: {metrics_path}")
    print(f"Frequency response CSV: {frequency_path}")
    print(f"Logs: {arecord_log}, {aplay_log}, {dmesg_log}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
