# RASPIAUDIO CamillaDSP Box Appliance

This folder turns the existing CamillaDSP profiles into a beginner-friendly
audio appliance:

```text
Flash image -> boot -> open http://raspiaudio.local -> choose mode -> test audio
```

The normal user should not need SSH, ALSA commands, YAML editing, `dtoverlay`,
`systemctl`, or `aplay`.

## V1 Target

- Raspberry Pi 5.
- Raspberry Pi OS Lite 64-bit.
- RASPIAUDIO 8xOUT or RASPIAUDIO 8xIN+8xOUT.
- One host USB profile: 7.1 / 8 channels / 48 kHz / S32_LE.
- CamillaDSP + CamillaGUI preinstalled.
- `dtoverlay=hifiberry-dac8x` for both boards.
- Optional optical TOSLINK stereo output on GPIO12 through `RASPISPDIF`.

8xOUT and 8xIN+8xOUT use the same Linux audio overlay. The appliance defaults
to `hardware=auto`: the official `hifiberry-dac8x` overlay declares
`hasadc-gpio` on GPIO5 active-low, the kernel driver uses that pin at boot, and
the appliance then checks ALSA to see whether the ADC capture device exists.
Manual `8xout` and `8xin8xout` overrides remain available for lab work.

For the 8xIN+8xOUT board, the appliance includes local 8-channel ADC capture and
8-channel analog playback support:

- analog inputs: `hw:CARD=sndrpihifiberry,DEV=0`
- analog outputs: `hw:CARD=sndrpihifiberry,DEV=0`
- CamillaDSP monitor profile: `8xin8xout_physical_passthrough.yml`

The beginner V1 USB gadget is still playback-only from the host computer to the
Pi: `PC USB 7.1 -> CamillaDSP -> 8 analog outputs`. Exposing the 8 analog inputs
back to the PC as a USB recording device is phase 2.

## Install On A Development SD

Use this for development only. Do not publish a development SD image.

1. Flash a blank microSD with Raspberry Pi Imager.
2. Select `Raspberry Pi OS Lite 64-bit`.
3. In Imager advanced options, use temporary development credentials:
   - hostname: `raspiaudio-dev`
   - username: `raspiaudio`
   - password: a temporary lab password
   - SSH: enabled for development
4. Boot on Raspberry Pi 5 with the RASPIAUDIO board installed.
5. Clone the repo and run:

```bash
sudo apt update
sudo apt install -y git
git clone https://github.com/RASPIAUDIO/CamillaDSP.git raspiaudio-camilladsp
cd raspiaudio-camilladsp
sudo ./appliance/install_appliance.sh
sudo reboot
```

The default installer mode is automatic hardware detection:

```bash
sudo ./appliance/install_appliance.sh
```

For 8xIN+8xOUT development, you normally do not need a manual mode. If you want
to force it for a lab test:

```bash
sudo RASPIAUDIO_HARDWARE=8xin8xout ./appliance/install_appliance.sh
```

If the final driver exposes an ADC enable option, pass it at install time:

```bash
sudo RASPIAUDIO_HARDWARE=8xin8xout \
  RASPIAUDIO_ADC_DRIVER_OPTION='options snd_rpi_hifiberry_dac8x adc_enable=1' \
  ./appliance/install_appliance.sh
```

This driver option is legacy/lab-only. With the upstream-style
`hifiberry-dac8x` overlay, GPIO5 `hasadc-gpio` should be enough and the option
should stay empty.

## Use

Open:

```text
http://raspiaudio.local/
```

The appliance dashboard exposes:

- `PC USB 7.1 to 8 analog outputs`
- `PC USB front L/R to optical TOSLINK stereo`
- `Stereo active crossover to 8 outputs`
- `8 analog inputs monitor/test` for 8xIN+8xOUT
- automatic hardware detection status; there is no beginner hardware selector
- only modes supported by the detected board are shown
- modes that need a missing runtime device, such as TOSLINK, are greyed out
- system checks for USB gadget, analog output card, TOSLINK, services and
  `raspiaudio.local`
- output tests
- TOSLINK test
- diagnostics zip
- release-candidate checks
- link to the advanced CamillaDSP editor

Advanced CamillaDSP editor:

```text
http://raspiaudio.local:5005/gui/index.html
```

## Public Image Rule

Never publish a raw development SD image. A public image must not contain:

- your development password
- SSH keys
- Wi-Fi credentials
- Raspberry Pi Connect account data
- shell history
- old logs
- a fixed `/etc/machine-id`

Before imaging the SD card for beta release, run:

```bash
sudo ./appliance/release/prepare_release_image.sh
sudo poweroff
```

Then image the SD card from your PC, compress it as `.img.xz`, and publish a
matching SHA256 file.

## Health Check

The dashboard calls:

```bash
raspiaudio-health --json
```

This is the beginner support surface. It reports the common first-run failures:

- `raspiaudio.local` / Avahi not ready
- USB gadget profile missing
- `UAC2Gadget` not visible
- analog output card not visible
- hardware auto-detection result from ALSA / GPIO5 `hasadc-gpio`
- 8xIN ADC not visible when effective hardware is `8xin8xout`
- TOSLINK `RASPISPDIF` card not visible
- CamillaDSP or CamillaGUI service inactive

The diagnostics zip includes both text and JSON health reports.

## Release Validation

After flashing a candidate public image, run:

```bash
sudo raspiaudio-validate-release
```

The same check is available from the dashboard with `Run release checks`.

It verifies the appliance-level requirements that can be proven from the Pi:

- Raspberry Pi 5 model.
- `raspiaudio.local` hostname and mDNS services.
- USB gadget and RASPIAUDIO audio boot overlays.
- USB Audio Gadget 7.1 / 48 kHz / S32_LE profile.
- CamillaDSP, CamillaGUI, nginx and dashboard services.
- Local dashboard and CamillaGUI HTTP endpoints.
- UAC2Gadget, RASPIAUDIO analog output and optional analog input ALSA cards.
- GPIO12 `RASPISPDIF` optical ALSA card.
- Default CamillaDSP profile after a fresh flash.
- Diagnostics zip generation.

If no optical hardware is fitted during a lab check, use:

```bash
sudo raspiaudio-validate-release --allow-missing-toslink
```

Manual checks are still required for host OS detection, real sound on all eight
outputs, optical receiver lock, and power-cycle mode persistence.

## Long-Term Release Path

The quick beta path is a cleaned master SD image.

The reproducible production path is in:

```text
image-builder/
```

It uses Raspberry Pi `rpi-image-gen` so every release can be built from source
instead of manually cloned from a lab SD card.
