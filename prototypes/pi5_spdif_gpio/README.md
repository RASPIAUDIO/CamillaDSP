# Raspberry Pi 5 GPIO S/PDIF OUT prototype

This folder is a separate, reversible experiment. It does not install services and does not change the existing CamillaDSP, USB gadget, or RASPIAUDIO 8xOUT profiles.

Status: prototype only. The encoder builds a 48 kHz stereo PCM S/PDIF BMC stream and the Pi 5 ALSA transmitter is written around RP1 PIO. The kernel path has now survived Pi-side smoke and stress tests at 48 kHz stereo, but no product or marketing claim should be made until lock, jitter, and the final coax/TOSLINK output stage are measured on real receivers.

## What raspdif does on Pi 4

`raspdif` proves that software S/PDIF is possible on Raspberry Pi 1-4, but it is not simple GPIO bit-banging.

- It reads raw 16-bit or 24-bit stereo PCM, usually from a FIFO exposed through ALSA.
- It builds S/PDIF subframes, channel status, parity, and BMC coding in memory.
- It uses the BCM283x PCM/I2S peripheral as a serial shifter.
- It uses DMA control blocks to feed encoded buffers into the PCM FIFO.
- It clocks PCM at `sample_rate * 64 * 2`; for 48 kHz this is 6.144 MHz.
- It muxes GPIO21/pin 40 to `PCM_DOUT` using the old BCM283x alternate function.

That means the CPU prepares buffers, but the timing-critical output is done by hardware clock + DMA.

## Why raspdif does not run unchanged on Pi 5

Raspberry Pi 5 moved the external I/O to the RP1 southbridge. The old assumptions in `raspdif` no longer match the hardware:

- BCM283x peripheral base addresses, DMA registers, PCM FIFO addresses, and clock registers are not the same programming model on Pi 5.
- GPIO21 is still on the 40-pin header, but its muxing is now RP1 muxing, not the old BCM283x GPIO block.
- The Pi 5 path to deterministic GPIO is now RP1 peripherals, especially RP1 PIO through the `rp1-pio` driver and PIOLib.
- A userspace `gpiod`/sysfs loop is far too slow for S/PDIF: 48 kHz stereo needs a 6.144 MHz half-bit stream.

## Pi 5 architecture options

### Option A: RP1 PIO

This is the best prototype path. Generate S/PDIF/BMC words in userspace, then let a PIO state machine output one bit per PIO clock cycle. For 48 kHz stereo, set the PIO state machine to 6.144 MHz and feed packed 32-bit words to its TX FIFO.

The included `spdif_pi5_pio_tx` does exactly this experimentally:

- PIO program: one instruction, `out pins, 1`.
- Data format: packed 32-bit words, MSB first.
- Default output: GPIO12, physical pin 32.
- Default audio: 48 kHz stereo, 1 kHz sine or 120 Hz -> 6 kHz sweep, -18 dBFS, 2 seconds.

Risk: continuous lock depends on PIOLib/DMA feeding the FIFO without gaps. Early chunked tests produced an audible chopped "helicopter" noise on optical output, which is consistent with inter-chunk underruns. The playback prototype now pre-encodes the finite tone/sweep/WAV stream and submits it as one PIOLib transfer, while PIOLib splits that transfer into smaller DMA bounce buffers internally. A kernel driver or circular DMA path is still the cleaner product path for endless audio.

The WAV playback path uses one userspace PIOLib transfer with about 0.5 second per internal DMA bounce buffer by default. This avoids a user/kernel handoff every 0.5 second, which caused visible TOSLINK LED drops during earlier tests. It is not yet a real ALSA circular-DMA driver: memory use scales with file length at about 16 bytes per stereo PCM frame, so a 30 second 44.1 kHz WAV needs about 21 MB of encoded buffer. On the tested Pi 5, the RP1 PIO clock must be treated as 200 MHz; using 100 MHz makes S/PDIF play at exactly double speed.

The buffering strategy is inspired by DSPi's S/PDIF output model on RP2040/RP2350: audio blocks are prepared ahead of time, the PIO output is fed by DMA, and the firmware exposes diagnostics such as consumer-buffer fill and DMA starvation counters. On Raspberry Pi 5, PIOLib does not currently expose the same bare-metal circular-DMA control from userspace, so this prototype uses the closest reversible approach: one finite transfer plus configurable PIOLib DMA bounce buffers. A product-grade version should move this into an ALSA/kernel driver or an external I2S-to-S/PDIF transmitter.

