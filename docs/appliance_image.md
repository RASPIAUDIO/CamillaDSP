# RASPIAUDIO CamillaDSP Box Image Guide

This is the manufacturer workflow for shipping a beginner-friendly image.

For the public beginner flashing guide, link users to:
[flash_appliance_image.md](flash_appliance_image.md)

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

For faster lab iteration, enable the hidden lab mode on the test image only:

```bash
sudo touch /etc/raspiaudio/lab-mode
sudo systemctl restart raspiaudio-web.service
```

The public dashboard must not show GitHub/lab update controls. The lab image
still accepts the hidden `/api/lab-update` endpoint when
`/etc/raspiaudio/lab-mode` exists, but normal users should only see
`Update system`.

The lab updater pulls the latest `main` branch into
`/opt/raspiaudio-camilladsp`, copies the dashboard/scripts, profiles and
systemd units, then restarts the audio services. This is much faster than
reflashing the SD card after every small change.

Equivalent shell command:

```bash
sudo raspiaudio-dev-update fast
```

Use a full reinstall only when package/install logic changed:

```bash
sudo raspiaudio-dev-update full
```

The release cleanup removes `/etc/raspiaudio/lab-mode`, so this button is not
visible in the public beginner image.

Network boot is possible on Raspberry Pi 5 for deeper kernel/rootfs work, but
it is heavier than necessary for ordinary CamillaDSP/dashboard iteration. For
our lab tests, prefer this workflow:

```text
flash once -> enable lab mode -> call /api/lab-update or run raspiaudio-dev-update -> retest
```

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
- Public update-channel reader and bundled changelog.
- Hidden lab updater for development images.
- Beginner health checks for USB gadget, analog output card, TOSLINK, services
  and `raspiaudio.local`.

## Hardware Modes

The image supports both boards with one public image:

- `8xout`
- `8xin8xout`

Both use:

```text
dtoverlay=hifiberry-dac8x
```

The default is `hardware=auto`. The official `hifiberry-dac8x` overlay exposes
`hasadc-gpio` on GPIO5 active-low. The kernel driver reads that GPIO at boot and
creates the ADC capture device only when the board has the input section. The
appliance therefore detects the board from ALSA:

- playback card only: `8xout`
- playback card + ADC capture card: `8xin8xout`

The beginner image should ship in `Auto detect`. The public dashboard does not
show a hardware selector; only the internal API/script override remains for lab
tests. The dashboard displays the detected hardware status, shows only modes
that make sense for that board, and greys out modes that need a missing runtime
device such as the TOSLINK ALSA card.

The old board-specific ADC module option is legacy/lab-only. Keep it empty
unless a development driver explicitly requires it.

Example when the final driver option is known:

```bash
sudo RASPIAUDIO_HARDWARE=8xin8xout \
  RASPIAUDIO_ADC_DRIVER_OPTION='options snd_rpi_hifiberry_dac8x adc_enable=1' \
  ./appliance/install_appliance.sh
```

Replace the example option with the real RASPIAUDIO driver option before
publishing a special lab image.

On 8xIN+8xOUT, the local ALSA layout is:

- analog ADC inputs: `hw:CARD=sndrpihifiberry,DEV=0`, 8 channels
- analog DAC outputs: `hw:CARD=sndrpihifiberry,DEV=0`, 8 channels

The V1 beginner image uses these inputs locally for CamillaDSP monitor/test
modes. It does not yet expose the 8 analog inputs to the host computer as a USB
recording device.

## Image Release

The public release channel is intentionally image-based. `Update system` reads:

```text
https://raspiaudio.com/camilladsp-box/releases.json
```

or `/etc/raspiaudio/update-channel-url` if a test image overrides it. The
button reports the latest image, SHA256, Raspberry Pi Imager repository URL,
and changelog. It does not rewrite the live SD card in place.

The channel format is documented in:

```text
appliance/update-channel.example.json
```

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
PC USB 7.1 -> 8 analog outputs
```

Then image the SD card on your computer and publish:

```text
raspiaudio-dspbox-pi5-YYYY.MM.DD.img.xz
raspiaudio-dspbox-pi5-YYYY.MM.DD.img.xz.sha256
```

Copy the final files into `public/camilladsp-box/`, together with the matching
`raspiaudio-imager-repository-YYYY.MM.DD.json`, then run the public page gate:

```bash
python3 scripts/validate_public_camilladsp_box.py
```

After uploading the folder to the website, verify the live beginner entry point
and release channel:

```bash
python3 scripts/validate_public_camilladsp_box.py \
  --base-url https://raspiaudio.com/camilladsp-box
