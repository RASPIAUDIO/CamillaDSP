# YouTube Shorts And Reddit Copy

These drafts are intentionally technical and community-first. They point to the
open CamillaDSP/RASPIAUDIO work without sounding like a product ad.

## YouTube Short 1

Video:
[https://youtube.com/shorts/jtMrTWnFblk](https://youtube.com/shorts/jtMrTWnFblk)

Title:

```text
Raspberry Pi 5 S/PDIF audio from a GPIO LED
```

Description:

```text
A Raspberry Pi 5 generating optical S/PDIF audio from GPIO12 using RP1 PIO + DMA.

For the first test I used a simple LED placed close to a TOSLINK receiver. Linux sees the output as an ALSA sound card, so CamillaDSP can route audio to it like a normal device.

Project / code:
https://github.com/RASPIAUDIO/CamillaDSP

More:
https://raspiaudio.com/

#RaspberryPi #CamillaDSP #SPDIF #TOSLINK #LinuxAudio #DIYAudio
```

## Instagram Reel For Video 1

Text on screen:

```text
Raspberry Pi 5
S/PDIF optical audio
from a simple GPIO LED
```

Caption:

```text
Yes, this is audio over light from a Raspberry Pi 5 GPIO.

The Raspberry Pi 5 has an RP1 I/O chip with PIO. We use it as a tiny hardware bitstream engine: Linux audio goes to an ALSA driver, the driver encodes S/PDIF, DMA feeds the RP1 PIO, and GPIO12 outputs the optical signal fast enough for a TOSLINK receiver.

So this is not just blinking an LED. It is a real S/PDIF audio stream generated from a Raspberry Pi 5 GPIO, and Linux sees it as a normal sound card.

That means CamillaDSP can route audio to it for filters, crossovers, experiments and optical output.

Project:
https://github.com/RASPIAUDIO/CamillaDSP

#raspberrypi #raspberrypi5 #camilladsp #spdif #toslink #linuxaudio #diyaudio #audioproject #opensourcehardware #raspiaudio
```

Short caption:

```text
Raspberry Pi 5 optical S/PDIF from a GPIO LED.

The Pi 5 RP1 PIO works as a small hardware bitstream engine: ALSA audio -> S/PDIF encoder -> DMA -> RP1 PIO -> GPIO12 -> TOSLINK receiver.

So the LED is carrying a real optical audio stream, not just blinking.

Project: github.com/RASPIAUDIO/CamillaDSP

#raspberrypi #camilladsp #spdif #toslink #diyaudio #linuxaudio
```

Technical note:

```text
On Raspberry Pi 5, GPIO timing goes through the RP1 I/O chip. RP1 has PIO blocks, which are small programmable hardware engines. For this S/PDIF output, the Linux driver encodes normal PCM audio into S/PDIF, DMA keeps the data flowing, and the RP1 PIO state machine outputs the 6.144 MHz 48 kHz stereo S/PDIF half-bit stream on GPIO12.

That is why it can appear as a normal ALSA sound card while still producing timing-accurate optical audio.
```

## YouTube Short 2

Video:
[https://youtube.com/shorts/2ND7hcqHV5Q](https://youtube.com/shorts/2ND7hcqHV5Q)

Title:

```text
PC USB audio into Raspberry Pi 5 CamillaDSP, then 8 outputs
```

Description:

```text
The Raspberry Pi 5 is seen by the PC as a USB sound card, using USB gadget mode and a USB-C power/data splitter.

Audio comes from the computer into the Pi, CamillaDSP processes it, then it can go to 8 analog outputs or optical TOSLINK. Useful for DIY active crossovers, home cinema experiments, FIR filters, PEQ, delays and routing.

Project / code / install guide:
https://github.com/RASPIAUDIO/CamillaDSP

RASPIAUDIO:
https://raspiaudio.com/

#RaspberryPi #CamillaDSP #USBAudio #DIYAudio #ActiveCrossover #HomeCinema
```

## Reddit Post For Video 2

Title:

```text
Raspberry Pi 5 as a USB sound card into CamillaDSP, then 8 analog outputs / TOSLINK
```

Text:

```text
I have been experimenting with a Raspberry Pi 5 as a small open DSP box.

The PC sees the Pi as a USB audio device using USB gadget mode. With a USB-C power/data splitter, the Pi can be powered normally while also receiving USB audio from the computer.

The audio path is:

PC USB audio -> Raspberry Pi 5 -> CamillaDSP -> 8 analog outputs and/or optical TOSLINK

The goal is active crossover / home cinema / speaker DSP use: routing, PEQ, FIR, delays, gain, and output testing from a simple web interface.

Short demo:
https://youtube.com/shorts/2ND7hcqHV5Q

Project / install notes:
https://github.com/RASPIAUDIO/CamillaDSP

More info:
https://raspiaudio.com/

Still experimental, but the basic USB gadget + CamillaDSP + multichannel output path is working.
```
