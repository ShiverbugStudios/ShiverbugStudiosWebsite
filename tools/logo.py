"""Lay the brand logo out sideways for the site header and footer.

    python tools/logo.py

The brand files in assets/brand stack the moth above the word SHIVERBUG
STUDIOS, which is right for a sticker and far too tall for a header. This
takes the vector artwork, splits the moth from the lettering by position, and
sets them side by side, twice:

- lockup-ink.svg for light bands: the black version's artwork with ink
  outlines and white fills, as the brand sits on white.
- lockup-on-dark.svg for the deep sea header and footer, as the brand sits on
  black: the moth from shiverbug-icon-on-black-rgb.svg, which draws the moon
  white, beside the lettering from the on-black version, where STUDIOS is
  white too. Recolouring the black version for a dark band would turn the
  moth and the lettering inside out.

They are files rather than inline SVG so every page after the first gets them
from the cache. It also writes moth-ink.svg, Shana on her own in the ink
colourway (the brand's look on cyan, black moon and all), for the alumni
badge, the new-starter slots and the team page.

Run it again only if the brand artwork changes.
"""

import re
from pathlib import Path

from fontTools.pens.boundsPen import BoundsPen
from fontTools.svgLib.path import parse_path

ROOT = Path(__file__).resolve().parents[1]
BRAND = ROOT / "assets" / "brand"
INK, WHITE, BLACK = "#072230", "#ffffff", "#010101"


def shapes(path, roles):
    """The artwork's paths and circles as (element, top), with each element's
    class swapped for its role: o for outlines, f for fills."""
    svg = path.read_text(encoding="utf-8")
    assert "transform" not in svg, f"{path.name} has transforms; the split below assumes it has none"
    out = []
    for m in re.finditer(r"<(path|circle)\b([^>]*?)/?>", svg):
        tag, attrs = m.groups()
        role = roles[re.search(r'class="([^"]+)"', attrs).group(1)]
        if tag == "path":
            d = re.search(r'\sd="([^"]+)"', attrs).group(1)
            pen = BoundsPen(None)
            parse_path(d, pen)
            out.append((f'<path class="{role}" d="{d}"/>', pen.bounds[1]))
        else:
            cx, cy, r = (re.search(rf'\s{k}="([^"]+)"', attrs).group(1) for k in ("cx", "cy", "r"))
            out.append((f'<circle class="{role}" cx="{cx}" cy="{cy}" r="{r}"/>', float(cy) - float(r)))
    return out


def split(items):
    """The moth and moon sit above y 494 in every brand file; the lettering below."""
    return [el for el, top in items if top < 494], [el for el, top in items if top >= 494]


mark, words = split(shapes(BRAND / "shiverbug-logo-black-rgb.svg", {"cls-2": "o", "cls-3": "f"}))
dark_mark, _ = split(shapes(BRAND / "shiverbug-icon-on-black-rgb.svg", {"b": "o", "a": "f"}))
_, dark_words = split(shapes(BRAND / "shiverbug-logo-on-black-rgb.svg", {"cls-1": "o", "cls-2": "f"}))

# Artwork bounds, read off the paths: the moth sits in x 240-616, y 125-490,
# the lettering in x 162-692, y 498-725. The icon file shares the coordinates.
MARK = (240, 125, 376, 365)
WORD = (162, 498, 530, 227)
mh = 280
ms = mh / MARK[3]
mw = MARK[2] * ms
gap = 34
wx = mw + gap
wy = (mh - WORD[3]) / 2
width = wx + WORD[2]

for name, moth, letters, (outline, fill) in (
    ("ink", mark, words, (INK, WHITE)),
    ("on-dark", dark_mark, dark_words, (BLACK, WHITE)),
):
    out = (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width:.0f} {mh}" width="{width:.0f}" height="{mh}">'
        f"<title>Shiverbug Studios</title>"
        f"<style>.o{{fill:{outline}}}.f{{fill:{fill}}}</style>"
        f'<g transform="scale({ms:.5f}) translate({-MARK[0]} {-MARK[1]})">{"".join(moth)}</g>'
        f'<g transform="translate({wx - WORD[0]:.2f} {wy - WORD[1]:.2f})">{"".join(letters)}</g>'
        f"</svg>\n"
    )
    path = BRAND / f"lockup-{name}.svg"
    path.write_text(out, encoding="utf-8", newline="\n")
    print(f"wrote {path.relative_to(ROOT)}: {len(moth)} moth shapes, {len(letters)} letter shapes, {len(out) // 1024} KB")

# Shana on her own.
moth = (
    f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{MARK[0]} {MARK[1]} {MARK[2]} {MARK[3]}" width="{MARK[2]}" height="{MARK[3]}">'
    f"<style>.o{{fill:{INK}}}.f{{fill:{WHITE}}}</style>{''.join(mark)}</svg>\n"
)
(BRAND / "moth-ink.svg").write_text(moth, encoding="utf-8", newline="\n")
print(f"wrote assets/brand/moth-ink.svg, {len(moth) // 1024} KB")
