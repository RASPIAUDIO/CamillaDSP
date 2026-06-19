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

For a beginner-friendly full setup of a Raspberry Pi 5 as a USB 7.1 sound card
with RASPIAUDIO 8xOUT passthrough, use:

```bash
git clone https://github.com/RASPIAUDIO/CamillaDSP.git myCamillaDSP
cd myCamillaDSP
sudo ./install_raspiaudio_usb_7_1.sh
```

Full guide:

```text
profiles/raspiaudio_8xout_usb_7_1_quickstart/README.md
```

On the Raspberry Pi:

```bash
git clone <repository-url> myCamillaDSP
cd myCamillaDSP
./scripts/install_camilladsp_pi5.sh
./scripts/install_camilladsp_global_pi5.sh
./scripts/install_camillagui_pi5.sh
./scripts/inspect_pi_audio.sh
/usr/local/bin/camilladsp --check /etc/camilladsp/8in_8out_passthrough.yml
```

To run CamillaDSP manually for testing with the global installation:

```bash
sudo systemctl start camilladsp.service
sudo systemctl status camilladsp.service
sudo systemctl stop camilladsp.service
```

The optional web GUI is available after installation at:

```text
http://<raspberry-pi-ip>:5005/gui/index.html
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
  usb_gadget_2ch_48k_to_8xout.yml
                              USB gadget stereo input to RASPIAUDIO 8-output routing
  usb_gadget_8ch_48k_to_8xout.yml
                              USB gadget 8-channel input to RASPIAUDIO 8-output routing
  usb_gadget_2ch_48k_to_2ch_output.yml
                              USB gadget stereo input to 2-output routing
  8xin8xout_physical_passthrough.yml
                              RASPIAUDIO 8-input to 8-output routing
docs/
  installation_pi5.md        Raspberry Pi 5 installation
  camillagui_installation.md CamillaGUI web interface installation
  usb_audio_gadget_pi5.md    Pi 5 USB Audio Class 2 gadget setup
  usb_gadget_2ch_to_8xout.md
                              USB stereo input to RASPIAUDIO 8-output tutorial
  usb_gadget_8ch_to_8xout.md
                              USB 8-channel input to RASPIAUDIO 8-output tutorial
  carte_raspiaudio_8x8.md    ALSA inventory for the board
  camilladsp_signalgenerator_loopback_test.md
                              Loopback test using CamillaDSP SignalGenerator
  8xin8xout_channel_mapping.md
                              RASPIAUDIO 8xIN+8xOUT ALSA channel mapping
  loopback_stereo_jack_test.md
                              Stereo jack loopback measurement
  tests_validation.md        Validation procedures
  service_systemd.md         Automatic startup
  troubleshooting.md         Troubleshooting
scripts/
  install_camilladsp_pi5.sh  User-local installation without sudo
  install_camilladsp_global_pi5.sh
                              Global installation with sudo
  install_camillagui_pi5.sh  CamillaGUI web interface installation
  inspect_pi_audio.sh        ALSA audio inventory
  setup_usb_audio_gadget_pi5.sh
                              Configure Pi 5 as a 2-channel USB audio gadget
  diagnose_usb_audio_gadget_pi5.sh
                              Diagnose gadget attachment, ALSA, and CamillaDSP
  test_outputs_8ch.sh        8-output test
  test_inputs_8ch.sh         8-input test
  test_loopback_stereo_jack.sh
                              Stereo jack loopback test and analysis
  test_camilladsp_signalgen_loopback.sh
                              SignalGenerator loopback test and analysis
profiles/
  usb_gadget_7_1_48k_8xout/
                              Self-contained 7.1 USB gadget profile, installer,
                              verifier, test WAV generator, and 48/96 kHz
                              bandwidth notes
systemd/
  camilladsp.service         System-wide service
  camillagui.service         CamillaGUI web service
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

For CamillaGUI control, the system service enables the CamillaDSP websocket API
on local port `1234` and stores the active configuration state in
`/var/lib/camilladsp/statefile.yml`.

The user-local installation remains useful as a staging area and fallback.

PipeWire is active on the Pi, but the CamillaDSP tests use ALSA directly through
`hw:CARD=sndrpihifiberry,DEV=0` to avoid conversion and software remixing.

Additional RASPIAUDIO 8-output ALSA validation on 2026-06-17:

- Output board: RASPIAUDIO 8xOUT / 8xIN+8xOUT output side
- ALSA playback device: detected automatically by the quick-start installer
- Capture/playback validated at 48000 Hz, 8 channels, `S32_LE`
- Measured physical loopback mapping: logical 1:1 on all 8 channels
- Validated configuration: `configs/8xin8xout_physical_passthrough.yml`
- Measurement notes: `docs/8xin8xout_channel_mapping.md`

USB Audio Gadget profiles:

- 2-channel host-to-Pi input to 8 outputs: `docs/usb_gadget_2ch_to_8xout.md`
- 8-channel host-to-Pi input to 8 outputs: `docs/usb_gadget_8ch_to_8xout.md`
- Self-contained 7.1 / 48 kHz profile bundle:
  `profiles/usb_gadget_7_1_48k_8xout/README.md`
