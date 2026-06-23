# Raspberry Pi 5 GPIO S/PDIF OUT prototype

This folder is a separate, reversible experiment. It does not install services and does not change the existing CamillaDSP, USB gadget, or RASPIAUDIO 8xOUT profiles.

Status: prototype only. The encoder builds a 48 kHz stereo PCM S/PDIF BMC stream and the Pi 5 transmitter is written around RP1 PIO, but no marketing claim should be made until a real S/PDIF receiver locks reliably.

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

Risk: continuous lock depends on PIOLib/DMA feeding the FIFO without gaps. Early chunked tests produced an audible chopped "helicopter" noise on optical output, which is consistent with inter-chunk underruns. The default lock tests now precompute a short 2 second signal and send it as one DMA transfer. Longer one-shot transfers can hit the current PIOLib timeout. A kernel driver or circular DMA path is still the cleaner product path for continuous audio.

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
LD_LIBRARY_PATH=third_party/piolib-build ./build/spdif_pi5_pio_tx --gpio 12 --rate 48000 --pio-clock-hz 100000000 --mode tone --tone 1000 --seconds 2 --amplitude-dbfs -18 --chunk-frames 0
LD_LIBRARY_PATH=third_party/piolib-build ./build/spdif_pi5_pio_tx --gpio 12 --rate 48000 --pio-clock-hz 100000000 --mode sweep --sweep-start 120 --sweep-end 6000 --seconds 2 --amplitude-dbfs -18 --chunk-frames 0
```

With a scope or logic analyser, GPIO12 should show a 6.144 Mbit/s BMC waveform for 48 kHz.

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

Still to prove on hardware:

- Real receiver lock on GPIO12.
- Long-duration lock without underruns.
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
