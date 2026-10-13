"""Cut the site's two typefaces down to what it uses, as woff2.

    python tools/fonts.py LuckiestGuy-Regular.ttf Nunito-VariableFont_wght.ttf Nunito-Italic.ttf

They are the faces of the studio's pitch decks: Luckiest Guy for headings and
Nunito for text, both from Google Fonts. Each is split into the latin and
latin-ext subsets Google Fonts serves, using the same unicode ranges as the
@font-face rules in assets/css/site.css, so a page in English only ever fetches
the latin files. Nunito's weight axis is narrowed to 400-800, which is
everything the site sets. The italic is Nunito's static regular italic: the
taglines are the only italic text.

Needs fontTools and brotli (pip install fonttools brotli). Run it once per
upstream update. The output is committed; nothing in CI runs it.
"""

import io
import sys
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

OUT = Path(__file__).resolve().parents[1] / "assets" / "fonts"

# Copied from the unicode-range of each @font-face in site.css.
RANGES = {
    "latin": "U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, "
    "U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD",
    "latin-ext": "U+0100-02BA, U+02BD-02C5, U+02C7-02CC, U+02CE-02D7, U+02DD-02FF, U+0304, U+0308, U+0329, "
    "U+1D00-1DBF, U+1E00-1E9F, U+1EF2-1EFF, U+2020, U+20A0-20AB, U+20AD-20C0, U+2113, U+2C60-2C7F, U+A720-A7FF",
}


def codepoints(spec):
    out = set()
    for part in spec.split(","):
        lo, _, hi = part.strip()[2:].partition("-")
        out.update(range(int(lo, 16), int(hi or lo, 16) + 1))
    return out


def family(src):
    stem = Path(src).stem.lower()
    if stem.startswith("luckiestguy"):
        return "luckiest-guy"
    return "nunito-italic" if "italic" in stem else "nunito"


for src in sys.argv[1:]:
    name = family(src)
    for script, spec in RANGES.items():
        font = TTFont(src)
        if "fvar" in font:
            # Saved and reopened, because the subsetter trips over the lazily
            # loaded tables the instancer leaves behind.
            buf = io.BytesIO()
            instancer.instantiateVariableFont(font, {"wght": (400, 800)}).save(buf)
            buf.seek(0)
            font = TTFont(buf)
        options = subset.Options()
        options.layout_features = ["*"]
        sub = subset.Subsetter(options)
        sub.populate(unicodes=codepoints(spec))
        sub.subset(font)
        font.flavor = "woff2"
        path = OUT / f"{name}-{script}.woff2"
        font.save(path)
        print(path.name, path.stat().st_size // 1024, "KB")
