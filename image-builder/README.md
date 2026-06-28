# RASPIAUDIO Image Builder

This folder is the reproducible image path for:

```text
RASPIAUDIO CamillaDSP Box for Raspberry Pi 5
```

It uses Raspberry Pi `rpi-image-gen` instead of cloning a hand-prepared SD card.
Raspberry Pi documents this tool in:

- https://github.com/raspberrypi/rpi-image-gen
- https://github.com/raspberrypi/rpi-image-gen/blob/master/getting_started.adoc

The first public beta can still be made from a cleaned master SD card, but this
builder is the preferred production path.

## Build Host

Use a Raspberry Pi 5 or another Raspberry Pi running 64-bit Raspberry Pi OS.
This avoids cross-architecture issues when downloading and validating the
CamillaDSP binaries.

Install `rpi-image-gen` once:

```bash
git clone https://github.com/raspberrypi/rpi-image-gen.git ~/rpi-image-gen
cd ~/rpi-image-gen
sudo ./install_deps.sh
```

## Build

From this repo:

```bash
cd ~/CamillaDSP
./image-builder/build_image.sh
```

If `rpi-image-gen` is elsewhere:

```bash
RPI_IMAGE_GEN_DIR=/path/to/rpi-image-gen ./image-builder/build_image.sh
```

To pin the public release filename:

```bash
RASPIAUDIO_RELEASE_VERSION=2026.06.28 ./image-builder/build_image.sh
```

`rpi-image-gen` writes its raw and `.zst` artefacts under its `work/`
directory. The RASPIAUDIO wrapper also creates a Raspberry Pi Imager-friendly
file:

```text
~/rpi-image-gen/work/deploy-*/raspiaudio-dspbox-pi5-YYYY.MM.DD.img.xz
~/rpi-image-gen/work/deploy-*/raspiaudio-dspbox-pi5-YYYY.MM.DD.img.xz.sha256
```

Flash the `.img.xz` with Raspberry Pi Imager using `Use Custom`.

For a faster lab build without the `.img.xz` conversion:

```bash
CREATE_XZ=0 ./image-builder/build_image.sh
```

## What The Image Contains

- Raspberry Pi OS Lite 64-bit base.
- Hostname: `raspiaudio`.
- CamillaDSP and CamillaGUI.
- RASPIAUDIO USB Audio Gadget 7.1 / 8 channel / 48 kHz / S32_LE.
- RASPIAUDIO 8xOUT and 8xIN+8xOUT output-side profiles.
- Active crossover preset.
- Optical TOSLINK profiles.
- Beginner dashboard on `http://raspiaudio.local`.
- Advanced CamillaGUI on port `5005`.
- Diagnostics zip.
- Release-candidate validator.

The S/PDIF optical kernel module is built on first boot against the real running
Pi 5 kernel. This avoids compiling the module against the build host kernel.

## Public Release Checklist

Before publishing an image:

1. Flash the built image to a fresh SD card.
2. Boot on Raspberry Pi 5 + RASPIAUDIO 8xOUT.
3. Open `http://raspiaudio.local`.
4. Run:

   ```bash
   sudo raspiaudio-validate-release
   ```

   Use `--allow-missing-toslink` only for a lab image where no optical hardware
   is fitted.

5. Confirm Windows/macOS/Linux sees the USB 7.1 audio device.
6. Test OUT1 to OUT8 at low volume.
7. Test TOSLINK lock on GPIO12.
8. Power-cycle and confirm the selected mode persists.
9. Download diagnostics zip and check it contains ALSA, services, boot config,
   CamillaDSP logs, health report and release validation output.
10. Repeat output-side validation on 8xIN+8xOUT.

Only after this publish:

```text
raspiaudio-dspbox-pi5-YYYY.MM.DD.img.xz
raspiaudio-dspbox-pi5-YYYY.MM.DD.img.xz.sha256
```

## Raspberry Pi Imager Repository

`raspiaudio-imager-repository.example.json` is a starter template for a custom
Raspberry Pi Imager repository. Do not publish it until the URL, SHA256, image
size and release notes match a validated image.
