"""Make every image the site serves, from the masters in source/.

    python tools/images.py            # only what is missing or older than its master
    python tools/images.py --force    # everything

Needs Pillow (and fontTools for the social cards, to read the woff2 fonts).
This is an asset step you run by hand after adding or changing a picture; CI
never runs it. It writes WebP into assets/img/ and records every output in
data/images.json, which is what the page build reads to write srcset and the
width/height attributes. Commit both.

Masters stay in source/, which _config.yml keeps off the published site.
"""

import io
import json
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "source"
OUT = ROOT / "assets" / "img"
MANIFEST = ROOT / "data" / "images.json"
FORCE = "--force" in sys.argv

# Colours shared with assets/css/site.css. The ink is the outline colour the
# game draws round its own title and UI text.
INK = (7, 34, 48)
SEA = (5, 205, 242)
CREAM = (255, 246, 227)


def widths_for(src_w, wanted):
    """The widths to write: every wanted width the master can honestly fill, plus
    the master's own width when it falls short of the largest. Nothing upscales."""
    out = [w for w in wanted if w <= src_w]
    if not out or (out[-1] < src_w and out[-1] < wanted[-1]):
        out.append(src_w)
    return sorted(set(out))


def save_set(img, name, wanted, quality=80, alpha=False):
    """Write name-<w>.webp for each width and return the manifest entry."""
    dest = OUT / name
    dest.parent.mkdir(parents=True, exist_ok=True)
    ws = widths_for(img.width, wanted)
    for w in ws:
        path = dest.parent / f"{dest.name}-{w}.webp"
        h = round(img.height * w / img.width)
        im = img if w == img.width else img.resize((w, h), Image.LANCZOS)
        if not alpha:
            im = im.convert("RGB")
        im.save(path, "WEBP", quality=quality, method=6)
    # Sizes an earlier run wrote that this one did not (a new crop can make a
    # portrait narrower than it used to be).
    for old in dest.parent.glob(f"{dest.name}-*.webp"):
        width = old.stem[len(dest.name) + 1:]
        if width.isdigit() and int(width) not in ws:
            old.unlink()
    return {"w": img.width, "h": img.height, "widths": ws, "alpha": alpha}


def fresh(master, name):
    """True when the outputs for name are newer than the master."""
    if FORCE:
        return False
    outs = list((OUT / name).parent.glob(f"{(OUT / name).name}-*.webp"))
    return bool(outs) and all(o.stat().st_mtime >= master.stat().st_mtime for o in outs)


# --- Photographs and screenshots -------------------------------------------

PHOTO_WIDTHS = [480, 800, 1200, 1600, 2000]

# name in assets/img -> master, optional crop box (left, top, right, bottom in px)
PHOTOS = {
    "game/cove": ("game/cove.jpg", None),
    "game/hats": ("game/hats.jpg", None),
    "game/title-scene": ("game/title-scene.jpg", None),
    # The hub shot has a placeholder cube and a prop box at its bottom corners.
    "game/hub-lagoon": ("game/hub-lagoon.jpg", (60, 0, 1600, 570)),
    "game/prototype-trailer": ("game/prototype-trailer.jpg", None),
    "photos/protoplay-public-vote-2025": ("photos/protoplay-public-vote-2025.jpg", None),
    "photos/tranzfuser-founders-2025": ("photos/tranzfuser-founders-2025.jpg", None),
    "photos/brighton-team-2026": ("photos/brighton-team-2026.jpg", None),
    "photos/brighton-founders-2026": ("photos/brighton-founders-2026.jpg", None),
}


def work_masters():
    work = json.loads((ROOT / "data" / "work.json").read_text(encoding="utf-8"))
    for piece in work["pieces"]:
        yield f"work/{piece['image']}", f"work/{piece['image']}.webp"


# --- Team portraits ---------------------------------------------------------

PORTRAIT_WIDTHS = [240, 360, 480, 640]


def portrait(master, crop):
    """Cut a 4:5 portrait. crop is [left, top, width] as fractions of the master;
    without one the frame is as wide as the photo and sits at the top."""
    im = Image.open(master)
    W, H = im.size
    left, top, width = crop or [0, 0, 1]
    w = W * width
    h = w * 5 / 4
    if h > H:  # a wide master: take the full height and centre it
        h = H
        w = h * 4 / 5
        left = (1 - w / W) / 2 if crop is None else left
    x, y = W * left, H * top
    y = min(max(0, y), H - h)
    x = min(max(0, x), W - w)
    return im.crop((round(x), round(y), round(x + w), round(y + h)))


# --- Stickers ---------------------------------------------------------------

STICKER_WIDTHS = [160, 320, 480, 720]