On the RASPIAUDIO 8xOUT / 8xIN+8xOUT setup, do not use GPIO18-GPIO27 for this prototype. The Pi 5 `hifiberry-dac8x` overlay uses those pins for I2S0:

- GPIO18: I2S0_SCLK
- GPIO19: I2S0_WS
- GPIO20, 22, 24, 26: I2S0 input lanes
- GPIO21, 23, 25, 27: I2S0 output lanes

GPIO21 was used by the original Pi 1-4 `raspdif`, but on this Pi 5 audio setup it is already `I2S0_SDO0`. GPIO12 is the safer default lab pin because it is not claimed by the active 8xOUT overlay.

### Option B: userspace low-level daemon

A userspace daemon that toggles GPIO directly is not realistic for product-quality S/PDIF. It would need stable edges up to 6.144 MHz at 48 kHz, 12.288 MHz at 96 kHz, and low jitter. Linux scheduling cannot guarantee this through normal GPIO APIs.

A userspace daemon can still be useful if it delegates timing to PIO or another hardware shifter.

### Option C: small kernel driver

This is the right direction if the PIO prototype locks but has gaps. The driver should expose an ALSA PCM playback device, encode IEC958/S/PDIF frames, and feed RP1 PIO or RP1 I2S/DMA continuously from kernel context.

For a product, also consider an external S/PDIF transmitter chip fed from I2S. That is less exotic and easier to validate than raw GPIO S/PDIF.

## Experimental ALSA kernel driver

This repo now includes an out-of-tree Raspberry Pi 5 module:

```text
kernel/raspiaudio_spdif_pio.c
```

It exposes a normal ALSA playback card:

```text
RASPISPDIF
hw:CARD=RASPISPDIF,DEV=0
```

V1 is intentionally narrow:

- Raspberry Pi 5 only.
- 48 kHz only.
- Stereo playback only.
- ALSA formats: `S16_LE` and `S32_LE`.
- Fixed period: 960 frames, 20 ms.
- Fixed buffer: 4 periods, 3840 frames, 80 ms.
- Encoded DMA period: 15360 bytes.
- Default raw output pin: GPIO12.
- Module parameters: `gpio=12`, `drive_ma=8`, `zero_on_underrun=1`.

The driver pre-encodes each ALSA period to S/PDIF BMC in kernel memory and queues the period to RP1 PIO DMA. On DMA completion, the callback advances the ALSA hardware pointer, records one elapsed period, and wakes a feeder kthread. The feeder calls `snd_pcm_period_elapsed()` and queues the next period. This keeps ALSA notification and DMA rearming in kernel context without doing heavier ALSA work directly inside the RP1 PIO completion callback. This is not a true `dmaengine_prep_dma_cyclic` implementation yet; it is a periodic kernel DMA queue using the exported `rp1-pio` API. If this still shows any lock drop under stress, the next step is a lower-level RP1 DMAengine/cyclic path or an external I2S-to-S/PDIF transmitter.

Do not use GPIO18-GPIO27 for this driver on a RASPIAUDIO 8xOUT or 8xIN+8xOUT setup. Those pins are reserved by the active I2S overlay.

Validated on the lab Raspberry Pi 5 on 2026-06-23:

- Build against `6.12.47+rpt-rpi-2712` Raspberry Pi kernel headers.
- `modinfo` dependencies: `snd-pcm`, `rp1-pio`, `snd`.
- ALSA card appears as `RASPISPDIF` on GPIO12.
- `speaker-test` works with `S16_LE` and `S32_LE` at 48 kHz stereo.
- A generated 48 kHz stereo WAV plays with `aplay`.
- 50 start/stop playback loops passed.
- 30 minutes continuous `speaker-test` passed without Pi crash, kernel Oops, panic, or driver-related underrun in the filtered log.
- Uninstall/reinstall is reversible when no ALSA client keeps the card open; with WirePlumber holding the control device, use `FORCE_AUDIO_STOP=1`.
- The card coexisted with the USB audio gadget, `sndrpihifiberry`, and an active CamillaDSP service on the same Pi.

### Build, install, remove

Run this on the Raspberry Pi 5:

```bash
cd ~/CamillaDSP/prototypes/pi5_spdif_gpio
chmod +x scripts/*.sh
./scripts/build_kernel_spdif_on_pi5.sh
./scripts/install_kernel_spdif_on_pi5.sh
```

Expected check:

