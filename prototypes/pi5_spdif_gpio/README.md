# Raspberry Pi 5 GPIO S/PDIF OUT

This folder contains an optional Raspberry Pi 5 S/PDIF output for lab testing.
It does not replace CamillaDSP, the USB audio gadget, or the RASPIAUDIO 8xOUT
profiles.

Recommended path: use the included ALSA kernel module. It creates a normal
ALSA playback card named `RASPISPDIF`, then sends a 48 kHz stereo S/PDIF stream
on GPIO12 through RP1 PIO.

Current status: validated on one RASPIAUDIO lab Raspberry Pi 5 with 48 kHz
stereo WAV playback after the underrun fix. Treat the raw GPIO output as a
prototype until the final coax/TOSLINK output stage, receiver lock, and jitter
are measured.

## What it does

```text
ALSA app / aplay
    -> RASPISPDIF ALSA card
    -> kernel S/PDIF encoder
    -> RP1 PIO + DMA
    -> GPIO12
    -> TOSLINK or coax output stage
    -> S/PDIF receiver / DAC
```

V1 is intentionally simple:

- Raspberry Pi 5 only.
- 48 kHz only.
- Stereo only.
- ALSA formats: `S16_LE` and `S32_LE`.
- ALSA device: `hw:CARD=RASPISPDIF,DEV=0`.
- Default output pin: GPIO12, physical pin 32.
- Do not use GPIO18-GPIO27 on RASPIAUDIO 8xOUT / 8xIN+8xOUT setups. Those pins
  are used by the Pi 5 I2S overlay.

## How it works

The kernel driver receives normal stereo PCM from ALSA. For each 20 ms audio
period it:

1. Converts left/right PCM samples into S/PDIF subframes.
2. Adds S/PDIF preambles, channel status, and parity.
3. Encodes the stream as BMC bits.
4. Queues the packed bits to RP1 PIO by DMA.

The PIO program is deliberately tiny: it outputs one bit per clock tick. At
48 kHz stereo, the S/PDIF half-bit stream is 6.144 MHz.

The important part is continuity. The driver keeps several DMA periods queued.
If ALSA has not provided the next period yet but existing DMA data is still in
flight, the feeder waits briefly instead of injecting silence. This avoids the
audible chopped sound that earlier tests produced.

## Install

Run this on the Raspberry Pi 5:

```bash
sudo apt update
sudo apt install -y raspberrypi-kernel-headers build-essential alsa-utils ffmpeg

git clone https://github.com/RASPIAUDIO/CamillaDSP.git
cd CamillaDSP/prototypes/pi5_spdif_gpio
chmod +x scripts/*.sh

./scripts/install_kernel_spdif_on_pi5.sh
```

If you already cloned the repo, just run the last four lines from your existing
checkout.

Check that the ALSA card exists:

```bash
aplay -l | grep -A2 RASPISPDIF
```

Expected result:

```text
card X: RASPISPDIF [RASPIAUDIO S/PDIF PIO], device 0: RASPISPDIF PCM
```

## Load at boot

The install script builds, installs, and loads the module immediately. To also
load it automatically after reboot:

```bash
echo raspiaudio_spdif_pio | sudo tee /etc/modules-load.d/raspiaudio-spdif-pio.conf

echo "options raspiaudio_spdif_pio gpio=12 drive_ma=8 zero_on_underrun=1" | \
  sudo tee /etc/modprobe.d/raspiaudio-spdif-pio.conf
```

Reboot and verify again:

```bash
sudo reboot
aplay -l | grep -A2 RASPISPDIF
```

## Play a WAV file

The current driver is fixed at 48 kHz stereo. Convert any WAV first:

```bash
ffmpeg -y -i /path/to/input.wav \
  -ac 2 -ar 48000 -sample_fmt s16 \
  /tmp/spdif_48k.wav

aplay -D hw:CARD=RASPISPDIF,DEV=0 /tmp/spdif_48k.wav
```

If the file is already stereo 48 kHz `S16_LE`, you can play it directly:

```bash
aplay -D hw:CARD=RASPISPDIF,DEV=0 /path/to/file.wav
```

## Quick test

