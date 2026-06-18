# Raspberry Pi 5 USB Audio Gadget, 2 channels

This note documents the current RASPIAUDIO Raspberry Pi 5 lab setup where the Pi enumerates as a USB Audio Class 2 sound card to a host computer, then routes host playback through CamillaDSP.

Current validated target:

- Board: Raspberry Pi 5 Model B
- OS: Debian Bookworm / Raspberry Pi kernel `6.12.47+rpt-rpi-2712`
- USB role: device/peripheral on the Pi 5 USB-C port
- Host-facing USB profile: UAC2 stereo playback endpoint
- Gadget-side ALSA device: `hw:CARD=UAC2Gadget,DEV=0` capture
- DSP: CamillaDSP `4.1.3`
- DSP output in this lab: RASPIAUDIO 8xOUT / 8xIN+8xOUT via `hw:CARD=XMOSDevice,DEV=0`
- Audio format: `48000 Hz`, `S32_LE`, `2 channels`

Important vocabulary: in Linux USB gadget audio, the host's playback stream appears on the Pi as an ALSA capture device. That is expected.

## Physical wiring

Use the Raspberry Pi 5 USB-C port as the USB device port. The host computer must see the USB data lines and CC orientation correctly.

A splitter is only valid if it passes USB data between the host and the Pi. Many USB-C power splitters only pass power, or put the Pi behind a charging-only path.

Check the low-level attachment state on the Pi:

```bash
cat /sys/class/udc/1000480000.usb/state
```

Expected once connected to a host: not `not attached`.

Observed failure on the lab bench on 2026-06-17:

```text
state=not attached
```

That means the Pi-side gadget is ready, but the USB-C data connection to the host is not present. In that state Windows will not show the sound card, and CamillaDSP will log that capture is stalled.

## Boot config

Edit `/boot/firmware/config.txt`.

On Raspberry Pi 5 Model B, the `dwc2` overlay must be under `[all]`, not under `[cm5]`.

```ini
[all]
dtoverlay=dwc2,dr_mode=peripheral
```

If present, disable host-only OTG mode:

```ini
#otg_mode=1
```

For the current lab output path, the RASPIAUDIO 8-output driver overlay is also active:

```ini
dtoverlay=xmos-device
```

If you use another output card, keep the USB gadget lines the same and change only the CamillaDSP playback device.

## Kernel modules

Use a minimal module list for the gadget test.

`/etc/modules`:

```text
i2c-dev
dwc2
g_audio
```

The same content was also written to `/etc/modules-load.d/modules.conf` on the lab Pi, because that file was already present and had previously disabled the gadget modules.

Do not load unrelated audio modules such as `snd-soc-wm8960` unless that is actually the target output hardware.

## USB audio profile

Create `/etc/modprobe.d/usb_g_audio.conf`:

```text
# Gadget-side ALSA capture = host-side speaker/playback endpoint.
# c_chmask=3: stereo L/R. c_ssize=4: S32_LE. c_srate=48000: fixed 48 kHz.
# p_chmask=0: no microphone endpoint from Pi back to the host for this first 2-channel test.
# idVendor/idProduct use Linux gadget defaults for lab validation only; use a real VID/PID for product.
options g_audio c_srate=48000 c_ssize=4 c_chmask=3 p_chmask=0 iManufacturer=RASPIAUDIO iProduct=RASPIAUDIO_USB_DSP_2ch iSerialNumber=RASPIAUDIO-PI5-2CH idVendor=0x1d6b idProduct=0x0101
```

This creates a two-channel host playback endpoint. On the Pi it appears as:

```text
card N: UAC2Gadget [UAC2_Gadget], device 0: UAC2 PCM [UAC2 PCM]
```

For a commercial product, do not ship with `idVendor=0x1d6b`. Use a proper VID/PID.

## CamillaDSP config

The matching config is in:

```text
configs/usb_gadget_2ch_48k_to_2ch_output.yml
```

For the RASPIAUDIO 8xOUT or 8xIN+8xOUT use case where the host sends stereo
audio and CamillaDSP expands it to eight output channels, use:

```text
configs/usb_gadget_2ch_48k_to_8xout.yml
```

See the isolated walkthrough in:

```text
docs/usb_gadget_2ch_to_8xout.md
```

Install it on the Pi:

```bash
install -o rosco -g rosco -m 0644 configs/usb_gadget_2ch_48k_to_2ch_output.yml /home/rosco/myCamillaDSP/configs/
```

The important devices are:

```yaml
capture:
  type: Alsa
  channels: 2
  device: "hw:CARD=UAC2Gadget,DEV=0"
  format: S32_LE
playback:
  type: Alsa
  channels: 2
  device: "hw:CARD=XMOSDevice,DEV=0"
  format: S32_LE
```

`XMOSDevice` is the Linux ALSA card name in this lab, not the RASPIAUDIO
product name. If your output card has a different ALSA name, list devices and
update the playback device:

```bash
aplay -l
arecord -l
cat /proc/asound/cards
```

Validate the config:

