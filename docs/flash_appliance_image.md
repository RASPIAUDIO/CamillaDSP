# Flash The RASPIAUDIO CamillaDSP Box Image

This is the simplest setup path for non-Linux users.

Public download page:

```text
https://raspiaudio.com/camilladsp-box
```

You flash one ready-made image, boot the Raspberry Pi, then use the web page:

```text
http://raspiaudio.local
```

## What You Need

- Raspberry Pi 5.
- RASPIAUDIO 8xOUT or 8xIN+8xOUT board.
- microSD card, 16 GB or larger.
- USB-C power/data splitter.
- Windows, macOS, or Linux computer.
- Raspberry Pi Imager.
- The RASPIAUDIO CamillaDSP Box `.img.xz` image file.

## Flash The microSD Card

1. Install Raspberry Pi Imager:
   [https://www.raspberrypi.com/software/](https://www.raspberrypi.com/software/)
2. Insert the microSD card in your computer.
3. Open Raspberry Pi Imager.
4. Click `Choose Device` and select `Raspberry Pi 5`.
5. Click `Choose OS`.
6. Scroll to the bottom and select `Use custom`.
7. Select the downloaded RASPIAUDIO `.img.xz` file.
8. Click `Choose Storage` and select the microSD card.
9. Click `Next`, then `Write`.
10. When Imager finishes, eject the microSD card safely.

The Windows flashing flow is shown in this video:
[Raspberry Pi Imager custom image on Windows](assets/raspberry-pi-imager-custom-image-windows.mp4)

## First Boot

1. Put the microSD card in the Raspberry Pi 5.
2. Mount the RASPIAUDIO board on the GPIO header.
3. Connect power through the power side of the USB-C splitter.
4. Connect the data side of the USB-C splitter to the computer.
5. Wait about one minute for the first boot.
6. Open:

   ```text
   http://raspiaudio.local
   ```

If that does not open, find the Raspberry Pi IP address in your router and open
that address instead, for example:

```text
http://192.168.1.155
```

## First Audio Test

1. In the dashboard, choose `PC USB 7.1 to 8 analog outputs`.
2. On the computer, select the USB sound card named like:

   ```text
   RASPIAUDIO_USB_DSP_7_1_48k
   ```

3. Set the computer output format to `7.1`, `8 channels`, `48 kHz`.
4. Use the dashboard output test buttons to test OUT1 to OUT8.
5. Keep amplifier volume low for the first test.

## Other Modes

After the first test works, the dashboard can also enable:

- `PC USB front L/R to optical TOSLINK stereo`.
- `Stereo active crossover to 8 outputs`.
- `8 analog inputs monitor/test` on 8xIN+8xOUT boards.

Use the `Advanced CamillaDSP editor` button only when you want to edit filters,
mixers, gains, delays, PEQ, FIR, or crossover settings.

## If You Need Support

Open the dashboard and click:

```text
Download diagnostics zip
```

Send that zip with your support message. It contains the audio device list,
dashboard health checks, CamillaDSP logs, and the selected mode.