```bash
cd ~/CamillaDSP/prototypes/pi5_spdif_gpio
./scripts/test_kernel_spdif_alsa.sh
```

This plays short 1 kHz tests in `S16_LE` and `S32_LE`, generates a 48 kHz stereo
WAV, plays it with `aplay`, then prints recent kernel logs.

Short development stress test:

```bash
SPDIF_STRESS_LOOPS=5 SPDIF_STRESS_LOOP_SECONDS=2 SPDIF_STRESS_SKIP_LONG=1 \
  ./scripts/stress_kernel_spdif_alsa.sh
```

Longer stress test:

```bash
./scripts/stress_kernel_spdif_alsa.sh
```

Watch the kernel log during receiver tests:

```bash
dmesg -w
```

If the driver logs `encoded silence period`, ALSA did not feed the card quickly
enough and the output may contain a mute gap.

## Optical loopback validation

For the RASPIAUDIO product path, optical is the priority. A practical validation
setup is:

```text
GPIO12 S/PDIF
    -> TOSLINK transmitter
    -> optical cable
    -> TOSLINK-to-analog converter
    -> analog jack back into 8xIN / 8xIN+8xOUT ADC inputs
```

This proves that the optical S/PDIF stream carries real audio continuously and
lets us capture the result with the Pi ADC. It does not replace a final optical
jitter or compliance measurement, but it is the most useful functional test.

Run:

```bash
cd ~/CamillaDSP/prototypes/pi5_spdif_gpio

arecord -l

ADC_DEVICE=hw:CARD=sndrpihifiberry,DEV=0 \
ADC_CHANNELS=8 \
./scripts/validate_optical_loopback_adc.sh
```

If `arecord -l` shows another capture card name, replace `ADC_DEVICE` with that
device.

The RASPIAUDIO 8xIN+8xOUT ADC path is captured as `S32_LE`; the script analyzes
that 32-bit full-scale stream by default.

The script:

- Generates a 48 kHz stereo test WAV.
- Plays it through `RASPISPDIF`.
- Records all ADC channels as raw PCM.
- Finds which ADC channels received the converter output.
- Estimates loopback latency from a marker burst.
- Checks 50 ms tone blocks for mute gaps.
- Saves a summary, CSV metrics, raw capture, playback log, capture log, and
  filtered kernel log under `out/optical_loopback_*`.

If your converter is plugged into different ADC inputs, keep `ADC_CHANNELS=8`
and read the strongest channels from the generated summary.

Known-good Pi 5 + RASPIAUDIO 8xIN+8xOUT optical loopback result:

- `IN0` carried the left test tone.
- `IN1` carried the right test tone.
- Other ADC channels stayed near the noise floor.
- The active channels showed `0` 50 ms dropout blocks.

The reported latency is the complete loopback path, including the TOSLINK
transmitter, optical converter, analog output, and ADC capture.

For a longer measurement pass with channel mapping, latency, dropout, crosstalk,
frequency-response sanity checks, and rough harmonic THD of the complete chain:

```bash
ADC_DEVICE=hw:CARD=sndrpihifiberry,DEV=0 ADC_CHANNELS=8 \
  ./scripts/measure_optical_loopback_adc.py
```

See [`MEASUREMENTS.md`](MEASUREMENTS.md) for measured lab results and the
recommended public wording.

## Wiring

GPIO12 is a 3.3 V raw digital output. It is useful for lab work, but it is not
a compliant S/PDIF electrical output by itself.

Prototype pins:

- GPIO12, physical pin 32: S/PDIF-like signal.
- GND, for example physical pin 34: ground reference.

For product hardware:

- TOSLINK: use a proper optical transmitter module and its recommended current
  limiting or driver circuit.
- Coax: use a proper 75 ohm S/PDIF output stage, typically a buffer plus AC
  coupling or pulse transformer.
- Do not connect raw GPIO directly to unknown external equipment for a product
  validation.

## Remove

```bash
cd ~/CamillaDSP/prototypes/pi5_spdif_gpio
./scripts/uninstall_kernel_spdif_on_pi5.sh
```

If another audio service keeps the ALSA card open:

