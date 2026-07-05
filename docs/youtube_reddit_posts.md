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
