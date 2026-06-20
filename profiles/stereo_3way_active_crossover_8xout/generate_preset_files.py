#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
from textwrap import dedent

import yaml
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
CONFIG_DIR = ROOT / "configs"
ASSET_DIR = ROOT / "docs" / "assets"
PROFILE_DIR = Path(__file__).resolve().parent

SAMPLERATE = 48000
PEQ_COUNT = 10

PEQ_FREQS = {
    "tweeter": [2500, 3500, 5000, 7000, 9000, 11000, 13000, 15000, 17000, 19000],
    "midrange": [300, 450, 630, 900, 1200, 1600, 2000, 2500, 3150, 4000],
    "woofer": [80, 110, 150, 200, 250, 300, 400, 500, 630, 800],
    "sub": [20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160],
    "fullrange": [31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000],
}

CROSSOVERS = {
    "sub": [("Sub_Lowpass_80Hz_LR24", "LinkwitzRileyLowpass", 80)],
    "woofer": [
        ("Woofer_Highpass_80Hz_LR24", "LinkwitzRileyHighpass", 80),
        ("Woofer_Lowpass_300Hz_LR24", "LinkwitzRileyLowpass", 300),
    ],
    "midrange": [
        ("Midrange_Highpass_300Hz_LR24", "LinkwitzRileyHighpass", 300),
        ("Midrange_Lowpass_2500Hz_LR24", "LinkwitzRileyLowpass", 2500),
    ],
    "tweeter": [("Tweeter_Highpass_2500Hz_LR24", "LinkwitzRileyHighpass", 2500)],
    "fullrange": [],
}


def output(name: str, label: str, role: str, channel: int, muted: bool = False) -> dict:
    return {"name": name, "label": label, "role": role, "channel": channel, "muted": muted}


DUAL_SUB_OUTPUTS = [
    output("L_Tweeter", "OUT1 Left tweeter", "tweeter", 0),
    output("L_Midrange", "OUT2 Left midrange", "midrange", 1),
    output("L_Woofer", "OUT3 Left woofer", "woofer", 2),
    output("L_Sub", "OUT4 Left sub", "sub", 3),
    output("R_Tweeter", "OUT5 Right tweeter", "tweeter", 4),
    output("R_Midrange", "OUT6 Right midrange", "midrange", 5),
    output("R_Woofer", "OUT7 Right woofer", "woofer", 6),
    output("R_Sub", "OUT8 Right sub", "sub", 7),
]

MONO_SUB_SPARE_OUTPUTS = [
    output("L_Tweeter", "OUT1 Left tweeter", "tweeter", 0),
    output("L_Midrange", "OUT2 Left midrange", "midrange", 1),
    output("L_Woofer", "OUT3 Left woofer", "woofer", 2),
    output("Mono_Sub", "OUT4 Mono sub", "sub", 3),
    output("R_Tweeter", "OUT5 Right tweeter", "tweeter", 4),
    output("R_Midrange", "OUT6 Right midrange", "midrange", 5),
    output("R_Woofer", "OUT7 Right woofer", "woofer", 6),
    output("Spare_Fullrange", "OUT8 Spare full-range test, muted by default", "fullrange", 7, muted=True),
]


def gain_filter(gain: float, description: str, muted: bool = False) -> dict:
    params = {"gain": gain, "inverted": False, "mute": muted, "scale": "dB"}
    return {"type": "Gain", "description": description, "parameters": params}


def delay_filter(description: str) -> dict:
    return {
        "type": "Delay",
        "description": description,
        "parameters": {"delay": 0.0, "unit": "ms", "subsample": False},
    }


def peq_filter(freq: float, description: str) -> dict:
    return {
        "type": "Biquad",
        "description": description,
        "parameters": {"type": "Peaking", "freq": freq, "gain": 0.0, "q": 1.0},
    }


def crossover_filter(kind: str, freq: int, description: str) -> dict:
    return {
        "type": "BiquadCombo",
        "description": description,
        "parameters": {"type": kind, "freq": freq, "order": 4},
    }


def source(channel: int, gain: float = 0.0) -> dict:
    return {"channel": channel, "gain": gain, "inverted": False}


def build_filters(outputs: list[dict]) -> dict:
    filters = {
        "Master_Safety_Gain_minus_12dB": gain_filter(
            -12.0,
            "Global safety attenuation. Raise only after testing at low amplifier volume.",
        )
    }

    for role_filters in CROSSOVERS.values():
        for name, kind, freq in role_filters:
            if name not in filters:
                filters[name] = crossover_filter(
                    kind,
                    freq,
                    f"{name.replace('_', ' ')} crossover section.",
                )

    for out in outputs:
        name = out["name"]
        role = out["role"]
        for idx, freq in enumerate(PEQ_FREQS[role], start=1):
            filters[f"{name}_PEQ_{idx:02d}"] = peq_filter(
                freq,
                f"{name} PEQ placeholder {idx:02d}. Gain 0 dB means bypass/flat.",
            )
        filters[f"{name}_Output_Trim_minus_6dB"] = gain_filter(
            -6.0,
            f"{name} output trim. Default -6 dB for safe first power-up.",
            muted=out["muted"],
        )
        filters[f"{name}_Delay_ms"] = delay_filter(
            f"{name} time alignment delay in milliseconds. Default 0 ms."
        )

    return filters