```bash
aplay -l | grep -A2 RASPISPDIF
```

Remove the test driver cleanly:

```bash
cd ~/CamillaDSP/prototypes/pi5_spdif_gpio
./scripts/uninstall_kernel_spdif_on_pi5.sh
```

If the module is busy, the script refuses to remove it and prints the ALSA clients holding `/dev/snd/*`. On Raspberry Pi OS Desktop, WirePlumber may open every ALSA control device automatically. For a lab Pi where it is acceptable to stop user audio services temporarily:

```bash
FORCE_AUDIO_STOP=1 ./scripts/uninstall_kernel_spdif_on_pi5.sh
```

The install script uses the same safeguard: if an old module is still loaded and busy, either close the client or run with `FORCE_AUDIO_STOP=1`.

### ALSA smoke test

```bash
cd ~/CamillaDSP/prototypes/pi5_spdif_gpio
./scripts/test_kernel_spdif_alsa.sh
```

This script runs a short `speaker-test`, generates a 4 second 48 kHz stereo S16_LE WAV, plays it with `aplay`, then prints recent kernel logs.

Manual commands:

```bash
speaker-test -D hw:CARD=RASPISPDIF,DEV=0 -c 2 -r 48000 -F S16_LE -t sine -f 1000
aplay -D hw:CARD=RASPISPDIF,DEV=0 /tmp/raspiaudio_spdif_48k_s16_1khz.wav
```

### Stress test

```bash
cd ~/CamillaDSP/prototypes/pi5_spdif_gpio
./scripts/stress_kernel_spdif_alsa.sh
```

Defaults:

- 50 start/stop loops.
- 30 minute continuous `speaker-test`.

Useful shorter development run:

```bash
SPDIF_STRESS_LOOPS=5 SPDIF_STRESS_LOOP_SECONDS=2 SPDIF_STRESS_SKIP_LONG=1 ./scripts/stress_kernel_spdif_alsa.sh
```

During a real validation run, also watch the receiver lock LED, TOSLINK light, and kernel log:

```bash
dmesg -w
```

## Build on Raspberry Pi 5

Use a current Raspberry Pi OS 64-bit install on Raspberry Pi 5.

```bash
cd ~/CamillaDSP/prototypes/pi5_spdif_gpio
chmod +x scripts/*.sh
./scripts/build_on_pi5.sh
```

If `/dev/pio0` is missing, update Raspberry Pi OS and EEPROM, then reboot:

```bash
sudo apt update
sudo apt full-upgrade -y
sudo raspi-config
# Advanced Options -> Bootloader Version -> Latest
sudo reboot
```

If `/dev/pio0` exists but permissions fail:

```bash
sudo usermod -aG gpio "$USER"
sudo tee /etc/udev/rules.d/99-rp1-pio.rules >/dev/null <<'EOF'
SUBSYSTEM=="*-pio", GROUP="gpio", MODE="0660"
EOF
sudo udevadm control --reload-rules
sudo udevadm trigger
newgrp gpio
```

## Generate a test stream without GPIO

This proves the encoder path and produces one second of packed BMC data.

```bash
cd ~/CamillaDSP/prototypes/pi5_spdif_gpio
mkdir -p out
./build/spdif_gen \
  --rate 48000 \
  --tone 1000 \
  --seconds 1 \
  --amplitude-dbfs -12 \
  --output out/spdif_48k_1khz_1s.bmc32 \
  --self-test
```

Expected size for 48 kHz, one second:

```text
48000 stereo frames * 128 half-bits / 8 = 768000 bytes
```

For a quick local sanity check of the encoder, scripts, and optional PIOLib build:

```bash
cd ~/CamillaDSP/prototypes/pi5_spdif_gpio
./scripts/verify_local.sh
```

If PIOLib is in a custom location, pass it explicitly:

```bash
PIOLIB_INC=/path/to/piolib/include PIOLIB_LIB=/path/to/piolib/build ./scripts/verify_local.sh
```

## GPIO lock test

Raw GPIO is only for lab validation. Start with a short cable and low-risk receiver.

```bash
cd ~/CamillaDSP/prototypes/pi5_spdif_gpio
./scripts/test_1khz_lock.sh
./scripts/test_sweep_lock.sh
```

The receiver/DAC should report lock as PCM 48 kHz. The first script plays a 2 second 1 kHz sine, and the second plays a 2 second 120 Hz -> 6 kHz sweep. If it does not lock:

