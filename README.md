# myCamillaDSP

Installation, test, and documentation for running CamillaDSP with the RASPIAUDIO
8xIN + 8xOUT audio board on a Raspberry Pi 5 running 64-bit Raspberry Pi OS.

Tested state on 2026-05-28:

- Raspberry Pi 5, `aarch64` architecture
- Debian GNU/Linux 13 `trixie`, kernel `6.12.75+rpt-rpi-2712`
- ALSA audio card: `sndrpihifiberry`
- ALSA device: `hw:CARD=sndrpihifiberry,DEV=0`
- Playback: 8 channels available
- Capture: 8 channels available
- Observed ALSA formats: `S16_LE`, `S24_LE`, `S32_LE`
- Observed capture rates: 8000 Hz to 192000 Hz
- Playback rate validated by CamillaDSP: 48000 Hz
- Validated configuration: 48000 Hz, 8 channels, `S32_LE`
- Tested CamillaDSP version: `4.1.3`
- Global binary: `/usr/local/bin/camilladsp`
- Global configuration directory: `/etc/camilladsp`
- Global log directory: `/var/log/camilladsp`
- Global service: `camilladsp.service`

## Quick Start

On the Raspberry Pi:

```bash
git clone <repository-url> myCamillaDSP
cd myCamillaDSP
./scripts/install_camilladsp_pi5.sh
./scripts/install_camilladsp_global_pi5.sh
./scripts/inspect_pi_audio.sh
/usr/local/bin/camilladsp --check /etc/camilladsp/8in_8out_passthrough.yml
```

To run CamillaDSP manually for testing with the global installation:

```bash
sudo systemctl start camilladsp.service
sudo systemctl status camilladsp.service
sudo systemctl stop camilladsp.service
```

The default routing is intentionally neutral:

- input 1 to output 1
- input 2 to output 2
- ...
- input 8 to output 8

## Layout

```text
configs/
  8in_8out_passthrough.yml   Direct 8-input to 8-output routing
  8in_8out_gain_test.yml     Variant with per-channel gain filters
  signalgen_500hz_out2_out3.yml
                              CamillaDSP SignalGenerator loopback config
docs/
  installation_pi5.md        Raspberry Pi 5 installation
  carte_raspiaudio_8x8.md    ALSA inventory for the board
  camilladsp_signalgenerator_loopback_test.md
                              Loopback test using CamillaDSP SignalGenerator
  loopback_stereo_jack_test.md
                              Stereo jack loopback measurement
  tests_validation.md        Validation procedures
  service_systemd.md         Automatic startup
  troubleshooting.md         Troubleshooting
scripts/
  install_camilladsp_pi5.sh  User-local installation without sudo
  install_camilladsp_global_pi5.sh
                              Global installation with passwordless sudo
  inspect_pi_audio.sh        ALSA audio inventory
  test_outputs_8ch.sh        8-output test
  test_inputs_8ch.sh         8-input test
  test_loopback_stereo_jack.sh
                              Stereo jack loopback test and analysis
  test_camilladsp_signalgen_loopback.sh
                              SignalGenerator loopback test and analysis
systemd/
  camilladsp.service         System-wide service
  camilladsp-user.service    User systemd service
```

## Important Notes

The preferred deployment is now the global installation:

```text
/usr/local/bin/camilladsp
/etc/camilladsp/*.yml
/etc/systemd/system/camilladsp.service
/var/log/camilladsp/camilladsp.log
```

The user-local installation remains useful as a staging area and fallback.

PipeWire is active on the Pi, but the CamillaDSP tests use ALSA directly through
`hw:CARD=sndrpihifiberry,DEV=0` to avoid conversion and software remixing.
