# RASPIAUDIO 8xOUT USB 7.1 quick start

This beginner guide installs a Raspberry Pi 5 as a USB 7.1 sound card with
eight analog outputs through the RASPIAUDIO 8xOUT. It also works with the output
side of the RASPIAUDIO 8xIN+8xOUT.

Default mode:

- USB input from the computer: 7.1, 8 channels, 48 kHz, 32-bit
- CamillaDSP routing: direct passthrough, input 1 to output 1, up to input 8 to
  output 8
- Analog output: RASPIAUDIO 8xOUT
- CamillaGUI web interface: enabled on port `5005`

The installer does not ask the user to type the Linux ALSA card name. It detects
the RASPIAUDIO playback device automatically and writes the correct CamillaDSP
configuration.

## What you need

- Raspberry Pi 5
- RASPIAUDIO 8xOUT, or RASPIAUDIO 8xIN+8xOUT
- Official Raspberry Pi 5 power supply
- microSD card, 16 GB or larger
- USB-C data cable, or this [USB-C power/data splitter](https://amzn.to/4aZwswF)
- Windows, macOS, or Linux computer
- Free Raspberry Pi Connect account: <https://connect.raspberrypi.com/>

## 1. Flash Raspberry Pi OS

1. Install Raspberry Pi Imager from:
   <https://www.raspberrypi.com/software/>
2. Insert the microSD card in the computer.
3. Open Raspberry Pi Imager.
4. Select the Raspberry Pi device: `Raspberry Pi 5`.
5. Select the OS: `Raspberry Pi OS Lite (64-bit)`.
   `Raspberry Pi OS with desktop (64-bit)` also works.
6. Select the microSD card.
7. Open OS customisation and set:
   - hostname: `raspiaudio-dsp`
   - username and password: choose your own
   - Wi-Fi: configure it if you will not use Ethernet
   - Raspberry Pi Connect: enabled and linked to your account
   - locale, keyboard, and timezone
8. Write the image.
9. Put the microSD card in the Raspberry Pi.
10. Mount the RASPIAUDIO board on the Raspberry Pi 5.
11. Power the Raspberry Pi and wait one or two minutes.

## 2. Open a Remote Shell

Open this page in a browser and sign in:

```text
https://connect.raspberrypi.com/
```

Then select your Raspberry Pi and open `Remote Shell`.

If Raspberry Pi Connect was not available in Imager, use SSH as a fallback:

```bash
ssh <your-user>@raspiaudio-dsp.local
```

## 3. Run the one-command installer

On the Raspberry Pi:

```bash
sudo apt update
sudo apt install -y git
git clone https://github.com/RASPIAUDIO/CamillaDSP.git myCamillaDSP
cd myCamillaDSP
sudo ./install_raspiaudio_usb_7_1.sh
```

At the end, accept the reboot. If you skipped it, run:

```bash
sudo reboot
```

## 4. Connect the USB audio cable

After reboot:

1. Connect the Raspberry Pi USB-C gadget/data path to the computer.
2. Keep the Raspberry Pi powered correctly. If you use a splitter, make sure one
   side powers the Pi and the other side carries USB data.
3. On the computer, select the USB audio device named like
   `RASPIAUDIO_8xOUT_USB_DSP_7_1_48k`.
4. Configure it as a 7.1 speaker device in the operating system audio settings.

## 5. Open CamillaGUI

Open this page in a browser:

```text
http://raspiaudio-dsp.local:5005/gui/index.html
```

If that does not work, use the Raspberry Pi IP address:

```text
http://<raspberry-pi-ip>:5005/gui/index.html
```

The default file is:

```text
/etc/camilladsp/raspiaudio_usb_7_1_48k_passthrough.yml
```

The default mixer is a direct passthrough:

| USB channel | Usual 7.1 label | RASPIAUDIO output |
|---:|---|---:|
| 1 | Front left | OUT1 |
| 2 | Front right | OUT2 |
| 3 | Center | OUT3 |
| 4 | LFE / sub | OUT4 |
| 5 | Back left | OUT5 |
| 6 | Back right | OUT6 |
| 7 | Side left | OUT7 |
| 8 | Side right | OUT8 |

## 6. Verify

Start audio playback from the computer, then run this on the Raspberry Pi:

```bash
cd ~/myCamillaDSP
./profiles/raspiaudio_8xout_usb_7_1_quickstart/verify.sh
```

Expected result while audio is playing:

```text
format: S32_LE
channels: 8
rate: 48000
```

The USB gadget should report `configured` and `high-speed`.

## Troubleshooting

If the computer does not show the USB sound card:

```bash
./profiles/raspiaudio_8xout_usb_7_1_quickstart/verify.sh
```

Check the USB gadget section. If it says `not attached`, the cable or splitter
is not presenting a USB host data connection to the Raspberry Pi.

If CamillaGUI meters move but there is no sound:

```bash
sudo systemctl restart camilladsp.service
```

Then play audio again. This is useful when the USB cable was connected after
CamillaDSP had already started.

If the RASPIAUDIO board is not detected:

```bash
aplay -l
```

You should see a non-HDMI playback card for the RASPIAUDIO board. If you do not,
power off, reseat the HAT, boot again, and run the installer once more.

Do not use the 96 kHz mode for the beginner setup. The safe default is
48 kHz / 7.1 / 8 outputs.

## What the installer changes

- Installs CamillaDSP to `/usr/local/bin/camilladsp`
- Installs CamillaGUI backend to `/opt/camillagui-backend`
- Writes CamillaDSP config to `/etc/camilladsp/`
- Enables `camilladsp.service`
- Enables `camillagui.service`
- Enables Raspberry Pi USB device mode with `dwc2`
- Enables the Linux USB audio gadget with `g_audio`
- Creates backups under `/root/raspiaudio-camilladsp-backups/`

## Useful links

- Raspberry Pi OS installation: <https://www.raspberrypi.com/documentation/computers/getting-started.html>
- Raspberry Pi Imager download: <https://www.raspberrypi.com/software/>
- Raspberry Pi Connect: <https://connect.raspberrypi.com/>
- CamillaDSP: <https://github.com/HEnquist/camilladsp>