```bash
/usr/local/bin/camilladsp -c /home/rosco/myCamillaDSP/configs/usb_gadget_2ch_48k_to_2ch_output.yml
```

## systemd

The lab service uses the config above:

```ini
ExecStart=/usr/local/bin/camilladsp -l info -o /var/log/camilladsp/camilladsp.log -w -p 1234 -s /home/rosco/myCamillaDSP/statefile.yml /home/rosco/myCamillaDSP/configs/usb_gadget_2ch_48k_to_2ch_output.yml
```

Enable CamillaDSP and CamillaGUI:

```bash
systemctl enable camilladsp.service camillagui.service
```

Disable unrelated lab services that may claim audio hardware or confuse startup diagnostics:

```bash
systemctl disable --now raspiaudio-radio.service raspiaudio-radio-boot.service
```

## Reboot and verify

Reboot:

```bash
reboot
```

Verify the gadget controller:

```bash
ls -la /sys/class/udc
cat /sys/class/udc/1000480000.usb/state
```

Verify modules:

```bash
lsmod | grep -E 'dwc2|g_audio|u_audio|usb_f_uac|libcomposite'
```

Verify ALSA:

```bash
cat /proc/asound/cards
arecord -l
aplay -l
```

Expected Pi-side result with the current lab card:

```text
card 2: UAC2Gadget [UAC2_Gadget]
card 3: XMOSDevice [XMOSDevice]
```

Expected CamillaDSP status:

```bash
systemctl status camilladsp.service
tail -n 100 /var/log/camilladsp/camilladsp.log
```

`Capture device is stalled` is normal when no host computer is sending audio.

## Windows verification

On Windows, after connecting a real USB data path to the Pi USB-C port:

```powershell
Get-PnpDevice -PresentOnly |
  Where-Object { $_.InstanceId -match 'VID_1D6B|RASPIAUDIO|UAC|Gadget|USB Audio' } |
  Select-Object Class,FriendlyName,InstanceId,Status
```

If nothing appears and the Pi still says `state=not attached`, the problem is the cable/splitter/port, not CamillaDSP.

## Descriptor isolation test

If the Pi-side UAC2 card exists but the host still sees nothing, temporarily test a different gadget class. This separates a USB attachment problem from a Windows audio descriptor problem.

```bash
sudo systemctl stop camilladsp.service
sudo modprobe -r g_audio usb_f_uac2 u_audio
sudo modprobe g_ether
cat /sys/class/udc/1000480000.usb/state
cat /sys/class/udc/1000480000.usb/function
sudo modprobe -r g_ether usb_f_rndis usb_f_ecm u_ether
sudo modprobe g_audio
sudo systemctl start camilladsp.service
```

Lab result on 2026-06-17:

```text
before_audio UDC=1000480000.usb state=not attached speed=UNKNOWN function=g_audio
during_gether UDC=1000480000.usb state=not attached speed=UNKNOWN function=g_ether
after_audio_restore UDC=1000480000.usb state=not attached speed=UNKNOWN function=g_audio
```

Because both audio and Ethernet gadgets stayed `not attached`, the current failure is below the USB class descriptor layer. It points to no real host data/VBUS/CC path on the USB-C connection.

## Beep test

Once Windows sees the USB audio device, send a short 48 kHz sine wave to the matching output device. With Python `sounddevice` installed:

```powershell
python - <<'PY'
import numpy as np
import sounddevice as sd

for i, d in enumerate(sd.query_devices()):
    print(i, d["name"], "out", d["max_output_channels"])

# Replace DEVICE_INDEX with the RASPIAUDIO / USB audio output index.
device = DEVICE_INDEX
fs = 48000
t = np.arange(int(fs * 0.5)) / fs
audio = 0.2 * np.sin(2 * np.pi * 1000 * t)
stereo = np.column_stack([audio, audio]).astype(np.float32)
sd.play(stereo, fs, device=device)
sd.wait()
PY
```

On the Pi, CamillaDSP should leave the stalled state while the host sends audio. If the output hardware is connected, the 1 kHz beep should be audible on the selected output path.

## Current lab state, 2026-06-17

Applied on `rosco@192.168.1.154`:

- Backup: `/root/codex-backups/usb-gadget-clean-20260617-153807`
- USB gadget boot overlay restored under `[all]`
- `dwc2` and `g_audio` restored in module load config
- WM8960 module autoload removed from the minimal gadget profile
- `raspiaudio-radio.service` and `raspiaudio-radio-boot.service` disabled
- CamillaDSP config switched to `usb_gadget_2ch_48k_to_2ch_output.yml`
- CamillaDSP and CamillaGUI enabled

Validated on the Pi:

```text
/sys/class/udc/1000480000.usb exists
UAC2Gadget appears in arecord -l
XMOSDevice appears in aplay -l
camilladsp.service is active
```

Not validated yet:

```text
Windows host enumeration
```

Reason:

```text
/sys/class/udc/1000480000.usb/state = not attached
```

That points to the USB-C splitter/cable path rather than the Raspberry Pi audio configuration.
