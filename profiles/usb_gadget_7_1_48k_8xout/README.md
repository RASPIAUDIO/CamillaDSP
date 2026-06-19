# RASPIAUDIO USB gadget 7.1 48 kHz to 8xOUT

This isolated profile makes a Raspberry Pi 5 enumerate as a USB Audio Class 2
7.1 playback device. The host sends 8 channels over USB-C, CamillaDSP captures
them from `UAC2Gadget`, then outputs them one-to-one to the RASPIAUDIO 8xOUT or
the output side of the RASPIAUDIO 8xIN+8xOUT.

The older stereo profile stays available in:

```text
configs/usb_gadget_2ch_48k_to_8xout.yml
docs/usb_gadget_2ch_to_8xout.md
```

## Files

```text
camilladsp_usb_7_1_48k_to_8xout.yml  CamillaDSP 7.1 to 8-output profile
install_on_pi.sh                      Enable the 7.1 gadget and install current.yml
verify_on_pi.sh                       Check USB speed, ALSA streams, and CamillaDSP
generate_7_1_test_wav.py              Generate a true 7.1 channel-identification WAV
bandwidth_48k_96k.md                  USB bandwidth calculation for 48/96 kHz
```

## Channel order

The gadget uses channel mask `0x63f`, the standard 7.1 home-theater layout:

| USB channel | Host label | CamillaDSP input | RASPIAUDIO output |
|---:|---|---:|---:|
| 0 | FL | 0 | OUT1 |
| 1 | FR | 1 | OUT2 |
| 2 | FC | 2 | OUT3 |
| 3 | LFE | 3 | OUT4 |
| 4 | BL | 4 | OUT5 |
| 5 | BR | 5 | OUT6 |
| 6 | SL | 6 | OUT7 |
| 7 | SR | 7 | OUT8 |

The ALSA card name `sndrpihifiberry` is the current Linux device name for the
RASPIAUDIO output path on the lab Pi. It is not the product name.

## Install on the Raspberry Pi

From this repository on the Pi:

```bash
cd /home/rosco/myCamillaDSP
sudo ./profiles/usb_gadget_7_1_48k_8xout/install_on_pi.sh
sudo reboot
```

The script:

- enables `dwc2` peripheral mode in `/boot/firmware/config.txt`
- loads `dwc2` and `g_audio` at boot
- writes `/etc/modprobe.d/usb_g_audio.conf`
- installs the CamillaDSP YAML into `/home/rosco/myCamillaDSP/configs`
- copies it to `/home/rosco/myCamillaDSP/configs/current.yml`
- restarts/enables `camilladsp.service`
- creates a backup under `/root/codex-backups/`

The gadget options written by default are:

```text
options g_audio c_srate=48000 c_ssize=4 c_chmask=0x63f p_chmask=0 iManufacturer=RASPIAUDIO iProduct=RASPIAUDIO_USB_DSP_7_1_48k iSerialNumber=RASPIAUDIO-PI5-7_1_48k idVendor=0x1d6b idProduct=0x0108
```

After reboot, reconnect the USB-C gadget cable if the host keeps an old cached
descriptor.

## Apply or edit in CamillaGUI

Open:

```text
http://<raspberry-pi-ip>:5005/gui/index.html
```

In the GUI:

1. Open **Files** and load `current.yml`.
2. Open **Devices** and check:
   - capture device: `hw:CARD=UAC2Gadget,DEV=0`
   - capture channels: `8`
   - playback device: `hw:CARD=sndrpihifiberry,DEV=0`
   - playback channels: `8`
   - sample rate: `48000`
3. Open **Mixers** and check `usb_7_1_to_8xout`.
4. Press **Apply** after edits.
5. Save the file if the active profile must survive a restart.

The service and the GUI must point to the same `current.yml`. Otherwise GUI
edits can look correct but not affect the running DSP pipeline.

## Verify

Start playback from the USB host, then run:

```bash
cd /home/rosco/myCamillaDSP
./profiles/usb_gadget_7_1_48k_8xout/verify_on_pi.sh
```

Expected active stream:

```text
UAC2Gadget capture:
format: S32_LE
channels: 8
rate: 48000

RASPIAUDIO playback:
format: S32_LE
channels: 8
rate: 48000
```

The USB gadget should report `current_speed: high-speed`.

## Generate a local 7.1 test WAV

On Windows, macOS, Linux, or the Pi:

```bash
python3 profiles/usb_gadget_7_1_48k_8xout/generate_7_1_test_wav.py \
  surround-tests/raspiaudio_7_1_channel_id_48k.wav
```

Play the generated WAV with VLC and select the RASPIAUDIO USB audio device.
Do not use a web browser or YouTube for validation because they can downmix to
stereo before the audio reaches the USB gadget.

## 96 kHz experiment

The same install script can generate an experimental 96 kHz profile:

```bash
cd /home/rosco/myCamillaDSP
sudo SAMPLE_RATE=96000 PRODUCT_ID=0x0196 PRODUCT_SUFFIX=7_1_96k \
  ./profiles/usb_gadget_7_1_48k_8xout/install_on_pi.sh
sudo reboot
```

Then verify while the host plays a 96 kHz 7.1 stream:

```bash
EXPECTED_RATE=96000 ./profiles/usb_gadget_7_1_48k_8xout/verify_on_pi.sh
```

The bandwidth math is in `bandwidth_48k_96k.md`. In theory, 7.1 / 96 kHz /
`S32_LE` is comfortably within USB 2.0 high-speed capacity; the real validation
is whether the host descriptor, ALSA devices, and CamillaDSP stay stable.