```bash
ls -l /dev/pio0
sudo dmesg | grep -i -E 'rp1|pio'
LD_LIBRARY_PATH=third_party/piolib-build ./build/spdif_pi5_pio_tx --gpio 12 --rate 48000 --pio-clock-hz 200000000 --mode tone --tone 1000 --seconds 2 --amplitude-dbfs -18 --chunk-frames 0
LD_LIBRARY_PATH=third_party/piolib-build ./build/spdif_pi5_pio_tx --gpio 12 --rate 48000 --pio-clock-hz 200000000 --mode sweep --sweep-start 120 --sweep-end 6000 --seconds 2 --amplitude-dbfs -18 --chunk-frames 0
```

With a scope or logic analyser, GPIO12 should show a 6.144 Mbit/s BMC waveform for 48 kHz.

## Raspberry Pi 5 LED visual test

The Raspberry Pi 5 ACT LED is not a useful S/PDIF output target for this prototype. It is not on an RP1 PIO-capable GPIO path.

The PWR LED is different: on the tested Pi 5 it is attached to RP1 GPIO44, so it can be used for a short visual lab test. This is only a way to see that RP1 PIO can drive the LED pin. It is not a valid TOSLINK output, not an electrical S/PDIF output, and not a receiver-lock test.

```bash
cd ~/CamillaDSP/prototypes/pi5_spdif_gpio
./scripts/build_on_pi5.sh
chmod +x scripts/test_pwr_led_spdif_visual.sh
./scripts/test_pwr_led_spdif_visual.sh
```

The script temporarily disables the Linux LED trigger for `/sys/class/leds/PWR`, blinks the LED three times slowly, sends a short 48 kHz stereo S/PDIF BMC stream on GPIO44, then restores the LED trigger. The LED may look steady or dim during the S/PDIF part because the carrier is 6.144 MHz.

Useful overrides:

```bash
SPDIF_LED_SECONDS=10 ./scripts/test_pwr_led_spdif_visual.sh
SPDIF_LED_NAME=PWR SPDIF_LED_GPIO=44 ./scripts/test_pwr_led_spdif_visual.sh
```

To play a WAV file, use PCM s16le stereo WAV. The file sample rate is used for S/PDIF channel status and clocking.

```bash
cd ~/CamillaDSP/prototypes/pi5_spdif_gpio
./scripts/play_wav.sh /path/to/file.wav
```

The WAV helper defaults to GPIO12, four PIOLib DMA buffers, 200 MHz RP1 PIO clock, and about 0.5 second per internal DMA bounce buffer. The WAV is encoded up front and submitted as one contiguous PIOLib transfer, which avoids an audible/visible dropout at every userspace chunk boundary. For experiments:

```bash
SPDIF_DMA_BUFFERS=8 SPDIF_CHUNK_FRAMES=24000 ./scripts/play_wav.sh /path/to/file.wav
```

`SPDIF_CHUNK_FRAMES` controls the internal DMA bounce-buffer size, not an application-level playback chunk. Keep it below roughly one second of audio so the current PIOLib userspace driver can recycle DMA buffers without hitting its timeout. If 44.1 kHz does not lock on a given receiver, convert the WAV to 48 kHz PCM s16le and test again before blaming the GPIO stage.

## Wiring

Prototype raw GPIO test:

- GPIO12, physical pin 32: S/PDIF-like signal.
- GND, for example physical pin 34: ground reference.
- Do not connect raw GPIO to unknown equipment for product testing.

Coax final output should be designed as a proper 75 ohm S/PDIF electrical output, around 0.5 Vpp into 75 ohm, normally with AC coupling and/or pulse transformer/buffering. A simple resistor divider may be acceptable for a bench proof, but it is not a final product output stage.

TOSLINK final output should use a proper optical transmitter module with the required current limiting or driver stage. A bare LED from GPIO is only a quick hack, not a product design.

## Limits to measure

- Lock reliability: must be proven on real DACs/receivers.
- Jitter: PIO clock edges should be stable, but FIFO underruns or buffer gaps will break the stream.
- 44.1 kHz: likely feasible at 5.6448 MHz half-bit clock, but must be tested.
- 48 kHz: target of this prototype, 6.144 MHz half-bit clock.
- 96 kHz: PIO can clock 12.288 MHz, but buffer rate doubles to 1.536 MB/s and underrun risk increases.
- CPU: BMC generation is light, but userspace chunk scheduling is the weak point.
- Electrical level: raw 3.3 V GPIO is not S/PDIF compliant.
- Product readiness: use a kernel driver or external S/PDIF transmitter before claiming product support.