# name -> master, whether it needs a die-cut border added, trim box fix
STICKERS = {
    "stickers/koopa": ("stickers/koopa.png", False),
    "stickers/kiko": ("stickers/kiko.png", False),
    "stickers/koopa-3d": ("game/koopa-render.png", True),
    "stickers/kiko-3d": ("game/kiko-render.png", True),
    "stickers/crab-grunt": ("stickers/crab-grunt.png", True),
    "stickers/crab-cannon": ("stickers/crab-cannon.png", True),
    "stickers/crab-shield": ("stickers/crab-shield.png", True),
    "stickers/crab-ghost": ("stickers/crab-ghost.png", True),
    "stickers/parrot-pirate": ("stickers/parrot-pirate.png", True),
    "stickers/baby-turtle": ("stickers/baby-turtle.png", True),
}


def largest_blob_only(im):
    """Drop floating specks (a stray shell fragment, a glow) that sit apart from
    the model, so the die-cut border hugs one shape rather than several."""
    a = im.getchannel("A").point(lambda v: 255 if v > 24 else 0)
    # Close small gaps so a claw and a body count as one piece.
    grown = a.filter(ImageFilter.MaxFilter(15))
    w, h = grown.size
    px = grown.load()
    seen = bytearray(w * h)
    best = None
    for sy in range(0, h, 3):
        for sx in range(0, w, 3):
            if px[sx, sy] == 0 or seen[sy * w + sx]:
                continue
            stack, pts = [(sx, sy)], []
            seen[sy * w + sx] = 1
            while stack:
                x, y = stack.pop()
                pts.append((x, y))
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] and px[nx, ny]:
                        seen[ny * w + nx] = 1
                        stack.append((nx, ny))
            if best is None or len(pts) > len(best):
                best = pts
    keep = Image.new("L", (w, h), 0)
    kp = keep.load()
    for x, y in best:
        kp[x, y] = 255
    keep = keep.filter(ImageFilter.MaxFilter(3))
    r, g, b, alpha = im.split()
    return Image.merge("RGBA", (r, g, b, ImageChops.multiply(alpha, keep)))


