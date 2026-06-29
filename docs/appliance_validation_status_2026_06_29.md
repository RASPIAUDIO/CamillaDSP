# RASPIAUDIO CamillaDSP Box Validation Status - 2026-06-29

This page records the first Windows-flashed appliance-image test reported from
the beginner workflow.

## Image Candidate

```text
raspiaudio-dspbox-pi5-2026.06.28.img.xz
size: 353609480
sha256: 7242131e7f8e31705babdb128deca0542147817103698c5186978e5dad1b01f6
```

The image was flashed from Windows with Raspberry Pi Imager using `Use custom`
and booted on Raspberry Pi 5.

Flash tutorial video:

```text
docs/assets/raspberry-pi-imager-custom-image-windows.mp4
```

## Fresh Flash Proof

Observed on first boot:

- `http://raspiaudio.local/` is reachable.
- fallback dashboard IP is `http://192.168.1.153/`.
- hardware mode is detected as `8xin8xout`.
- active mode is `usb_7_1_to_8out`.
- active CamillaDSP profile is
  `/etc/camilladsp/usb_gadget_8ch_48k_to_8xout.yml`.
- CamillaDSP, CamillaGUI, nginx, Avahi, and `raspiaudio-web` are active.
- USB gadget profile is 8 channels / 7.1 / 48 kHz / S32_LE.
- `UAC2Gadget` is visible locally to CamillaDSP.
- RASPIAUDIO analog output card is visible.
- RASPIAUDIO analog input card is visible.

## Issues Found

Dashboard output test / direct hardware test:

```text
Playback device is hw:CARD=sndrpihifiberry,DEV=0
Stream parameters are 48000Hz, S32_LE, 8 channels
Playback open error: -16,Device or resource busy
```

Cause: CamillaDSP already owns the ALSA output device. The appliance test
helper must temporarily stop CamillaDSP, run `speaker-test`, then restart
CamillaDSP.

USB-C data side:

```text
USB gadget controller is not configured by a host (1000480000.usb=not attached).
```

Windows did not show a present RASPIAUDIO/UAC2 audio endpoint during this check.
The dashboard is online over the network, but the USB host link still needs
cable/splitter/host-side validation.

TOSLINK:

```text
raspiaudio-spdif.service is inactive.
RASPISPDIF card is not visible.
```

The first-boot driver path needs a repair/retry action from the dashboard
because a release image should not require SSH for this fix.

Diagnostics API:

The diagnostics script generated a valid zip when called by the validator, but
the web API failed when it passed a pre-created temporary file path. The script
must remove that empty file before creating the zip.

## Fixes Added After This Test

- `raspiaudio-test-audio` now stops and restarts CamillaDSP around direct ALSA
  hardware tests.
- `raspiaudio-test-audio toslink` now attempts to build/load the GPIO12
  `RASPISPDIF` driver if the card is missing.
- `raspiaudio-diagnostics` now removes the pre-created output file before
  writing the zip.
- `raspiaudio-restart-usb-gadget` was added.
- The dashboard now has a `Restart USB gadget` action.
- `raspiaudio-validate-release` now checks the USB-C host link state.

## Next Validation Needed

Build a new image with the fixes above, flash it again, then confirm:

1. Dashboard `OUT1` to `OUT8` tests pass without `Device or resource busy`.
2. Diagnostics zip downloads from the web UI.
3. Windows sees the USB gadget as a present 7.1 / 8-channel / 48 kHz audio
   output device.
4. `Restart USB gadget` clears a stale `not attached` USB state, or the UI
   message correctly tells the user to replug/reboot.
5. TOSLINK card appears as `RASPISPDIF` or `Test TOSLINK` repairs it.
6. Release checks pass, aside from any explicitly accepted missing external
   optical receiver test.
