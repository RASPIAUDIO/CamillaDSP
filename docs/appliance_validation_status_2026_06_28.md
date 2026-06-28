# RASPIAUDIO CamillaDSP Box Validation Status - 2026-06-28

This page records the current proof level for the first flashable appliance
image candidate.

## Image Candidate

Built on the Raspberry Pi 5 lab unit with `rpi-image-gen`.

```text
raspiaudio-dspbox-pi5-2026.06.28.img.xz
sha256: 6a806d6a9c8a4a2c654b6c13996405f5f19f021b6ee3e1753d8b32186b7a7ac3
```

The `.img.xz` archive was checked with `xz -t` on the build Pi and the copied
Windows artefact matched the same SHA256.

## Offline Image Audit

The generated root filesystem was inspected before flashing. It contains:

- hostname `raspiaudio`
- `/etc/raspiaudio/box.conf` with default mode `usb_7_1_to_8out`
- USB gadget profile `RASPIAUDIO_8xOUT_USB_DSP_7_1_48k`
- USB gadget format: 8 channels / 7.1 / 48 kHz / S32_LE
- `dtoverlay=dwc2,dr_mode=peripheral`
- `dtoverlay=hifiberry-dac8x`
- default CamillaDSP symlink:
  `/etc/camilladsp/current.yml -> usb_gadget_8ch_48k_to_8xout.yml`
- 15 CamillaDSP profiles, including 8xOUT passthrough, 8xIN+8xOUT monitor,
  active crossover, and TOSLINK profiles
- enabled services: Avahi, nginx, CamillaDSP, CamillaGUI, `raspiaudio-web`,
  and `raspiaudio-spdif`
- executable helper commands: `raspiaudio-mode`, `raspiaudio-health`,
  `raspiaudio-test-audio`, `raspiaudio-diagnostics`,
  `raspiaudio-validate-release`

## Static Checks

These checks passed on the repository sources used for the image:

```text
bash -n appliance/install_appliance.sh
bash -n appliance/release/prepare_release_image.sh
bash -n image-builder/build_image.sh
bash -n profiles/raspiaudio_8xout_usb_7_1_quickstart/install.sh
bash -n appliance/bin/raspiaudio-diagnostics
bash -n appliance/bin/raspiaudio-install-spdif-driver
bash -n appliance/bin/raspiaudio-mode
bash -n appliance/bin/raspiaudio-test-audio
python -m py_compile appliance/web/raspiaudio_web.py
python -m py_compile appliance/bin/raspiaudio-health
python -m py_compile appliance/bin/raspiaudio-validate-release
PyYAML parse of all configs/*.yml: 15 files
```

## Live Lab Hardware Proof Already Obtained

On the current lab Raspberry Pi 5 with the RASPIAUDIO 8xIN+8xOUT connected,
Linux exposes the analog card as:

```text
card sndrpihifiberry: snd_rpi_hifiberry_dac8x
```

The output side was observed active as:

```text
format: S32_LE
channels: 8
rate: 48000
```

The input side accepts:

```text
FORMAT: S24_LE S32_LE
CHANNELS: 8
RATE: 48000
```

This proves the driver/card path has 8 analog inputs and 8 analog outputs on
the lab hardware. The beginner V1 USB profile still exposes only host-to-Pi
USB audio. Exposing the 8 analog inputs back to the host as a USB recording
device is a later profile to validate separately.

The TOSLINK path on GPIO12 was also validated previously on the lab setup with
the `RASPISPDIF` ALSA card and optical loopback/capture tests.

## Not Yet Proven For This Image Candidate

The following items still require a real fresh flash of this exact `.img.xz`
image to a microSD card:

1. First boot on Raspberry Pi 5 + RASPIAUDIO 8xOUT.
2. `http://raspiaudio.local` reachable without SSH.
3. Host OS sees the USB device as a 7.1 / 8-channel / 48 kHz output.
4. Dashboard output tests pass on OUT1 to OUT8.
5. 8xIN+8xOUT output-side repeat test.
6. TOSLINK mode locks and plays for 10 minutes from the fresh image.
7. Active crossover mode is editable in CamillaGUI.
8. Selected mode persists across power cycle.
9. Beginner failure states produce useful dashboard warnings and diagnostics.

As of this validation note, no removable SD card target was visible on the
Windows host. Do not write the image to any fixed NVMe/SATA disk.

