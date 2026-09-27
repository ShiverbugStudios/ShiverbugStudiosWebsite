"""Cut the display face down to the part of it the site uses.

    python tools/fonts.py path/to/Fraunces-latin.woff2 path/to/Fraunces-latin-ext.woff2

Fraunces ships with four axes. The site only ever sets it fully soft (SOFT 100)
and without the wonky alternates (WONK 0), between weights 500 and 800, so
those are pinned and narrowed here and the file drops to roughly half. The
optical size axis stays live: the browser picks it from the font size, which is
what keeps the big headings tight and the small ones open.

Run it once per upstream update. The output is committed; nothing in CI runs it.
"""

import sys
from pathlib import Path

from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

OUT = Path(__file__).resolve().parents[1] / "assets" / "fonts"

for src in sys.argv[1:]:
    font = TTFont(src)
    font = instancer.instantiateVariableFont(font, {"SOFT": 100, "WONK": 0, "wght": (500, 800)})
    font.flavor = "woff2"
    name = "fraunces-soft-" + ("latin-ext" if "ext" in Path(src).stem else "latin") + ".woff2"
    font.save(OUT / name)
    print(name, (OUT / name).stat().st_size // 1024, "KB")
