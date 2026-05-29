# RASPIAUDIO 8xIN + 8xOUT Board

Inventory observed on the Raspberry Pi 5 on 2026-05-27.

## System

```text
Architecture : aarch64
Distribution : Debian GNU/Linux 13 trixie
Kernel       : 6.12.75+rpt-rpi-2712
```

## ALSA Cards

```text
0 [vc4hdmi0       ]: vc4-hdmi - vc4-hdmi-0
1 [vc4hdmi1       ]: vc4-hdmi - vc4-hdmi-1
2 [sndrpihifiberry]: RPi-simple - snd_rpi_hifiberry_dac8x
```

The RASPIAUDIO board appears as:

```text
sndrpihifiberry
```

The device to use with CamillaDSP is:

```text
hw:CARD=sndrpihifiberry,DEV=0
```

## PCM

```text
02-00: HiFiBerry DAC8xADC8x HiFi snd-soc-dummy-dai-0 : playback 1 : capture 1
```

## ALSA Capabilities Observed With `arecord --dump-hw-params`

```text
FORMAT: S16_LE S24_LE S32_LE
CHANNELS: [2 8]
RATE: [8000 192000]
```

## Capabilities Observed by CamillaDSP

CamillaDSP 4.1.3 opens the device correctly in duplex mode with:

```text
48000 Hz, 8 channels, S32_LE
```

In the CamillaDSP log, capture reports several discrete rates, but playback
reports only `48000`. The documented configuration is therefore intentionally
fixed at 48000 Hz.

## Active Audio Services

```text
pipewire.service
pipewire-pulse.service
wireplumber.service
```

The CamillaDSP configurations use the direct ALSA `hw:...` device in order to
bypass software mixing during tests.