```bash
FORCE_AUDIO_STOP=1 ./scripts/uninstall_kernel_spdif_on_pi5.sh
```

To remove boot autoload too:

```bash
sudo rm -f /etc/modules-load.d/raspiaudio-spdif-pio.conf
sudo rm -f /etc/modprobe.d/raspiaudio-spdif-pio.conf
```

## Troubleshooting

No `RASPISPDIF` card:

```bash
cd ~/CamillaDSP/prototypes/pi5_spdif_gpio
./scripts/install_kernel_spdif_on_pi5.sh
dmesg | grep -i -E 'raspiaudio_spdif|rp1|pio'
```

Module is busy during reinstall:

```bash
FORCE_AUDIO_STOP=1 ./scripts/install_kernel_spdif_on_pi5.sh
```

Audio plays too fast or at the wrong pitch:

- Use the ALSA kernel driver path above.
- Convert the file to 48 kHz before playback.
- The older userspace PIOLib prototype needs a 200 MHz RP1 PIO clock on the
  tested Pi 5; the ALSA kernel driver handles this internally.

Audio is chopped:

- Make sure the repo includes the underrun feeder fix.
- Reinstall the kernel module.
- Check `dmesg` for `encoded silence period`.
- Test with a local 48 kHz WAV and `aplay`, not browser playback.

## What is proven

Validated on the lab Raspberry Pi 5:

- The module builds against Raspberry Pi kernel `6.12.47+rpt-rpi-2712`.
- `RASPISPDIF` appears as a normal ALSA playback card.
- `S16_LE` and `S32_LE` 48 kHz stereo playback work.
- Generated 48 kHz WAV playback works through `aplay`.
- A converted stereo music WAV played cleanly after the underrun feeder fix.
- Short start/stop stress passed without driver underrun logs.
- The card coexists with the USB audio gadget, `sndrpihifiberry`, and
  CamillaDSP on the same Pi.

Still to measure before product claims:

- Multiple receiver/DAC lock compatibility.
- Long external receiver lock with optical/coax hardware.
- Jitter and eye pattern.
- Final coax/TOSLINK electrical compliance.
- 44.1 kHz and 96 kHz support.

## Developer notes

The main solution is:

```text
kernel/raspiaudio_spdif_pio.c
scripts/install_kernel_spdif_on_pi5.sh
scripts/test_kernel_spdif_alsa.sh
scripts/stress_kernel_spdif_alsa.sh
scripts/validate_optical_loopback_adc.sh
scripts/measure_optical_loopback_adc.py
```

The older userspace PIOLib tools are kept for low-level experiments:

```text
scripts/build_on_pi5.sh
scripts/play_wav.sh
scripts/test_1khz_lock.sh
scripts/test_sweep_lock.sh
scripts/test_pwr_led_spdif_visual.sh
src/spdif_pi5_pio_tx.c
```

They are useful for understanding RP1 PIO output, but the ALSA kernel driver is
the recommended path for audio playback.

## Why not raspdif directly?

`raspdif` proves that software S/PDIF is possible on Raspberry Pi 1-4, but it
uses the older BCM283x PCM/I2S peripheral and DMA programming model. Raspberry
Pi 5 moved external I/O to RP1, so the old register addresses, GPIO muxing, and
DMA assumptions do not apply.

On Pi 5, the practical path is RP1 PIO plus DMA. This repo implements that as a
small ALSA playback driver.

## Sources

- `raspdif`: https://github.com/mill1000/raspdif
- Raspberry Pi RP1 peripherals datasheet: https://pip.raspberrypi.com/documents/RP-008370-DS-1-rp1-peripherals.pdf
- Raspberry Pi PIOLib announcement: https://www.raspberrypi.com/news/piolib-a-userspace-library-for-pio-control/
- Raspberry Pi PIOLib source: https://github.com/raspberrypi/utils/tree/master/piolib
- Pico S/PDIF via PIO reference: https://github.com/raspberrypi/pico-extras/tree/master/src/rp2_common/pico_audio_spdif
- Raspberry Pi 5 I2S/S/PDIF driver reference: https://github.com/riban-bw/zynaudiox8
