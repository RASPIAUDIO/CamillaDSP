# Stereo 3-way + dual subs active crossover

This profile turns the Raspberry Pi 5 + RASPIAUDIO 8xOUT into an open
miniDSP-style active crossover:

```text
USB stereo audio from PC
  -> Raspberry Pi 5 USB audio gadget, 2 channels, 48 kHz
  -> CamillaDSP crossover / PEQ / gain / delay
  -> RASPIAUDIO 8xOUT analog outputs
  -> amplifiers and speaker drivers
```

![Stereo 3-way active crossover routing](../../docs/assets/stereo-3way-active-crossover-8xout.png)

## Safety first

Start with the amplifiers at very low volume. Do not connect tweeters
directly for the first test. The preset includes a `Master_Safety_Gain_minus_12dB`
filter and each output trim starts at `-6 dB`, but wiring or amplifier gain can
still damage drivers.

## Files

Main preset:

```text
configs/stereo_3way_dual_subs_48k_8xout.yml
```

After running the main installer, CamillaGUI can also load it from:

```text
/etc/camilladsp/stereo_3way_dual_subs_48k_8xout.yml
```

Variant:

```text
configs/stereo_3way_mono_sub_spare_out8_48k_8xout.yml
```

The main preset expects the 2-channel USB audio gadget profile. It receives
only USB left and USB right, then creates the 8 crossover outputs in CamillaDSP.

## Output routing

| RASPIAUDIO output | Signal |
|---:|---|
| OUT1 | Left tweeter |
| OUT2 | Left midrange |
| OUT3 | Left woofer |
| OUT4 | Left sub |
| OUT5 | Right tweeter |
| OUT6 | Right midrange |
| OUT7 | Right woofer |
| OUT8 | Right sub |

USB left feeds OUT1, OUT2, OUT3, and OUT4. USB right feeds OUT5, OUT6,
OUT7, and OUT8.

## Default crossover

All crossover filters are Linkwitz-Riley 24 dB/octave. In CamillaDSP this is
`BiquadCombo` with `order: 4`.

| Driver | Filters |
|---|---|
| Sub | low-pass 80 Hz |
| Woofer | high-pass 80 Hz, low-pass 300 Hz |
| Midrange | high-pass 300 Hz, low-pass 2500 Hz |
| Tweeter | high-pass 2500 Hz |

## Edit in CamillaGUI

1. Open CamillaGUI: `http://<raspberry-pi-ip>:5005/gui/index.html`.
2. Go to **Files** and load `stereo_3way_dual_subs_48k_8xout.yml`.
3. Go to **Pipeline**. The order is mixer, master safety gain, crossover,
   then PEQ/gain/delay for each output.
4. Go to **Filters** to edit frequencies, PEQ bands, gain trims, and delays.
5. Press **Apply** to send the edit to the running DSP.
6. Press **Save** to write the edited YAML.

## Change crossover frequencies

In **Filters**, edit these named filters:

- `Sub_Lowpass_80Hz_LR24`
- `Woofer_Highpass_80Hz_LR24`
- `Woofer_Lowpass_300Hz_LR24`
- `Midrange_Highpass_300Hz_LR24`
- `Midrange_Lowpass_2500Hz_LR24`
- `Tweeter_Highpass_2500Hz_LR24`

Change the `freq` value. Keep `order: 4` for Linkwitz-Riley 24 dB/oct.

## PEQ, gain, and delay

Each output has 10 named PEQ placeholders:

```text
L_Tweeter_PEQ_01 ... L_Tweeter_PEQ_10
R_Sub_PEQ_01 ... R_Sub_PEQ_10
```

A PEQ with `gain: 0.0` is flat. To use a PEQ, enter the `freq`, `gain`,
and `q` values from your measurement.

Each output also has:

```text
<Output>_Output_Trim_minus_6dB
<Output>_Delay_ms
```

Use gain trim for level matching. Use delay in milliseconds for acoustic
time alignment.

## REW workflow

1. Measure each driver separately with REW and a measurement microphone.
2. Export or note the PEQ filters from REW.
3. In CamillaGUI, copy each REW band manually into the matching PEQ filter:
   frequency to `freq`, gain to `gain`, Q to `q`.
4. Re-measure, adjust output gain trims, then adjust delays for phase/time
   alignment around the crossover regions.
5. Keep the master safety gain low until the crossover and routing are verified.

## Mono sub + spare OUT8 variant

`stereo_3way_mono_sub_spare_out8_48k_8xout.yml` keeps OUT1-OUT3 and
OUT5-OUT7 as stereo 3-way outputs. OUT4 receives a mono L+R summed sub.
OUT8 receives a mono full-range test/spare signal but is muted by default
in `Spare_Fullrange_Output_Trim_minus_6dB`.
