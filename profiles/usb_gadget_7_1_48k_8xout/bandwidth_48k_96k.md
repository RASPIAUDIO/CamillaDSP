# USB bandwidth for 7.1 gadget audio

This profile uses the Raspberry Pi USB-C port as a USB Audio Class 2 device.
The host sends audio to the Pi, and Linux exposes that host-to-Pi stream as
`UAC2Gadget` ALSA capture.

The lab profile is:

- channels: 8
- sample format: `S32_LE`
- bytes per sample: 4
- direction: host to Pi only
- USB speed observed on the Pi: high-speed

## Raw PCM payload

Formula:

```text
sample_rate * channels * bits_per_sample
```

For 48 kHz:

```text
48000 * 8 * 32 = 12,288,000 bit/s
12,288,000 / 8 = 1,536,000 byte/s
```

For 96 kHz:

```text
96000 * 8 * 32 = 24,576,000 bit/s
24,576,000 / 8 = 3,072,000 byte/s
```

If a future profile also exposes an 8-channel Pi-to-host microphone endpoint,
double those raw payload numbers:

```text
48 kHz full duplex 8 in + 8 out: 24.576 Mbit/s
96 kHz full duplex 8 in + 8 out: 49.152 Mbit/s
```

## USB high-speed check

USB 2.0 high-speed has a 480 Mbit/s line rate. Isochronous payload capacity is
lower than that after protocol overhead, but this profile is still far below the
limit.

At 96 kHz, high-speed USB uses 8000 microframes per second:

```text
96000 / 8000 = 12 samples per microframe
12 samples * 8 channels * 4 bytes = 384 bytes per microframe
```

That is comfortably below the high-speed isochronous packet size used by this
class of audio gadget. In theory, 7.1 / 96 kHz / S32_LE host-to-Pi should pass
over the Raspberry Pi 5 USB-C gadget link.

The important practical checks are not raw USB bandwidth. They are:

- the Pi must enumerate at `high-speed`, not full-speed
- Windows/macOS/Linux must accept the new 96 kHz descriptor
- ALSA must open `UAC2Gadget` capture at 8 channels / 96 kHz / `S32_LE`
- the RASPIAUDIO output side must open playback at 8 channels / 96 kHz / `S32_LE`
- CamillaDSP must keep a stable buffer level without underruns

Full-speed USB is not enough for this profile. Even 7.1 / 48 kHz / S32_LE has a
raw payload of 12.288 Mbit/s before USB overhead, which already exceeds the
usable payload of a 12 Mbit/s full-speed link.