## Proven vs open

Proven in this repo:

- `raspdif` Pi 4 architecture was inspected.
- Pi 5 public RP1/PIOLib path was identified.
- A standalone S/PDIF/BMC 48 kHz encoder is included.
- A Pi 5 RP1/PIO transmitter skeleton is included and buildable with PIOLib.
- On a live Pi 5 with `hifiberry-dac8x`, GPIO18-GPIO27 are occupied by the 8xOUT/8xIN+8xOUT I2S path, so GPIO12 is now the default test pin.
- The experimental ALSA driver source, Makefile, install/uninstall scripts, smoke test script, and stress test script are included.
- On the lab Pi after reboot, the module built, loaded, and exposed `RASPISPDIF` on kernel `6.12.47+rpt-rpi-2712`.
- `speaker-test` passed in `S16_LE` and `S32_LE` at 48 kHz stereo.
- A generated 48 kHz stereo WAV played through ALSA with `aplay`.
- A 50-loop start/stop stress test passed.
- A 30 minute continuous 48 kHz stereo ALSA run completed. `timeout` returned `124`, as expected, and the Pi remained reachable.
- Forced uninstall was tested with WirePlumber holding the ALSA control device: `FORCE_AUDIO_STOP=1` stopped the user audio services, removed `RASPISPDIF`, and reinstall recreated it.
- After reinstall, `RASPISPDIF`, the USB gadget, `sndrpihifiberry`, and `camilladsp.service` were all visible/active together.

Still to prove on hardware:

- Real receiver lock on GPIO12 with the kernel ALSA driver over multiple receivers.
- Long-duration external receiver lock. The 30 minute Pi-side ALSA/kernel run is proven, but the optical/coax receiver lock LED was not instrumented in this log.
- Full analog 8xOUT audio regression after a cold reboot with the user's normal Camilla profile.
- Automatic boot-time loading policy. The prototype currently installs and loads manually; it does not create a service or `/etc/modules-load.d` entry.
- 44.1 kHz and 96 kHz behavior.
- Jitter and eye pattern.
- Correct final coax/TOSLINK electrical stage.

## Prior art and next references

No public project was found that is already a finished `raspdif` equivalent for Raspberry Pi 5 bare GPIO S/PDIF output. The closest useful references are:

- `pico_audio_spdif`: Raspberry Pi's Pico example for S/PDIF output via PIO. It is not Pi 5 code, but it is the best reference for a cleaner PIO program, DMA feeding, 192-frame S/PDIF blocks, X/Y/Z preambles, and channel-status handling.
- `zynaudiox8`: a Raspberry Pi 5 project with a device-tree overlay, 8-channel I2S audio, and a kernel driver with S/PDIF duplex support. It is not a bare-GPIO `raspdif` port, but it is useful prior art for a future ALSA/kernel-driver implementation on Pi 5.
- Raspberry Pi forum discussion: a Raspberry Pi engineer notes that `raspdif` relies on old low-level mechanisms such as `/dev/mem`, mailbox calls, and `bcm_host_get_sdram_address()`, so it is very unlikely to work unchanged on Pi 5. The same comment points out that a clean kernel driver is plausible, and that ALSA already has IEC958 encapsulation support.

These references reinforce the current roadmap: first prove a fixed 48 kHz stereo sine on RP1 PIO, then move to a continuous buffered implementation, and only then consider ALSA/kernel integration.

## Sources

- `raspdif`: https://github.com/mill1000/raspdif
- Raspberry Pi RP1 peripherals datasheet: https://pip.raspberrypi.com/documents/RP-008370-DS-1-rp1-peripherals.pdf
- Raspberry Pi PIOLib announcement: https://www.raspberrypi.com/news/piolib-a-userspace-library-for-pio-control/
- Raspberry Pi PIOLib source: https://github.com/raspberrypi/utils/tree/master/piolib
- Kernel ALSA/I2S reference idea: https://github.com/kiffie/rpi-i2s-spdif
- Pico S/PDIF via PIO reference: https://github.com/raspberrypi/pico-extras/tree/master/src/rp2_common/pico_audio_spdif
- Raspberry Pi 5 I2S/S/PDIF driver reference: https://github.com/riban-bw/zynaudiox8
- Raspberry Pi forum Pi 5 S/PDIF discussion: https://forums.raspberrypi.com/viewtopic.php?t=390954
