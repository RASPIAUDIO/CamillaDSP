# CamillaDSP SignalGenerator Loopback Test

This test uses CamillaDSP itself as the signal source. The capture device is
`SignalGenerator`, and playback goes to the RASPIAUDIO ALSA output device.

This is different from `loopback_stereo_jack_test.md`, where the output signal
is a prepared WAV played by `aplay`.

## Purpose

Validate that CamillaDSP can:

- generate a test tone internally,
- route it through the DSP pipeline,
- play it on the RASPIAUDIO second stereo output jack,
- and produce the expected signal on the corresponding looped-back input jack.

## Limitation

CamillaDSP `SignalGenerator` generates the same signal on every generated
channel. It is therefore useful for validating signal presence and level, but it
does not distinguish left and right with different frequencies in a single run.
For left/right identification, use `docs/loopback_stereo_jack_test.md`.

## Configuration

Config file:

```text
configs/signalgen_500hz_out2_out3.yml
```

Installed global path:

```text
/etc/camilladsp/signalgen_500hz_out2_out3.yml
```

Signal:

```text
SignalGenerator sine
frequency: 500 Hz
level: -18 dB
outputs: channels 2 and 3 only
```

## Reproduce the Test

Install or refresh the global configuration:

```bash
./scripts/install_camilladsp_global_pi5.sh
```

Stop the persistent service so the test can use the ALSA device:

```bash
sudo systemctl stop camilladsp.service
```

Run:

```bash
./scripts/test_camilladsp_signalgen_loopback.sh
```

The script starts `arecord`, then runs CamillaDSP for a short time using:

```bash
/usr/local/bin/camilladsp -l info -o /tmp/camilladsp_signalgen_loopback/camilladsp_signalgen.log /etc/camilladsp/signalgen_500hz_out2_out3.yml
```

## Expected Result

With one stereo jack-to-jack cable connected on the second stereo jack pair, the
strongest 500 Hz signal should be present on input channels `2` and `3`.

The other inputs should remain near the noise floor.

## Measured Result

The test performed on 2026-05-29 produced:

```text
channel,rms_dbfs,peak_dbfs,500hz_rel_db,500hz_snr_db
0,-107.20,-94.30,-125.7,9.8
1,-107.18,-93.25,-123.9,12.0
2,-21.08,-18.07,-0.0,135.0
3,-21.05,-18.04,0.0,134.8
4,-107.25,-94.28,-128.7,6.6
5,-107.38,-94.56,-127.2,8.5
6,-107.41,-94.55,-126.2,9.5
7,-107.39,-93.45,-128.1,7.7
strongest_inputs 3,2
```

Interpretation:

```text
CamillaDSP SignalGenerator 500 Hz -> output channels 2 and 3
Physical loopback                 -> input channels 2 and 3
```

The captured input WAV and CamillaDSP log were copied locally to:

```text
artifacts/camilladsp_signalgen_loopback/IN_record_camilladsp_signalgen_500Hz_s32_8ch.wav
artifacts/camilladsp_signalgen_loopback/camilladsp_signalgen.log
```