def build_dual_sub_mixer() -> dict:
    return {
        "channels": {"in": 2, "out": 8},
        "description": "USB left feeds OUT1-OUT4. USB right feeds OUT5-OUT8.",
        "mapping": [
            {"dest": 0, "sources": [source(0)]},
            {"dest": 1, "sources": [source(0)]},
            {"dest": 2, "sources": [source(0)]},
            {"dest": 3, "sources": [source(0)]},
            {"dest": 4, "sources": [source(1)]},
            {"dest": 5, "sources": [source(1)]},
            {"dest": 6, "sources": [source(1)]},
            {"dest": 7, "sources": [source(1)]},
        ],
    }


def build_mono_sub_spare_mixer() -> dict:
    return {
        "channels": {"in": 2, "out": 8},
        "description": "Stereo 3-way plus mono summed sub on OUT4 and muted mono full-range spare on OUT8.",
        "mapping": [
            {"dest": 0, "sources": [source(0)]},
            {"dest": 1, "sources": [source(0)]},
            {"dest": 2, "sources": [source(0)]},
            {"dest": 3, "sources": [source(0, -6.0), source(1, -6.0)]},
            {"dest": 4, "sources": [source(1)]},
            {"dest": 5, "sources": [source(1)]},
            {"dest": 6, "sources": [source(1)]},
            {"dest": 7, "sources": [source(0, -6.0), source(1, -6.0)]},
        ],
    }


def build_pipeline(mixer_name: str, outputs: list[dict]) -> list[dict]:
    pipeline = [
        {"type": "Mixer", "name": mixer_name},
        {"type": "Filter", "channels": list(range(8)), "names": ["Master_Safety_Gain_minus_12dB"]},
    ]

    for role in ("sub", "woofer", "midrange", "tweeter"):
        channels = [out["channel"] for out in outputs if out["role"] == role]
        if not channels:
            continue
        names = [name for name, _, _ in CROSSOVERS[role]]
        if names:
            pipeline.append({"type": "Filter", "channels": channels, "names": names})

    for out in outputs:
        names = [f"{out['name']}_PEQ_{idx:02d}" for idx in range(1, PEQ_COUNT + 1)]
        names.extend([f"{out['name']}_Output_Trim_minus_6dB", f"{out['name']}_Delay_ms"])
        pipeline.append({"type": "Filter", "channels": [out["channel"]], "names": names})

    return pipeline


def build_config(title: str, description: str, mixer_name: str, mixer: dict, outputs: list[dict]) -> dict:
    return {
        "title": title,
        "description": description,
        "devices": {
            "samplerate": SAMPLERATE,
            "chunksize": 256,
            "target_level": 768,
            "adjust_period": 10,
            "capture": {
                "type": "Alsa",
                "channels": 2,
                "device": "hw:CARD=UAC2Gadget,DEV=0",
                "format": "S32_LE",
            },
            "playback": {
                "type": "Alsa",
                "channels": 8,
                "device": "hw:CARD=sndrpihifiberry,DEV=0",
                "format": "S32_LE",
            },
        },
        "mixers": {mixer_name: mixer},
        "filters": build_filters(outputs),
        "pipeline": build_pipeline(mixer_name, outputs),
    }


def write_yaml(path: Path, config: dict) -> None:
    text = yaml.safe_dump(config, sort_keys=False, width=120, allow_unicode=False)
    path.write_text("---\n" + text, encoding="utf-8", newline="\n")


def write_readme() -> None:
    readme = dedent(
        """\
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
        """
    )
    (PROFILE_DIR / "README.md").write_text(readme, encoding="utf-8", newline="\n")


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        "C:/Windows/Fonts/arialbd.ttf" if bold else "C:/Windows/Fonts/arial.ttf",
        "C:/Windows/Fonts/segoeuib.ttf" if bold else "C:/Windows/Fonts/segoeui.ttf",
    ]
    for candidate in candidates:
        try:
            return ImageFont.truetype(candidate, size)
        except OSError:
            pass
    return ImageFont.load_default()


def rounded_box(draw: ImageDraw.ImageDraw, xy: tuple[int, int, int, int], fill: str, outline: str, radius: int = 16) -> None:
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=2)


def arrow(draw: ImageDraw.ImageDraw, start: tuple[int, int], end: tuple[int, int], color: str = "#304057") -> None:
    draw.line([start, end], fill=color, width=4)
    x1, y1 = end
    draw.polygon([(x1, y1), (x1 - 12, y1 - 8), (x1 - 12, y1 + 8)], fill=color)


