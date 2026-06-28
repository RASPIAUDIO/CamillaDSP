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
- Release-candidate validator.
- Beginner health checks for USB gadget, analog output card, TOSLINK, services
  and `raspiaudio.local`.

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

- analog ADC inputs: `hw:CARD=sndrpihifiberry,DEV=0`, 8 channels
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

1. Fresh flash on a new SD card.
2. Boot on Raspberry Pi 5 + 8xOUT.
3. Open `http://raspiaudio.local`.
4. Run the automatic release checks from the dashboard, or from a shell:

   ```bash
   sudo raspiaudio-validate-release
   ```

   If the image being checked has no optical hardware fitted yet:

   ```bash
   sudo raspiaudio-validate-release --allow-missing-toslink
   ```

   The validator checks the Pi 5 model, hostname, boot overlays, USB gadget
   profile, services, dashboard, CamillaGUI, ALSA cards, active default profile,
   health report, diagnostics zip generation, and TOSLINK driver presence.

5. Confirm Windows/macOS/Linux sees the USB device as an 8-channel / 7.1 /
   48 kHz output.
6. Run the dashboard output tests on OUT1 to OUT8 at low volume.
7. TOSLINK mode: confirm the GPIO12 optical receiver locks and plays clean audio
   for at least 10 minutes.
8. Power-cycle and confirm the selected mode persists.
9. Download the diagnostics zip and keep it with the release notes.
10. Repeat output-side validation on 8xIN+8xOUT with ADC mode enabled.

The command is intentionally not the whole release proof. Host OS detection,
real analog sound on every output, receiver lock, and power-cycle persistence
are still manual product checks.

## Future Production Build

The first beta can be a cleaned master SD image.

The reproducible production path is now under:

```text
image-builder/
```

Build on a Raspberry Pi OS 64-bit host with:

```bash
git clone https://github.com/raspberrypi/rpi-image-gen.git ~/rpi-image-gen
cd ~/rpi-image-gen
sudo ./install_deps.sh

cd ~/CamillaDSP
./image-builder/build_image.sh
```

The builder uses:

- `image-builder/config/raspiaudio-dspbox-pi5.yaml`
- `image-builder/bdebstrap/customize90-raspiaudio-appliance`
- the current repo packaged into `image-builder/source/raspiaudio-camilladsp.tar`

The generated image must still pass the validation checklist above before it is
published as a beta or release image.
