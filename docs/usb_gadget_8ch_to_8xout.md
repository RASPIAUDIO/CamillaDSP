# USB 8ch input to RASPIAUDIO 8xOUT with CamillaDSP

This profile makes the Raspberry Pi 5 enumerate as an 8-channel USB Audio Class
2 playback device to the host computer. The host sends 8 channels over USB-C to
the Pi, CamillaDSP receives them as an 8-channel ALSA capture stream, then sends
them one-to-one to the RASPIAUDIO 8xOUT / 8xIN+8xOUT output path.

This is the multichannel version of `docs/usb_gadget_2ch_to_8xout.md`.

Validated target shape:

- Raspberry Pi 5 USB-C in device/peripheral mode
- USB gadget function: `g_audio`
- Host-facing USB profile: UAC2 7.1 / 8-channel playback endpoint
- Pi-side ALSA capture: `hw:CARD=UAC2Gadget,DEV=0`, 8 channels
- Pi-side ALSA playback: `hw:CARD=sndrpihifiberry,DEV=0`, 8 channels
- Output hardware: RASPIAUDIO 8xOUT or RASPIAUDIO 8xIN+8xOUT output side
- Audio format: `48000 Hz`, `S32_LE`
- CamillaDSP profile: `configs/usb_gadget_8ch_48k_to_8xout.yml`

`sndrpihifiberry` is the Linux ALSA card name used by the current driver path on the
lab Raspberry Pi. It is not the product name.

## Signal path

```text
Windows / macOS / Linux host
  USB audio 7.1 / 8-channel playback
    -> Raspberry Pi 5 USB-C gadget
    -> ALSA capture: UAC2Gadget, 8 channels
    -> CamillaDSP
    -> ALSA playback: sndrpihifiberry, 8 channels
    -> RASPIAUDIO 8xOUT / 8xIN+8xOUT outputs
```

In Linux USB gadget vocabulary, `c_*` options configure the host-to-Pi stream.
That stream appears on the Pi as an ALSA capture device. This is why the USB
"input" profile below uses `c_chmask`, not `p_chmask`.

## USB channel mask

Use the standard 7.1 home-theater channel mask:

```text
c_chmask=0x63f
```

This exposes 8 host-to-Pi channels in this order:

| USB channel | Host label | CamillaDSP input | Physical output |
|---:|---|---:|---:|
| 0 | FL | 0 | 1 |
| 1 | FR | 1 | 2 |
| 2 | FC | 2 | 3 |
| 3 | LFE | 3 | 4 |
| 4 | BL | 4 | 5 |
| 5 | BR | 5 | 6 |
| 6 | SL | 6 | 7 |
| 7 | SR | 7 | 8 |

`0xff` also contains 8 bits, but on Windows it means 7.1 wide
`FL, FR, FC, LFE, BL, BR, FLC, FRC`. For a generic 8-output DSP, `0x63f` is the
safer default because Windows treats it as normal 7.1.

## Enable the 8-channel USB gadget

Edit `/etc/modprobe.d/usb_g_audio.conf`:

```text
# Gadget-side ALSA capture = host-side speaker/playback endpoint.
# c_chmask=0x63f: 8-channel 7.1 host-to-Pi stream.
# c_ssize=4: S32_LE. c_srate=48000: fixed 48 kHz.
# p_chmask=0: no Pi-to-host microphone endpoint in this profile.
# idVendor/idProduct use Linux gadget defaults for lab validation only; use a real VID/PID for product.
options g_audio c_srate=48000 c_ssize=4 c_chmask=0x63f p_chmask=0 iManufacturer=RASPIAUDIO iProduct=RASPIAUDIO_USB_DSP_8ch iSerialNumber=RASPIAUDIO-PI5-8CH idVendor=0x1d6b idProduct=0x0108
```

Using a different lab `idProduct` from the 2-channel profile helps Windows avoid
reusing a cached 2-channel descriptor.

Reboot after changing `g_audio` options:

```bash
sudo reboot
```

## Install the CamillaDSP profile

From the repository on the Pi:

```bash
cd /home/rosco/myCamillaDSP
install -m 0644 configs/usb_gadget_8ch_48k_to_8xout.yml \
  /home/rosco/myCamillaDSP/configs/
```

Validate the YAML:

```bash
/usr/local/bin/camilladsp --check \
  /home/rosco/myCamillaDSP/configs/usb_gadget_8ch_48k_to_8xout.yml
```

Use it as the active GUI/service profile:

```bash
cp /home/rosco/myCamillaDSP/configs/usb_gadget_8ch_48k_to_8xout.yml \
  /home/rosco/myCamillaDSP/configs/current.yml
sudo systemctl restart camilladsp.service
```

In CamillaGUI:

1. Open **Files** and load `current.yml`.
2. Open **Devices** and check:
   - capture: `hw:CARD=UAC2Gadget,DEV=0`
   - capture channels: `8`
   - playback: `hw:CARD=sndrpihifiberry,DEV=0`
   - playback channels: `8`
3. Open **Mixers** and check `usb_8ch_to_8xout`.
4. Press **Apply** and then **Save**.

## Verify

On the Pi:

```bash
cat /sys/class/udc/1000480000.usb/state
cat /sys/class/udc/1000480000.usb/function
arecord -l
aplay -l
cat /proc/asound/card*/pcm*/sub*/hw_params 2>/dev/null
```

When the host is playing an 8-channel stream, expected active parameters are:

```text
UAC2Gadget capture:
format: S32_LE
channels: 8
rate: 48000

RASPIAUDIO 8-output playback:
format: S32_LE
channels: 8
rate: 48000
```

On Windows, open the sound device properties and configure it as 7.1 if Windows
does not do it automatically. The device should appear as a speaker/playback
endpoint, not as a microphone endpoint.

## Notes

At `48000 Hz`, `S32_LE`, 8 channels, the raw audio payload is about
`48,000 * 32 * 8 = 12.288 Mbit/s`, before USB overhead. That is comfortably
within USB 2.0 high-speed capacity.

For a crossover, this profile is only the transport and 1:1 routing base.
Replace the mixer/pipeline with PEQ, crossover filters, gains, delays, phase
inversion, and limiter stages as needed.