def write_diagram() -> None:
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    img = Image.new("RGB", (1600, 1060), "#f7f9fb")
    draw = ImageDraw.Draw(img)
    title_font = font(46, True)
    h_font = font(28, True)
    body_font = font(23)
    small_font = font(19)

    draw.text((70, 50), "RASPIAUDIO 8xOUT active crossover preset", fill="#111827", font=title_font)
    draw.text((72, 112), "USB stereo input -> Raspberry Pi 5 -> CamillaDSP -> 8 analog outputs", fill="#475569", font=body_font)

    boxes = [
        (70, 190, 360, 320, "PC / Mac / Linux", "USB audio stereo\n2 ch / 48 kHz"),
        (470, 190, 780, 320, "Raspberry Pi 5", "USB gadget input\nUAC2Gadget capture"),
        (890, 170, 1250, 340, "CamillaDSP", "LR24 crossover\n10 PEQ / gain / delay\nper output"),
        (1360, 190, 1530, 320, "8xOUT", "8 analog\noutputs"),
    ]
    for x0, y0, x1, y1, head, body in boxes:
        rounded_box(draw, (x0, y0, x1, y1), "#ffffff", "#cbd5e1")
        draw.text((x0 + 24, y0 + 24), head, fill="#0f172a", font=h_font)
        draw.multiline_text((x0 + 24, y0 + 66), body, fill="#475569", font=body_font, spacing=6)

    arrow(draw, (360, 255), (470, 255))
    arrow(draw, (780, 255), (890, 255))
    arrow(draw, (1250, 255), (1360, 255))

    rows = [
        ("OUT1", "Left tweeter", "HP 2500 Hz LR24", "L_Tweeter_PEQ_01..10", "#7c3aed"),
        ("OUT2", "Left midrange", "HP 300 + LP 2500 Hz LR24", "L_Midrange_PEQ_01..10", "#2563eb"),
        ("OUT3", "Left woofer", "HP 80 + LP 300 Hz LR24", "L_Woofer_PEQ_01..10", "#059669"),
        ("OUT4", "Left sub", "LP 80 Hz LR24", "L_Sub_PEQ_01..10", "#dc2626"),
        ("OUT5", "Right tweeter", "HP 2500 Hz LR24", "R_Tweeter_PEQ_01..10", "#7c3aed"),
        ("OUT6", "Right midrange", "HP 300 + LP 2500 Hz LR24", "R_Midrange_PEQ_01..10", "#2563eb"),
        ("OUT7", "Right woofer", "HP 80 + LP 300 Hz LR24", "R_Woofer_PEQ_01..10", "#059669"),
        ("OUT8", "Right sub", "LP 80 Hz LR24", "R_Sub_PEQ_01..10", "#dc2626"),
    ]

    x, y = 110, 420
    col_w = [120, 260, 420, 360, 250]
    headers = ["Output", "Driver", "Crossover", "PEQ placeholders", "Safety"]
    draw.rectangle((x, y, x + sum(col_w), y + 54), fill="#111827")
    cx = x
    for idx, header in enumerate(headers):
        draw.text((cx + 16, y + 14), header, fill="#ffffff", font=small_font)
        cx += col_w[idx]

    y += 54
    for i, row in enumerate(rows):
        fill = "#ffffff" if i % 2 == 0 else "#f1f5f9"
        draw.rectangle((x, y, x + sum(col_w), y + 58), fill=fill, outline="#e2e8f0")
        cx = x
        values = [row[0], row[1], row[2], row[3], "master -12 dB\ntrim -6 dB"]
        for idx, value in enumerate(values):
            color = row[4] if idx == 0 else "#0f172a"
            draw.multiline_text((cx + 16, y + 12), value, fill=color, font=small_font, spacing=2)
            cx += col_w[idx]
        y += 58

    draw.text((112, 988), "Default is intentionally quiet. Test at low amplifier volume before connecting tweeters.", fill="#991b1b", font=body_font)
    img.save(ASSET_DIR / "stereo-3way-active-crossover-8xout.png")


def main() -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    ASSET_DIR.mkdir(parents=True, exist_ok=True)

    dual = build_config(
        "RASPIAUDIO stereo 3-way + dual subs active crossover 48k",
        "USB stereo input -> CamillaDSP -> RASPIAUDIO 8xOUT. OUT1/2/3/4 are left tweeter/mid/woofer/sub, OUT5/6/7/8 are right tweeter/mid/woofer/sub. Safe startup gain included.",
        "usb_stereo_to_stereo_3way_dual_subs_8xout",
        build_dual_sub_mixer(),
        DUAL_SUB_OUTPUTS,
    )
    mono = build_config(
        "RASPIAUDIO stereo 3-way + mono sub + spare OUT8 active crossover 48k",
        "USB stereo input -> CamillaDSP -> RASPIAUDIO 8xOUT. OUT4 is mono summed sub. OUT8 is mono full-range spare/test and muted by default.",
        "usb_stereo_to_stereo_3way_mono_sub_spare_8xout",
        build_mono_sub_spare_mixer(),
        MONO_SUB_SPARE_OUTPUTS,
    )

    write_yaml(CONFIG_DIR / "stereo_3way_dual_subs_48k_8xout.yml", dual)
    write_yaml(CONFIG_DIR / "stereo_3way_mono_sub_spare_out8_48k_8xout.yml", mono)
    write_readme()
    write_diagram()


if __name__ == "__main__":
    main()
