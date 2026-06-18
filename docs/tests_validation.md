# Validation Tests

## Audio Inventory

```bash
./scripts/inspect_pi_audio.sh
```

Confirm that the board appears as `sndrpihifiberry`.

## Output Test

Check the output level before running this test.

```bash
./scripts/test_outputs_8ch.sh
```

The test sends a sine wave channel by channel to the 8 outputs. Physically note
which output corresponds to each ALSA label (`Front Left`, `Front Right`, etc.).

## Input Test

```bash
DURATION=10 ./scripts/test_inputs_8ch.sh
```

The generated file is:

```text
/tmp/camilladsp_8ch_capture.wav
```

## CamillaDSP Validation

```bash
/usr/local/bin/camilladsp --check /etc/camilladsp/8in_8out_passthrough.yml
/usr/local/bin/camilladsp --check /etc/camilladsp/8in_8out_gain_test.yml
```

Short non-interactive test:

```bash
timeout 6 /usr/local/bin/camilladsp -l debug -o /tmp/camilladsp_run_test.log /etc/camilladsp/8in_8out_passthrough.yml
tail -80 /tmp/camilladsp_run_test.log
```

If the device is already in use, stop the applications that are capturing from
or playing to the board, then run the test again.

## System Service Test

```bash
sudo systemctl start camilladsp.service
sleep 3
sudo systemctl status camilladsp.service
tail -60 /var/log/camilladsp/camilladsp.log
sudo systemctl stop camilladsp.service
```

The service test performed on 2026-05-28 started successfully with:

```text
/usr/local/bin/camilladsp -l info -o /var/log/camilladsp/camilladsp.log /etc/camilladsp/8in_8out_passthrough.yml
```

## Stereo Jack Loopback Test

For a physical jack-to-jack cable between one output jack and one input jack:

```bash
sudo systemctl stop camilladsp.service
./scripts/test_loopback_stereo_jack.sh
```

The documented 2026-05-29 test found:

```text
output channel 2 -> input channel 2, 500 Hz
output channel 3 -> input channel 3, 1000 Hz
```

See `docs/loopback_stereo_jack_test.md`.

## CamillaDSP SignalGenerator Loopback Test

This test uses CamillaDSP as the signal source instead of playing a WAV file:

```bash
sudo systemctl stop camilladsp.service
./scripts/install_camilladsp_global_pi5.sh
./scripts/test_camilladsp_signalgen_loopback.sh
```

Expected result with the current cable position:

```text
strongest_inputs 2,3
```

See `docs/camilladsp_signalgenerator_loopback_test.md`.

## RASPIAUDIO 8-output Physical Mapping Test

For the RASPIAUDIO 8-output ALSA profile (`XMOSDevice` in the current lab),
patch each physical output to the corresponding physical input on the same
block, then stop CamillaDSP so ALSA can access the capture and playback devices
directly:

```bash
sudo systemctl stop camilladsp.service
arecord -D hw:CARD=XMOSDevice,DEV=1 -f S32_LE -r 48000 -c 8 -d 9 xmos_8in_loopback_record_s32.wav
```

In another shell during the recording:

```bash
aplay -D hw:CARD=XMOSDevice,DEV=0 xmos_8out_sequential_test_s32.wav
```

The 2026-06-17 measurement found a logical 1:1 mapping on all 8 channels, with
more than 73 dB of margin between the matched input and the next strongest
input for every tone.

Use `configs/8xin8xout_physical_passthrough.yml` for CamillaDSP.

See `docs/8xin8xout_channel_mapping.md`.

## Long Test

```bash
timeout 3600 /usr/local/bin/camilladsp -l info -o /tmp/camilladsp.log /etc/camilladsp/8in_8out_passthrough.yml
grep -iE 'error|warn|xrun|underrun|overrun' /tmp/camilladsp.log || true
```
