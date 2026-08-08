#!/usr/bin/env python3
"""Generate all Android launcher icon assets for AR Synth from the master SVGs.

Sources (in this directory):
  ar_synth_icon.svg  -> full self-contained icon (legacy ic_launcher.png, store art)
  ar_synth_bg.svg    -> adaptive-icon background layer
  ar_synth_fg.svg    -> adaptive-icon foreground layer (hand + ripples, safe-zoned)
  ar_synth_mono.svg  -> Android 13+ themed (monochrome) layer

Run:  python3 scripts/icon/generate_icons.py
"""
import os
import cairosvg

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.abspath(os.path.join(HERE, "..", "..", "android", "app", "src", "main", "res"))

# Legacy square launcher icon sizes (px) per density bucket.
LAUNCHER = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
# Adaptive layers are 108dp canvases.
ADAPTIVE = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}


def render(svg, out, size):
    os.makedirs(os.path.dirname(out), exist_ok=True)
    cairosvg.svg2png(url=os.path.join(HERE, svg), write_to=out,
                     output_width=size, output_height=size)
    print("  ", os.path.relpath(out, RES), f"{size}x{size}")


def main():
    print("Legacy launcher icons:")
    for bucket, size in LAUNCHER.items():
        d = os.path.join(RES, f"mipmap-{bucket}")
        render("ar_synth_icon.svg", os.path.join(d, "ic_launcher.png"), size)
        render("ar_synth_icon.svg", os.path.join(d, "ic_launcher_round.png"), size)

    print("Adaptive icon layers:")
    for bucket, size in ADAPTIVE.items():
        d = os.path.join(RES, f"mipmap-{bucket}")
        render("ar_synth_bg.svg",   os.path.join(d, "ic_launcher_background.png"), size)
        render("ar_synth_fg.svg",   os.path.join(d, "ic_launcher_foreground.png"), size)
        render("ar_synth_mono.svg", os.path.join(d, "ic_launcher_monochrome.png"), size)

    print("High-res store / README art:")
    render("ar_synth_icon.svg", os.path.join(HERE, "ar_synth_icon_1024.png"), 1024)


if __name__ == "__main__":
    main()