```

The strict public gate must pass before claiming that the appliance image is
publicly ready. It checks the beginner page copy, the 8-step setup, required
assets, image/SHA filenames, SHA256 match, Imager JSON, and live download URLs.

## Beginner Tutorial

Public tutorial:

1. Download the RASPIAUDIO CamillaDSP Box image.
2. Flash it with Raspberry Pi Imager using `Use custom image`.
3. Plug Raspberry Pi 5 + RASPIAUDIO board.
4. Connect USB-C data to the computer and power through the splitter.
5. Boot.
6. Open `http://raspiaudio.local`.
7. Choose `PC USB 7.1 -> 8 analog outputs`.
8. Click output tests.

[Windows flashing video](assets/raspberry-pi-imager-custom-image-windows.mp4)
shows the Raspberry Pi Imager `Use custom image` flow for the `.img.xz`
appliance image.

Linux details belong in the advanced documentation, not in the first tutorial.

## First-Flash Findings

Fresh-flash validation on 2026-06-29 proved:

- `http://raspiaudio.local/` comes online.
- The image can detect RASPIAUDIO hardware from the ALSA cards exposed by
  `dtoverlay=hifiberry-dac8x`.
- CamillaDSP, CamillaGUI, nginx, Avahi, and the dashboard start.
- The analog 8-output ALSA card and analog 8-input ALSA card are visible.

The same test found fixes that must be included in the next image:

- Dashboard output tests must temporarily stop CamillaDSP before using
  `speaker-test`, otherwise ALSA returns `Device or resource busy`.
- Diagnostics download must remove the pre-created temporary file before
  writing the zip.
- The dashboard needs a `Restart USB gadget` action for cases where the Pi USB-C
  controller reports `not attached` even though the data cable is connected.
- TOSLINK test should try to build/load the GPIO12 `RASPISPDIF` driver if the
  first-boot service did not leave the ALSA card visible.

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

Latest fresh-flash validation notes:
[2026-06-29](appliance_validation_status_2026_06_29.md).

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
./image-builder/build_public_release.sh
```

Set `RASPIAUDIO_RELEASE_VERSION=YYYY.MM.DD` when you want an exact public
filename.

The builder uses:

- `image-builder/config/raspiaudio-dspbox-pi5.yaml`
- `image-builder/bdebstrap/customize90-raspiaudio-appliance`
- the current repo packaged into `image-builder/source/raspiaudio-camilladsp.tar`

The RASPIAUDIO wrapper creates the publishable Raspberry Pi Imager artefact in:

```text
~/rpi-image-gen/work/deploy-*/raspiaudio-dspbox-pi5-YYYY.MM.DD.img.xz
~/rpi-image-gen/work/deploy-*/raspiaudio-dspbox-pi5-YYYY.MM.DD.img.xz.sha256
~/rpi-image-gen/work/deploy-*/raspiaudio-imager-repository-YYYY.MM.DD.json
artifacts/camilladsp-box-public-YYYY.MM.DD.zip
```

The Imager repository JSON is only generated when
`RASPIAUDIO_IMAGE_BASE_URL` is set. Use:

```bash
RASPIAUDIO_IMAGE_BASE_URL=https://raspiaudio.com/camilladsp-box/downloads
```

Publish it only after the exact image has passed the fresh-flash validation
checklist.

The generated image must still pass the validation checklist above before it is
published as a beta or release image. Use `CREATE_XZ=0` only for faster local
lab builds where a release artefact is not needed.

If the image was already built and validated, stage the public site bundle from
the real image without rebuilding:

```bash
./image-builder/build_public_release.sh \
  --skip-build \
  --image ~/rpi-image-gen/work/deploy-v2.7.0/raspiaudio-dspbox-pi5-YYYY.MM.DD.img.xz \
  --raw-image ~/rpi-image-gen/work/image-raspiaudio-dspbox-pi5/raspiaudio-dspbox-pi5.img
```

That command writes the public `downloads/` files, updates `releases.json`,
updates the `Download image` link, validates the local public bundle, and
creates `artifacts/camilladsp-box-public-YYYY.MM.DD.zip` for upload.

Current candidate validation status:
[appliance_validation_status_2026_06_28.md](appliance_validation_status_2026_06_28.md)
