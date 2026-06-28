# RASPIAUDIO CamillaDSP Box Image Guide

This is the manufacturer workflow for shipping a beginner-friendly image.

The product promise is:

```text
Flash image -> boot -> open http://raspiaudio.local -> choose mode -> test audio
```

Do not present this as "install CamillaDSP on Linux". Present it as a
RASPIAUDIO audio appliance.

## What To Flash First

For development, start with a blank microSD card and Raspberry Pi Imager:

- Device: `Raspberry Pi 5`.
- OS: `Raspberry Pi OS Lite 64-bit`.
- Hostname: `raspiaudio-dev`.
- User: `raspiaudio`.
- Password: temporary lab password only.
- SSH: enabled for development only.

This development image is only a working master. It must not be published.

## What Gets Installed

Run:

```bash
sudo apt update
sudo apt install -y git
git clone https://github.com/RASPIAUDIO/CamillaDSP.git raspiaudio-camilladsp
cd raspiaudio-camilladsp
sudo ./appliance/install_appliance.sh
sudo reboot
```

The appliance installer adds:

- CamillaDSP.
- CamillaGUI.
- RASPIAUDIO USB gadget 7.1 / 48 kHz / S32_LE.
- RASPIAUDIO 8-output profiles.
- Active crossover profiles.
- TOSLINK profiles.
- `RASPISPDIF` driver install attempt for GPIO12 optical output.
- `raspiaudio.local` mDNS through Avahi.
- Beginner web dashboard on port 80.
- Advanced CamillaGUI on port 5005.
- Mode switcher through `/etc/camilladsp/current.yml`.
- Diagnostics zip generator.

## Hardware Modes

The image supports both:

- `8xout`
- `8xin8xout`

Both use:

```text
dtoverlay=hifiberry-dac8x
```

The 8xIN+8xOUT mode uses the same driver/overlay, plus the board-specific driver
option that enables the ADC path. Keep this option empty for 8xOUT images.

Example when the final driver option is known:

```bash
sudo RASPIAUDIO_HARDWARE=8xin8xout \
  RASPIAUDIO_ADC_DRIVER_OPTION='options snd_rpi_hifiberry_dac8x adc_enable=1' \
  ./appliance/install_appliance.sh
```

Replace the example option with the real RASPIAUDIO driver option before
publishing an 8xIN+8xOUT image.

On 8xIN+8xOUT, the local ALSA layout is:

- analog ADC inputs: `hw:CARD=sndrpihifiberry,DEV=1`, 8 channels
- analog DAC outputs: `hw:CARD=sndrpihifiberry,DEV=0`, 8 channels

The V1 beginner image uses these inputs locally for CamillaDSP monitor/test
modes. It does not yet expose the 8 analog inputs to the host computer as a USB
recording device.

## Image Release

Before publishing, clean the development image:

```bash
cd ~/raspiaudio-camilladsp
sudo ./appliance/release/prepare_release_image.sh
sudo poweroff
```

The release cleanup removes:

- logs
- shell history
- SSH host keys
- user SSH keys
- Wi-Fi state
- machine-id

It also resets the default mode to:

```text
PC USB 7.1 to 8 analog outputs
```

Then image the SD card on your computer and publish:

```text
raspiaudio-dspbox-pi5-YYYY.MM.DD.img.xz
raspiaudio-dspbox-pi5-YYYY.MM.DD.img.xz.sha256
```

## Beginner Tutorial

Public tutorial:

1. Download the RASPIAUDIO CamillaDSP Box image.
2. Flash it with Raspberry Pi Imager using `Use custom image`.
3. Plug Raspberry Pi 5 + RASPIAUDIO board.
4. Connect USB-C data to the computer and power through the splitter.
5. Boot.
6. Open `http://raspiaudio.local`.
7. Choose `PC USB 7.1 to 8 analog outputs`.
8. Click output tests.

Linux details belong in the advanced documentation, not in the first tutorial.

## Validation Checklist

Before publishing a beta image:

- Fresh flash on a new SD card.
- Boot on Raspberry Pi 5 + 8xOUT.
- `http://raspiaudio.local` opens.
- USB 7.1 device appears on Windows.
- Output tests work on OUT1 to OUT8.
- TOSLINK mode locks a receiver on GPIO12.
- Reboot keeps the selected mode.
- Diagnostics zip downloads and contains ALSA, services, logs and boot config.
- Repeat on 8xIN+8xOUT with ADC mode enabled.

## Future Production Build

The first beta can be a cleaned master SD image.

The production image should be built with Raspberry Pi `rpi-image-gen`, so the
image is reproducible and does not depend on manual SD-card cloning.
