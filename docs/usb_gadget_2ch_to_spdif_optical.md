# USB stereo to S/PDIF optical stereo

These CamillaDSP profiles turn the Raspberry Pi 5 into a USB audio input with
optical S/PDIF output:

```text
Windows / macOS / Linux USB audio
    -> Raspberry Pi 5 UAC2Gadget capture
    -> CamillaDSP
    -> RASPISPDIF ALSA playback
    -> GPIO12 optical transmitter
    -> TOSLINK receiver / DAC
```

It is separate from the RASPIAUDIO 8xOUT profiles. It uses the experimental
Raspberry Pi 5 S/PDIF ALSA driver from `prototypes/pi5_spdif_gpio`.

## Profiles

For the current RASPIAUDIO 7.1 USB gadget, use the front-left/front-right
profiles:

```text
configs/usb_gadget_8ch_48k_front_lr_to_spdif_optical_stereo.yml
configs/usb_gadget_8ch_48k_front_lr_to_spdif_optical_stereo_fir_load.yml
```

Those open the 8-channel USB gadget but only route host channels 1 and 2 to
S/PDIF:

```text
USB front left  -> S/PDIF left
USB front right -> S/PDIF right
```

For a pure 2-channel USB gadget, use:

```text
configs/usb_gadget_2ch_48k_to_spdif_optical_stereo.yml
configs/usb_gadget_2ch_48k_to_spdif_optical_stereo_fir_load.yml
```

For a lab test that does not need USB audio from a computer, use:

```text
configs/signalgen_1khz_48k_to_spdif_optical_fir_load.yml
```

The FIR load profiles add:

```text
Master_Safety_Gain_minus_12dB
Stereo_FIR_Load_4096_Taps
```

The FIR coefficient file is generated separately so the YAML stays readable.

## Limits

- Raspberry Pi 5 only.
- Optical S/PDIF driver must already be installed.
- Fixed 48 kHz.
- Stereo only.
- Playback device: `hw:CARD=RASPISPDIF,DEV=0`.
- Capture device for the USB profiles: `hw:CARD=UAC2Gadget,DEV=0`.
- The S/PDIF driver currently uses 20 ms ALSA periods, so these profiles use
  `chunksize: 960` and `target_level: 2880`.
- The USB capture clock and the S/PDIF playback clock are independent. The USB
  profiles therefore enable CamillaDSP rate adjustment with
  `enable_rate_adjust: true`, `adjust_period: 1`, and `queuelimit: 8`.

## Install the profiles on the Pi

From the repo checkout on the Raspberry Pi:

```bash
cd ~/raspiaudio-camilladsp-latest
sudo ./scripts/install_camilladsp_spdif_optical_profiles.sh
```

That command copies the profiles into `/etc/camilladsp`, generates the 4096-tap
FIR coefficient file in `/etc/camilladsp/coeffs`, and validates the YAML with
CamillaDSP.

If the optical S/PDIF ALSA card is not installed yet, install it first:

```bash
cd ~/raspiaudio-camilladsp-latest/prototypes/pi5_spdif_gpio
./scripts/install_kernel_spdif_on_pi5.sh
aplay -l | grep -A2 RASPISPDIF
```

## Run from CamillaGUI

Open:

```text
http://<raspberry-pi-ip>:5005/gui/index.html
```

In `Files`, load:

```text
usb_gadget_8ch_48k_front_lr_to_spdif_optical_stereo.yml
```

For a DSP load test, load:

```text
usb_gadget_8ch_48k_front_lr_to_spdif_optical_stereo_fir_load.yml
```

If no PC is currently playing USB audio, use this lab-only profile instead:

```text
signalgen_1khz_48k_to_spdif_optical_fir_load.yml
```

It generates a 1 kHz sine inside CamillaDSP, applies the same FIR load, and
sends it to the optical S/PDIF output.

## Run from the shell

Stop the service first if it is already using the audio devices:

```bash
sudo systemctl stop camilladsp
```

Run the signal-generator load test for 20 seconds:

```bash
timeout 20s camilladsp -l info \
  -o /tmp/camilladsp_spdif_fir_load.log \
  /etc/camilladsp/signalgen_1khz_48k_to_spdif_optical_fir_load.yml
```

Check the log:

```bash
tail -n 80 /tmp/camilladsp_spdif_fir_load.log
```

Then restart the normal service if needed:

```bash
sudo systemctl start camilladsp
```

## Lab result

Tested on the RASPIAUDIO Raspberry Pi 5 lab unit on 2026-06-24:

- CamillaDSP version: `4.1.3`.
- USB gadget card present as `UAC2Gadget`.
- Optical S/PDIF card present as `RASPISPDIF`.
- With no USB host audio playing, CamillaDSP reports `Capture device is
  stalled`; this is expected and clears when the host sends audio.
- `signalgen_1khz_48k_to_spdif_optical_fir_load.yml` ran for 30 seconds with
  the 4096-tap FIR load.
- Measured CamillaDSP process load during that FIR test: about `0.7%` CPU on
  Raspberry Pi 5.
- No new S/PDIF underrun, silence-period, PIO, or DMA messages were printed in
  the kernel log during the FIR run.
- A real USB radio stream was tested through this chain:
  `Windows -> USB gadget -> CamillaDSP FIR -> optical S/PDIF -> TOSLINK DAC ->
  RASPIAUDIO ADC`.
- Without rate adjustment, `usb_gadget_8ch_48k_front_lr_to_spdif_optical_stereo.yml`
  produced repeated capture stalls, playback underruns, and audible optical
  dropouts.
- With `enable_rate_adjust: true`, `adjust_period: 1`, `queuelimit: 8`, and
  `chunksize: 960`, the FIR profile ran for 5 minutes. The only CamillaDSP
  stalls were two startup events, with `0` playback underruns and `0` sample-rate
  change warnings afterwards.
- The 5-minute ADC capture had active audio on channels 0 and 1, `0` silent
  100 ms windows below `-80 dBFS`, and `0` relative 100 ms drops deeper than
  35 dB below the median level.
- The installed `/etc/camilladsp/usb_gadget_8ch_48k_front_lr_to_spdif_optical_stereo_fir_load.yml`
  profile was also checked for 3 minutes. It reported `0` playback underruns
  and `0` sample-rate change warnings after startup, and the TOSLINK-to-analog
  jack converter output was validated by listening.

## Notes for editing

In CamillaGUI:

- The routing is in `Mixers`.
- `Master_Safety_Gain_minus_12dB` is in `Filters`.
- `Stereo_FIR_Load_4096_Taps` is a `Conv` filter.
- The order is visible in `Pipeline`.

The convolution filter uses CamillaDSP's `Conv` filter with raw text
coefficients. The coefficient file is one floating-point FIR tap per line.
