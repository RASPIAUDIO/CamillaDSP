# Troubleshooting

## `Device or resource busy`

The direct ALSA device is already open. Find the process:

```bash
fuser -v /dev/snd/*
```

Stop the relevant application or use a non-direct ALSA device for a one-off
test.

Also check whether the global CamillaDSP service is running:

```bash
sudo systemctl status camilladsp.service
sudo systemctl stop camilladsp.service
```

## No Sound on Output

Check the card:

```bash
aplay -l
cat /proc/asound/cards
```

Test ALSA without CamillaDSP:

```bash
./scripts/test_outputs_8ch.sh
```

## Empty Capture or Wrong Channel

Test ALSA directly:

```bash
DURATION=10 ./scripts/test_inputs_8ch.sh
```

Then inspect the WAV file in an audio editor that can display all 8 channels.

## Rejected Format

The tested board reports:

```text
S16_LE S24_LE S32_LE
```

CamillaDSP 4.1.3 and the ALSA tools use the same notation here: `S32_LE`.

## Too Much Latency or Instability

Try this in `configs/*.yml`:

```yaml
chunksize: 512
target_level: 512
```

If XRUNs appear, revert to `1024`.

## Service Does Not Start

Check the system service and logs:

```bash
sudo systemctl status camilladsp.service
sudo journalctl -u camilladsp.service -n 100 --no-pager
tail -100 /var/log/camilladsp/camilladsp.log
```

Revalidate the installed configuration:

```bash
/usr/local/bin/camilladsp --check /etc/camilladsp/8in_8out_passthrough.yml
```
