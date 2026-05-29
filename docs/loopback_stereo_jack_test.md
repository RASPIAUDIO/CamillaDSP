# Stereo Jack Loopback Test

This test documents a physical loopback made with one jack-to-jack cable between
one stereo output connector and one stereo input connector on the RASPIAUDIO
8xIN + 8xOUT board.

## Physical Setup

The board exposes 8 ALSA channels, but the physical connectors are grouped as 4
stereo input jacks and 4 stereo output jacks.

Expected logical channel grouping:

```text
Jack 1: channels 0 / 1
Jack 2: channels 2 / 3
Jack 3: channels 4 / 5
Jack 4: channels 6 / 7
```

For the captured test, a single jack-to-jack cable was connected between one
physical output jack and one physical input jack. The measurement identifies this
connection as logical channels `2 / 3`, so the cable is on the second stereo jack
pair.

## Test Signal

The output WAV is 8-channel, 32-bit PCM, 48000 Hz:

```text
channel 2: 500 Hz sine, amplitude 0.125, about -18 dBFS peak
channel 3: 1000 Hz sine, amplitude 0.125, about -18 dBFS peak
other channels: silence
```

During playback, the 8 input channels are recorded simultaneously as 32-bit PCM
at 48000 Hz.

## Reproduce the Test

Stop CamillaDSP if it is running:

```bash
sudo systemctl stop camilladsp.service
```

Run the loopback test:

```bash
./scripts/test_loopback_stereo_jack.sh
```

Default parameters:

```text
DEVICE=hw:CARD=sndrpihifiberry,DEV=0
OUT_LEFT=2
OUT_RIGHT=3
FREQ_LEFT=500
FREQ_RIGHT=1000
AMP=0.125
WORK=/tmp/raspiaudio_loopback_dual_tone
```

## Captured Files

The WAV files from the 2026-05-29 test were copied locally to:

```text
artifacts/loopback_jack_2/OUT_play_out2_500Hz_out3_1000Hz_s32_8ch.wav
artifacts/loopback_jack_2/IN_record_out2_500Hz_out3_1000Hz_s32_8ch.wav
```

These WAV files are intentionally ignored by Git because they are binary test
artifacts.

## Measured Result

Analysis of the recorded WAV:

```text
channel,rms_dbfs,peak_dbfs,500hz_rel_db,1000hz_rel_db
0,-107.30,-94.37,-125.3,-126.7
1,-107.18,-94.29,-126.4,-125.5
2,-21.14,-18.13,0.0,-74.4
3,-21.36,-18.36,-86.2,-0.2
4,-107.40,-93.69,-128.9,-126.3
5,-107.37,-93.39,-124.7,-127.2
6,-107.49,-93.58,-125.7,-127.0
7,-107.43,-94.39,-127.5,-130.8
```

Detected input channels:

```text
500 Hz  -> input channel 2
1000 Hz -> input channel 3
```

## Interpretation

The single physical jack cable carries two audio channels. In this setup:

```text
output channel 2 -> input channel 2
output channel 3 -> input channel 3
```

The other inputs remain near the noise floor, around `-107 dBFS RMS`, which
confirms that the loopback is isolated to the stereo jack pair `2 / 3`.
