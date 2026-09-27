"""Lay the brand logo out sideways for the site header and footer.

    python tools/logo.py

The brand files in assets/brand stack the moth above the word SHIVERBUG
STUDIOS, which is right for a sticker and far too tall for a header. This
takes the vector artwork from the black version, splits the moth from the
lettering by position, and sets them side by side, twice: lockup-ink.svg for
light bands (ink outlines, white fills) and lockup-cream.svg for the dark
footer (cream outlines, deep sea fills). They are files rather than inline SVG
so every page after the first gets them from the cache.

Run it again only if the brand artwork changes.
"""

import re
from pathlib import Path

from fontTools.pens.boundsPen import BoundsPen
from fontTools.svgLib.path import parse_path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets" / "brand" / "shiverbug-logo-black-rgb.svg"
OUT = ROOT / "assets" / "brand"
COLOURS = {"ink": ("#072230", "#ffffff"), "cream": ("#fff6e3", "#0b2f41")}

svg = SRC.read_text(encoding="utf-8")
assert "transform" not in svg, "the artwork has transforms; the split below assumes it has none"

mark, words = [], []
for m in re.finditer(r"<(path|circle)\b([^>]*?)/?>", svg):
    tag, attrs = m.groups()
    cls = re.search(r'class="([^"]+)"', attrs).group(1)
    role = {"cls-2": "o", "cls-3": "f"}[cls]
    if tag == "path":
        d = re.search(r'\sd="([^"]+)"', attrs).group(1)
        pen = BoundsPen(None)
        parse_path(d, pen)
        top = pen.bounds[1]
        el = f'<path class="{role}" d="{d}"/>'
    else:
        cx, cy, r = (re.search(rf'\s{k}="([^"]+)"', attrs).group(1) for k in ("cx", "cy", "r"))
        top = float(cy) - float(r)
        el = f'<circle class="{role}" cx="{cx}" cy="{cy}" r="{r}"/>'
    (mark if top < 494 else words).append(el)

# Artwork bounds, read off the paths: the moth sits in x 240-616, y 125-490,
# the lettering in x 162-692, y 498-725.
MARK = (240, 125, 376, 365)
WORD = (162, 498, 530, 227)
mh = 280
ms = mh / MARK[3]
mw = MARK[2] * ms
gap = 34
wx = mw + gap
wy = (mh - WORD[3]) / 2
width = wx + WORD[2]

for name, (outline, fill) in COLOURS.items():
    out = (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width:.0f} {mh}" width="{width:.0f}" height="{mh}">'
        f"<title>Shiverbug Studios</title>"
        f"<style>.o{{fill:{outline}}}.f{{fill:{fill}}}</style>"
        f'<g transform="scale({ms:.5f}) translate({-MARK[0]} {-MARK[1]})">{"".join(mark)}</g>'
        f'<g transform="translate({wx - WORD[0]:.2f} {wy - WORD[1]:.2f})">{"".join(words)}</g>'
        f"</svg>\n"
    )
    path = OUT / f"lockup-{name}.svg"
    path.write_text(out, encoding="utf-8", newline="\n")
    print(f"wrote {path.relative_to(ROOT)}: {len(mark)} moth shapes, {len(words)} letter shapes, {len(out) // 1024} KB")

# Shana on her own, for small badges such as the alumni tag on the team page.
outline, fill = COLOURS["ink"]
moth = (
    f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{MARK[0]} {MARK[1]} {MARK[2]} {MARK[3]}" width="{MARK[2]}" height="{MARK[3]}">'
    f"<style>.o{{fill:{outline}}}.f{{fill:{fill}}}</style>{''.join(mark)}</svg>\n"
)
(OUT / "moth-ink.svg").write_text(moth, encoding="utf-8", newline="\n")
print(f"wrote assets/brand/moth-ink.svg, {len(moth) // 1024} KB")
