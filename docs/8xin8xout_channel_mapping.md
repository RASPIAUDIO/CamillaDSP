# RASPIAUDIO 8xIN+8xOUT channel mapping

This test checks how the logical ALSA channels of `sndrpihifiberry` map to the
physical 8 input / 8 output blocks.

`sndrpihifiberry` is the Linux ALSA card name used by the current driver path on the
lab Raspberry Pi. It is not the product name; the output hardware is
RASPIAUDIO 8xOUT or the output side of RASPIAUDIO 8xIN+8xOUT.

## Hardware setup

Each physical output was patched to the corresponding physical input on the
same block:

- physical output 1 to physical input 1
- physical output 2 to physical input 2
- physical output 3 to physical input 3
- physical output 4 to physical input 4
- physical output 5 to physical input 5
- physical output 6 to physical input 6
- physical output 7 to physical input 7
- physical output 8 to physical input 8

CamillaDSP was stopped during the measurement so ALSA could access the capture
and playback devices directly.

## Test method

The generated WAV plays one tone at a time on each logical output channel:

| Logical output | Tone |
|---:|---:|
| 0 | 1000 Hz |
| 1 | 1173 Hz |
| 2 | 1346 Hz |
| 3 | 1519 Hz |
| 4 | 1692 Hz |
| 5 | 1865 Hz |
| 6 | 2038 Hz |
| 7 | 2211 Hz |

The loopback recording is then analysed with an exact-frequency projection on
each input channel. The strongest input channel for each tone is the measured
logical mapping.

## Measured result

Artifacts:

- `artifacts/channel_map_latest/raspiaudio_8out_sequential_test_s32.wav`
- `artifacts/channel_map_latest/raspiaudio_8in_loopback_record_s32.wav`
- `artifacts/channel_map_latest/raspiaudio_channel_mapping_analysis.csv`
- `artifacts/channel_map_latest/raspiaudio_channel_mapping_analysis.json`
- `artifacts/channel_map_latest/raspiaudio_channel_mapping_analysis.md`

| Logical output | Strongest logical input | Margin over second input |
|---:|---:|---:|
| 0 | 0 | 81.55 dB |
| 1 | 1 | 80.16 dB |
| 2 | 2 | 77.62 dB |
| 3 | 3 | 76.90 dB |
| 4 | 4 | 76.25 dB |
| 5 | 5 | 75.91 dB |
| 6 | 6 | 73.68 dB |
| 7 | 7 | 73.30 dB |

The mapping is therefore logical 1:1 for this ALSA device:

```text
out0 -> in0
out1 -> in1
out2 -> in2
out3 -> in3
out4 -> in4
out5 -> in5
out6 -> in6
out7 -> in7
```

## CamillaDSP profile

Use `configs/8xin8xout_physical_passthrough.yml`.

The profile uses:

- capture: `hw:CARD=sndrpihifiberry,DEV=0`
- playback: `hw:CARD=sndrpihifiberry,DEV=0`
- format: `S32_LE`
- sample rate: `48000`
- routing: `dest n <- source n` for all 8 channels

With the loopback cables still installed, avoid leaving this passthrough running
at normal gain into speakers or an amplifier. It is a feedback path by design.
