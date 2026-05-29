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

## Long Test

```bash
timeout 3600 /usr/local/bin/camilladsp -l info -o /tmp/camilladsp.log /etc/camilladsp/8in_8out_passthrough.yml
grep -iE 'error|warn|xrun|underrun|overrun' /tmp/camilladsp.log || true
```