def die_cut(im):
    """A white sticker border round a transparent render, like the character
    icons the game's UI already uses, then trimmed with a small margin."""
    im = largest_blob_only(im.convert("RGBA"))
    pad = max(12, round(max(im.size) * 0.035))
    canvas = Image.new("RGBA", (im.width + pad * 4, im.height + pad * 4), (0, 0, 0, 0))
    canvas.alpha_composite(im, (pad * 2, pad * 2))
    a = canvas.getchannel("A").point(lambda v: 255 if v > 40 else 0)
    border = a
    step = 9
    for _ in range(pad // (step // 2)):
        border = border.filter(ImageFilter.MaxFilter(step))
    border = border.filter(ImageFilter.GaussianBlur(1.2)).point(lambda v: 255 if v > 110 else 0)
    border = border.filter(ImageFilter.GaussianBlur(0.8))
    white = Image.new("RGBA", canvas.size, (255, 255, 255, 0))
    white.putalpha(border)
    out = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    out.alpha_composite(white)
    out.alpha_composite(canvas)
    return out.crop(out.getbbox())


# --- Social cards -----------------------------------------------------------


def font(path, size, **axes):
    """Load a woff2 variable font at an instance Pillow can draw with."""
    from fontTools.ttLib import TTFont
    from fontTools.varLib import instancer

    tt = TTFont(path)
    if axes and "fvar" in tt:
        tt = instancer.instantiateVariableFont(tt, axes)
    tt.flavor = None
    buf = io.BytesIO()
    tt.save(buf)
    buf.seek(0)
    return ImageFont.truetype(buf, size)


def outlined_text(draw, xy, text, fnt, fill, outline, width, shadow=0):
    x, y = xy
    if shadow:
        draw.text((x, y + shadow), text, font=fnt, fill=outline, stroke_width=width, stroke_fill=outline)
    draw.text((x, y), text, font=fnt, fill=fill, stroke_width=width, stroke_fill=outline)


def social_cards():
    fonts = ROOT / "assets" / "fonts"
    serif = lambda s: font(fonts / "fraunces-soft-latin.woff2", s, wght=720, opsz=144)
    sans = lambda s: font(fonts / "instrument-sans-latin.woff2", s, wght=600)
    lockup = Image.open(ROOT / "assets" / "brand" / "shiverbug-logo-on-blue.png").convert("RGBA")
    koopa = Image.open(SRC / "stickers" / "koopa.png").convert("RGBA")
    kiko = Image.open(SRC / "stickers" / "kiko.png").convert("RGBA")

    def fit(im, h):
        return im.resize((round(im.width * h / im.height), h), Image.LANCZOS)

    # The studio card: the logo as it appears on its own cyan, with the two
    # heroes stuck on beside it.
    card = Image.new("RGBA", (1200, 630), SEA + (255,))
    logo = fit(lockup, 560)
    card.alpha_composite(logo, (40, 35))
    card.alpha_composite(fit(kiko, 330).rotate(6, expand=True, resample=Image.BICUBIC), (800, 40))
    card.alpha_composite(fit(koopa, 250).rotate(-5, expand=True, resample=Image.BICUBIC), (640, 330))
    d = ImageDraw.Draw(card)
    d.text((660, 60), "Games you play", font=sans(34), fill=INK)
    d.text((660, 100), "side by side.", font=sans(34), fill=INK)
    card.convert("RGB").save(OUT / "og" / "studio.jpg", quality=86)

    # The game card: a still from the title scene with the title set the way
    # the game's own title screen sets it, cream with a hard ink outline.
    still = Image.open(SRC / "game" / "title-scene.jpg").convert("RGBA")
    still = still.resize((1200, round(still.height * 1200 / still.width)), Image.LANCZOS)
    still = still.crop((0, (still.height - 630) // 2, 1200, (still.height - 630) // 2 + 630))
    shade = Image.new("RGBA", still.size, INK + (0,))
    sd = ImageDraw.Draw(shade)
    for i in range(330):
        sd.line([(0, 630 - i), (1200, 630 - i)], fill=INK + (round(150 * (1 - i / 330) ** 1.6),))
    still.alpha_composite(shade)
    d = ImageDraw.Draw(still)
    t = serif(150)
    outlined_text(d, (56, 300), "Out of", t, CREAM, INK, 7, shadow=10)
    outlined_text(d, (56, 430), "Water", t, CREAM, INK, 7, shadow=10)
    still.alpha_composite(fit(koopa, 150).rotate(-4, expand=True, resample=Image.BICUBIC), (1000, 450))
    still.convert("RGB").save(OUT / "og" / "out-of-water.jpg", quality=86)


def favicons():
    """The moth, cut from the brand artwork, on the brand cyan."""
    src = Image.open(ROOT / "assets" / "brand" / "shiverbug-logo-on-blue.png").convert("RGBA")
    s = src.width / 854.56  # the brand SVG's viewBox width
    mark = src.crop((round(228 * s), round(118 * s), round(628 * s), round(500 * s)))
    side = max(mark.size)
    sq = Image.new("RGBA", (side, side), SEA + (255,))
    sq.alpha_composite(mark, ((side - mark.width) // 2, (side - mark.height) // 2))
    (ROOT / "assets" / "icons").mkdir(exist_ok=True)
    for size, name in ((180, "apple-touch-icon.png"), (192, "icon-192.png"), (512, "icon-512.png"), (48, "favicon-48.png")):
        sq.resize((size, size), Image.LANCZOS).convert("RGB").save(ROOT / "assets" / "icons" / name, optimize=True)


def main():
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8")) if MANIFEST.exists() else {}
    jobs = []

    for name, (master, box) in PHOTOS.items():
        jobs.append((name, SRC / master, lambda m=SRC / master, b=box: Image.open(m).crop(b) if b else Image.open(m), PHOTO_WIDTHS, 80, False))

    # A LinkedIn post's own picture, saved as source/news/<post id>.jpg.
    for m in sorted((SRC / "news").glob("*")):
        if m.suffix.lower() in (".jpg", ".jpeg", ".png", ".webp"):
            jobs.append((f"news/{m.stem}", m, lambda m=m: Image.open(m).convert("RGB"), [480, 800, 1200], 80, False))

    for name, master in work_masters():
        jobs.append((name, SRC / master, lambda m=SRC / master: Image.open(m), [640, 960, 1600], 82, False))

    team = json.loads((ROOT / "data" / "team.json").read_text(encoding="utf-8"))
    for person in team["team"] + team["talent"]:
        m = SRC / "team" / person["photo"]
        jobs.append((f"team/{person['slug']}", m, lambda m=m, c=person.get("crop"): portrait(m, c), PORTRAIT_WIDTHS, 78, False, person.get("crop")))

    for name, (master, cut) in STICKERS.items():
        m = SRC / master
        jobs.append((name, m, lambda m=m, c=cut: die_cut(Image.open(m)) if c else Image.open(m).convert("RGBA"), STICKER_WIDTHS, 88, True))

    made = 0
    for job in jobs:
        name, master, load, wanted, q, alpha = job[:6]
        # A crop lives in team.json rather than in the master, so a changed
        # crop has to count as a change on its own.
        spec = job[6] if len(job) > 6 else None
        if name in manifest and manifest[name].get("crop") == spec and fresh(master, name):
            continue
        img = load()
        manifest[name] = save_set(img, name, wanted, quality=q, alpha=alpha)
        if spec is not None:
            manifest[name]["crop"] = spec
        made += 1
        print("made", name, manifest[name]["widths"])

    (OUT / "og").mkdir(parents=True, exist_ok=True)
    if FORCE or not (OUT / "og" / "studio.jpg").exists():
        social_cards()
        favicons()
        print("made social cards and icons")

    # Drop entries whose job no longer exists.
    names = {j[0] for j in jobs}
    manifest = {k: v for k, v in sorted(manifest.items()) if k in names}
    MANIFEST.write_text(json.dumps(manifest, indent=1) + "\n", encoding="utf-8", newline="\n")
    print(f"{made} image sets written, {len(manifest)} in the manifest")


if __name__ == "__main__":
    main()
