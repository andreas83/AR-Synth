#!/usr/bin/env python3
"""Generate all Android launcher icon assets for AR Synth from the master SVGs.

Sources (in this directory):
  ar_synth_icon.svg  -> full self-contained icon (legacy ic_launcher.png, store art)
  ar_synth_bg.svg    -> adaptive-icon background layer
  ar_synth_fg.svg    -> adaptive-icon foreground layer (hand + ripples, safe-zoned)
  ar_synth_mono.svg  -> Android 13+ themed (monochrome) layer

The gradient colours live in one place — the PALETTES table below — and are
injected into the two gradient-bearing masters (icon + bg) at render time, so
switching the whole app logo is a one-line change. The foreground and
monochrome layers are the white waveform only and are palette-independent.

Run:  python3 scripts/icon/generate_icons.py                 # active palette
      python3 scripts/icon/generate_icons.py --palette aurora
      AR_SYNTH_PALETTE=sunset python3 scripts/icon/generate_icons.py
"""
import argparse
import os
import re

import cairosvg

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.abspath(os.path.join(HERE, "..", "..", "android", "app", "src", "main", "res"))

# Diagonal gradient stops (top-left -> mid -> bottom-right) per named option.
# Add a new tuple here to offer another logo colourway.
PALETTES = {
    "synthwave": ("#35d0ff", "#9a6bff", "#ff5ec8"),  # original: cyan -> purple -> pink
    "aurora":    ("#00f5a0", "#00d1f5", "#5b6bff"),  # option 1: mint -> cyan -> indigo
    "sunset":    ("#ffb830", "#ff5e8a", "#8a3ff0"),  # option 2: amber -> rose -> violet
    "ember":     ("#ff5a3c", "#ff2d78", "#b01eff"),  # option 3: orange-red -> magenta -> purple
}
# The colourway the app actually ships. Keep the committed master SVGs in sync
# with this so opening a master shows the real default.
ACTIVE_PALETTE = "ember"

# Legacy square launcher icon sizes (px) per density bucket.
LAUNCHER = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
# Adaptive layers are 108dp canvases.
ADAPTIVE = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}

_STOP_RE = re.compile(r'(stop-color=")#[0-9a-fA-F]{6}(")')


def tint(svg_text, palette):
    """Recolour the (up to three) gradient stops of a master SVG in order.

    Palette-agnostic: rewrites whatever hex values the file currently holds, so
    the committed master's colours don't have to match the requested palette.
    """
    colours = iter(palette)

    def repl(m):
        return f"{m.group(1)}{next(colours)}{m.group(2)}"

    return _STOP_RE.sub(repl, svg_text)


def render(svg_name, out, size, palette=None):
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(os.path.join(HERE, svg_name), encoding="utf-8") as f:
        svg = f.read()
    if palette is not None:
        svg = tint(svg, palette)
    cairosvg.svg2png(bytestring=svg.encode("utf-8"), write_to=out,
                     output_width=size, output_height=size)
    print("  ", os.path.relpath(out, RES), f"{size}x{size}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--palette",
        choices=sorted(PALETTES),
        default=os.environ.get("AR_SYNTH_PALETTE", ACTIVE_PALETTE),
        help=f"gradient colourway to render (default: {ACTIVE_PALETTE})",
    )
    args = parser.parse_args()
    palette = PALETTES[args.palette]
    print(f"Palette: {args.palette} {palette}")

    print("Legacy launcher icons:")
    for bucket, size in LAUNCHER.items():
        d = os.path.join(RES, f"mipmap-{bucket}")
        render("ar_synth_icon.svg", os.path.join(d, "ic_launcher.png"), size, palette)
        render("ar_synth_icon.svg", os.path.join(d, "ic_launcher_round.png"), size, palette)

    print("Adaptive icon layers:")
    for bucket, size in ADAPTIVE.items():
        d = os.path.join(RES, f"mipmap-{bucket}")
        render("ar_synth_bg.svg",   os.path.join(d, "ic_launcher_background.png"), size, palette)
        render("ar_synth_fg.svg",   os.path.join(d, "ic_launcher_foreground.png"), size)
        render("ar_synth_mono.svg", os.path.join(d, "ic_launcher_monochrome.png"), size)

    print("High-res store / README art:")
    render("ar_synth_icon.svg", os.path.join(HERE, "ar_synth_icon_1024.png"), 1024, palette)


if __name__ == "__main__":
    main()
