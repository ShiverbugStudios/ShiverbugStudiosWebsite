"""Build shiverbugstudios.com into the repository root.

    python tools/build.py

Standard library only, so CI needs nothing but Python. Reads:

    src/layout.html      the page shell
    src/pages/*.html     one file per page: a front matter block, then the page
    data/*.json          people, work, studio facts, and the image manifest

and writes every published HTML page, the minified stylesheet, the press
archives, sitemap.xml, robots.txt and llms.txt. Everything it writes is
committed, because GitHub Pages serves this folder as it is; CI runs the build
again and fails if the result differs from what was committed.

Inside a page, {{ ... }} is a Python expression evaluated against the helpers
at the bottom of this file, e.g. {{ img("game/cove", "Koopa and Kiko on the
beach", sizes="50vw") }} or {{ people_grid("founders") }}. Keep them to calls
and names: the build is for us, not for untrusted input.
"""

import datetime
import hashlib
import html
import json
import re
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load(name):
    return json.loads((ROOT / "data" / name).read_text(encoding="utf-8"))


SITE = load("site.json")
TEAM = load("team.json")
WORK = load("work.json")
NEWS = load("news.json")
IMAGES = load("images.json")
BASE = SITE["url"]

PEOPLE = TEAM["team"] + TEAM["talent"]
BY_SLUG = {p["slug"]: p for p in PEOPLE}
DISCIPLINES = {d["id"]: d for d in WORK["disciplines"]}

written = []  # every file this run produced, for the stale-file sweep


def e(value):
    return html.escape(str(value), quote=True)


def typo(text):
    """Curly apostrophes in the studio's own copy. Never applied to what people
    wrote about themselves in team.json: those words go out exactly as written."""
    return re.sub(r"(?<=[A-Za-z])'(?=[A-Za-z])", "’", text)


def typo_html(text):
    return "".join(p if p.startswith("<") else typo(p) for p in re.split(r"(<[^>]+>)", text))


def write(rel, content, binary=False):
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    data = content if binary else content.encode("utf-8")
    if not path.exists() or path.read_bytes() != data:
        path.write_bytes(data)
    written.append(rel.replace("\\", "/"))


def versioned(url):
    """A site path with a short content hash, so a changed file is never served
    from a stale cache (Pages caches for ten minutes)."""
    digest = hashlib.sha1(lf((ROOT / url.lstrip("/")).read_bytes())).hexdigest()[:10]
    return f"{url}?v={digest}"


def lf(data):
    """Text as git stores it, whatever the checkout did to the line endings."""
    return data.replace(b"\r\n", b"\n")


# ---- Images ------------------------------------------------------------------


def srcset(name):
    return ", ".join(f"/assets/img/{name}-{w}.webp {w}w" for w in IMAGES[name]["widths"])


def src(name, near=960):
    ws = IMAGES[name]["widths"]
    return f"/assets/img/{name}-{next((w for w in ws if w >= near), ws[-1])}.webp"


def full(name):
    return f"/assets/img/{name}-{IMAGES[name]['widths'][-1]}.webp"


def img(name, alt, sizes="100vw", cls="", eager=False, near=960):
    if name not in IMAGES:
        raise KeyError(f"no image called {name!r} in data/images.json; run tools/images.py")
    entry = IMAGES[name]
    attrs = [
        f'src="{src(name, near)}"',
        f'srcset="{srcset(name)}"',
        f'sizes="{sizes}"',
        f'width="{entry["w"]}"',
        f'height="{entry["h"]}"',
        f'alt="{e(alt)}"',
    ]
    if cls:
        attrs.append(f'class="{cls}"')
    attrs.append('fetchpriority="high"' if eager else 'loading="lazy"')
    attrs.append('decoding="async"')
    return f"<img {' '.join(attrs)}>"


def sticker(name, cls="", sizes="200px", eager=False):
    """Decorative cut-outs: empty alt, so a screen reader skips them."""
    return img(f"stickers/{name}", "", sizes=sizes, cls=f"sticker {cls}".strip(), near=320, eager=eager)


# ---- People ------------------------------------------------------------------


def listed(p):
    """A person with no about text is unfinished: no page and no link."""
    return bool(p.get("about"))


def url(p):
    return f"/team/{p['slug']}"


def first(p):
    return p["name"].split()[0]


def side(p):
    return {"turtle": ("koopa", "Team Turtle"), "seagull": ("kiko", "Team Seagull")}.get(p.get("favourite"))


def side_tag(p):
    s = side(p)
    if not s:
        return ""
    icon, label = s
    cls = "tag" if icon == "koopa" else "tag tag--seagull"
    return f'<span class="{cls}">{img("stickers/" + icon, "", sizes="24px", near=160)}{label}</span>'


def alumni_tag(p):
    """The talent pool's two kinds of people: those contributing now, badged in
    the game's "you are here" gold, and former shiverbugs, badged with Shana
    the moth."""
    if p.get("status") == "active":
        return '<span class="tag tag--active">Contributing now</span>'
    if p.get("status") != "former":
        return ""
    moth = '<img src="/assets/brand/moth-ink.svg" alt="" width="376" height="365">'
    return f'<span class="tag tag--alumni">{moth}Shiverbug alumni</span>'


def face(p, big=False):
    photo = img(f"team/{p['slug']}", p["name"], sizes="76px" if big else "56px", near=240)
    return f'<a href="{url(p)}">{photo}</a>' if listed(p) else photo


def faces(slugs=None, group=None, big=False):
    ps = [BY_SLUG[s] for s in slugs] if slugs else group_members(group)
    cls = "faces faces--big" if big else "faces"
    return f'<ul class="{cls}">' + "".join(f"<li>{face(p, big)}</li>" for p in ps) + "</ul>"


def group_members(group):
    if group == "founders":
        return [p for p in TEAM["team"] if p.get("founder")]
    if group == "studio":
        return [p for p in TEAM["team"] if not p.get("founder")]
    if group == "team":
        return TEAM["team"]
    if group == "talent":  # people who work with us now, then the alumni
        return sorted(TEAM["talent"], key=lambda p: p.get("status") == "former")
    if group == "active":
        return [p for p in TEAM["talent"] if p.get("status") == "active"]
    if group == "former":
        return [p for p in TEAM["talent"] if p.get("status") == "former"]
    if group == "interns":
        return [p for p in TEAM["team"] if not p.get("founder")]
    raise KeyError(group)


def count(group):
    words = "zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen".split()
    n = len(group_members(group))
    return words[n] if n < len(words) else str(n)


def person_card(p):
    photo = f'<div class="person__photo">{img("team/" + p["slug"], "", sizes="(min-width: 72em) 16rem, (min-width: 40em) 30vw, 90vw", near=480)}</div>'
    body = (
        f'<h3>{e(p["name"])}</h3>'
        f'<p class="person__role">{e(p["role"])}</p>'
        f'<p class="person__line">{e(p["tagline"])}</p>'
    )
    tags = side_tag(p) + alumni_tag(p)
    inner = photo + body
    if listed(p):
        inner = f'<a href="{url(p)}">{inner}</a>'
    return f'<li class="person">{inner}{tags}</li>'


def people_grid(group):
    return '<ul class="people">' + "".join(person_card(p) for p in group_members(group)) + "</ul>"


def crew(slugs):
    out = []
    for s in slugs:
        p = BY_SLUG[s]
        if p.get("status") == "former":
            continue
        pic = img(f"team/{s}", "", sizes="36px", near=240)
        out.append(f'<li><a href="{url(p)}">{pic}<span>{e(p["name"])} <small>{e(p["role"].split(" · ")[0])}</small></span></a></li>')
    return '<ul class="crew">' + "".join(out) + "</ul>"


# ---- Work --------------------------------------------------------------------


def piece(pc):
    p = BY_SLUG[pc["by"]]
    name = f"work/{pc['image']}"
    credit = f"By {p['name']}" + (f", for {pc['project']}" if pc.get("project") else "")
    data = {
        "data-piece": "",
        "data-title": pc["title"],
        "data-by": credit,
        "data-note": typo(pc.get("note", "")),
        "data-alt": pc["alt"],
    }
    if pc.get("video"):
        data["data-video"] = f"/assets/video/{pc['video']}"
    attrs = " ".join(f'{k}="{e(v)}"' if v else k for k, v in data.items())
    badge = '<span class="badge">Has video</span>' if pc.get("video") else ""
    return (
        f'<li class="piece"><a href="{full(name)}" {attrs}>'
        f'<div class="piece__img">{img(name, pc["alt"], sizes="(min-width: 72em) 24rem, (min-width: 40em) 45vw, 92vw", near=640)}{badge}</div>'
        f'<h4>{e(pc["title"])}</h4><p>{e(credit)}</p></a></li>'
    )


def pieces_for(discipline=None, by=None):
    return [
        pc for pc in WORK["pieces"]
        if (discipline is None or pc["discipline"] == discipline)
        and (by is None or pc["by"] == by)
        and BY_SLUG[pc["by"]].get("status") != "former"
    ]


def gallery(discipline=None, by=None):
    ps = pieces_for(discipline, by)
    return '<ul class="gallery">' + "".join(piece(pc) for pc in ps) + "</ul>" if ps else ""


def service(did):
    d = DISCIPLINES[did]
    ticks = "".join(f"<li>{e(i)}</li>" for i in d["includes"])
    work = gallery(did)
    if not work:
        work = '<p class="service__nowork">Portfolio pieces for this one are on the way. Ask and we will send examples.</p>'
    return (
        f'<section class="service" id="{did}" aria-labelledby="{did}-title">'
        f'<div class="service__head"><div><h2 id="{did}-title">{e(d["name"])}</h2>'
        f'<p class="lede">{typo(e(d["summary"]))}</p></div>'
        f'<div><p>{typo(e(d["body"]))}</p><ul class="ticks">{ticks}</ul></div></div>'
        f"{crew(d['people'])}{work}</section>"
    )


def discipline_cards():
    out = []
    for d in WORK["disciplines"]:
        ps = pieces_for(d["id"])
        pic = img(f"work/{ps[0]['image']}", "", sizes="(min-width: 72em) 18rem, (min-width: 40em) 45vw, 92vw", near=640) if ps else ""
        out.append(
            f'<li class="discipline"><a href="/co-development#{d["id"]}">'
            f'<div class="discipline__img">{pic}</div><h3>{e(d["name"])}</h3><p>{typo(e(d["summary"]))}</p></a></li>'
        )
    return '<ul class="disciplines">' + "".join(out) + "</ul>"


# ---- News --------------------------------------------------------------------
# The studio's LinkedIn posts. We show our own headline and a short extract in
# the post's exact words, and send people to LinkedIn for the rest.


def post_date(p):
    # A LinkedIn activity id carries its own timestamp: the top 41 bits are
    # milliseconds since 1970. So the date never has to be typed in.
    ms = int(p["id"]) >> 22
    return datetime.datetime.fromtimestamp(ms / 1000, datetime.timezone.utc).date()


def post_url(p):
    return f"https://www.linkedin.com/feed/update/urn:li:activity:{p['id']}/"


def long_date(d):
    return f"{d.day} {d:%B %Y}"


def newest(limit=None):
    ps = sorted(NEWS["posts"], key=lambda p: int(p["id"]), reverse=True)
    return ps[:limit] if limit else ps


def post_image(p):
    name = p.get("image") or f"news/{p['id']}"
    return name if name in IMAGES else None


def post(p):
    d = post_date(p)
    pid = f"post-{p['id']}"
    quote = "".join(f"<p>{e(x)}</p>" for x in p["excerpt"])
    details = ""
    if p.get("details"):
        details = '<ul class="post__details">' + "".join(f"<li>{e(x)}</li>" for x in p["details"]) + "</ul>"
    people = ""
    if p.get("people"):
        people = f'<div class="post__people"><p>Tagged</p>{faces(p["people"])}</div>'
    pic = post_image(p)
    fig = ""
    if pic:
        fig = f'<figure class="post__img">{img(pic, p.get("alt", ""), sizes="(min-width: 60em) 26rem, 92vw", near=800)}</figure>'
    return (
        f'<li class="post{" post--img" if fig else ""}" id="{pid}"><article aria-labelledby="{pid}-title">'
        f'<time datetime="{d.isoformat()}">{long_date(d)}</time>'
        f'<div class="post__body"><h2 id="{pid}-title">{e(typo(p["title"]))}</h2>'
        f'<blockquote class="post__quote" cite="{post_url(p)}">{quote}</blockquote>{details}{people}'
        f'<p><a class="arrow-link" href="{post_url(p)}">Read the whole post on LinkedIn</a></p></div>'
        f"{fig}</article></li>"
    )


def news():
    return '<ol class="posts">' + "".join(post(p) for p in newest()) + "</ol>"


def latest_posts(limit=3):
    cards = []
    for p in newest(limit):
        d = post_date(p)
        cards.append(
            f'<li class="post-card"><a href="/news#post-{p["id"]}">'
            f'<time datetime="{d.isoformat()}">{long_date(d)}</time>'
            f'<h3>{e(typo(p["title"]))}</h3><p>{e(p["excerpt"][-1])}</p></a></li>'
        )
    return '<ul class="post-cards">' + "".join(cards) + "</ul>"


# ---- Studio ------------------------------------------------------------------


def log():
    items = []
    for item in SITE["log"]:
        text = f"<p>{typo(e(item['text']))}</p>"
        fig = ""
        if item.get("photo"):
            fig = f'<figure>{img(item["photo"], item["alt"], sizes="(min-width: 48em) 30rem, 92vw", near=800)}<figcaption>{e(item["caption"])}</figcaption></figure>'
        cls = "log__item log__item--photo" if fig else "log__item"
        items.append(f'<li class="{cls}"><time datetime="{item["when"]}">{e(item["label"])}</time>{text}{fig}</li>')
    return '<ol class="log">' + "".join(items) + "</ol>"


def facts(rows):
    return '<dl class="facts">' + "".join(f"<dt>{e(k)}</dt><dd>{v}</dd>" for k, v in rows) + "</dl>"


def game_facts():
    g = SITE["game"]
    return facts([
        ("Genre", e(g["genre"])),
        ("Players", e(g["players"])),
        ("Platform", e(g["platforms"])),
        ("Engine", e(g["engine"])),
        ("Status", e(g["status"])),
        ("Release", e(g["release"])),
        ("Developer", f'<a href="/">{e(SITE["legalName"])}</a>, {e(SITE["town"])}'),
    ])


def studio_facts():
    founders = ", ".join(f'<a href="{url(p)}">{e(p["name"])}</a>' for p in group_members("founders"))
    return facts([
        ("Studio", e(SITE["legalName"])),
        ("Based in", f"{e(SITE['town'])}, {e(SITE['region'])}, UK"),
        ("Founded", e(SITE["foundedText"])),
        ("Founders", founders),
        ("Team", f"{len(TEAM['team'])} people, plus a pool of regular collaborators"),
        ("Website", f'<a href="{BASE}">{BASE.replace("https://", "")}</a>'),
        ("Press contact", f'<a href="mailto:{SITE["email"]}">{SITE["email"]}</a>'),
        ("Company number", f'{e(SITE["companyNumber"])} ({e(SITE["registeredIn"])})'),
    ])


def socials():
    """The footer's Elsewhere list: Discord, then every account in site.json."""
    links = [("Discord", SITE["discord"])] + [(s["label"], s["url"]) for s in SITE["socials"]]
    return "".join(f'<li><a href="{e(u)}" rel="me">{e(label)}</a></li>' for label, u in links)


def email(text=None):
    return f'<a href="mailto:{SITE["email"]}">{e(text or SITE["email"])}</a>'


def newsletter(button="Keep me posted"):
    return (
        f'<form class="form form--inline" action="{SITE["forms"]["newsletter"]}" method="post" target="_blank">'
        '<div class="field"><label for="nl-email">Your email address</label>'
        '<input id="nl-email" type="email" name="email" autocomplete="email" required></div>'
        '<input type="hidden" name="tag" value="website">'
        f'<button class="btn" type="submit">{e(button)}</button></form>'
        '<p class="form-note mt-m">Sent by Buttondown, who handle the list for us. One click unsubscribes. '
        '<a href="/privacy">How we look after your address</a>.</p>'
    )


def video(name, poster, label, cls=""):
    """A muted game loop with its pause control. Without script it is a still."""
    return (
        f'<video data-loop muted loop playsinline preload="none" poster="{src(poster, 1200)}" '
        f'aria-label="{e(label)}"{f" class={chr(34)}{cls}{chr(34)}" if cls else ""}>'
        f'<source src="/assets/video/{name}.mp4" type="video/mp4"></video>'
        '<button class="play-toggle" type="button" aria-pressed="false" hidden>Pause</button>'
    )


def size(rel):
    n = (ROOT / rel.lstrip("/")).stat().st_size
    return f"{n / 1_048_576:.1f} MB" if n > 1_048_576 else f"{max(1, round(n / 1024))} KB"


# ---- Page shell --------------------------------------------------------------

NAV = [
    ("Out of Water", "/out-of-water", "game"),
    ("Co-development", "/co-development", "codev"),
    ("Team", "/team/", "team"),
    ("News", "/news", "news"),
    ("Careers", "/careers", "careers"),
    ("Press", "/press", "press"),
]

CSP = (
    "default-src 'self'; script-src 'self' https://gc.zgo.at; style-src 'self'; "
    "img-src 'self' data: https://oliverneal04.goatcounter.com; font-src 'self'; media-src 'self'; "
    "connect-src 'self' https://formspree.io https://oliverneal04.goatcounter.com; "
    "form-action https://formspree.io https://buttondown.com; frame-src 'none'; "
    "base-uri 'none'; object-src 'none'"
)


def nav_list(current, with_contact=False):
    items = [(label, href, key) for label, href, key in NAV]
    if with_contact:
        items.append(("Contact", "/contact", "contact"))
    lis = "".join(
        f'<li><a href="{href}"{" aria-current=" + chr(34) + "page" + chr(34) if key == current else ""}>{label}</a></li>'
        for label, href, key in items
    )
    return f"<ul>{lis}</ul>"


def schema_org():
    founders = group_members("founders")
    return {
        "@type": "Organization",
        "@id": f"{BASE}/#studio",
        "name": SITE["name"],
        "legalName": SITE["legalName"],
        "url": f"{BASE}/",
        "logo": f"{BASE}/assets/brand/shiverbug-logo-on-blue.png",
        "email": SITE["email"],
        "foundingDate": SITE["founded"],
        "founder": [{"@type": "Person", "name": p["name"], "url": f"{BASE}{url(p)}"} for p in founders],
        "address": {
            "@type": "PostalAddress",
            "streetAddress": "Victoria Building, Victoria Road",
            "addressLocality": "Middlesbrough",
            "postalCode": "TS1 3AP",
            "addressCountry": "GB",
        },
        "identifier": {"@type": "PropertyValue", "propertyID": "Companies House", "value": SITE["companyNumber"]},
        "sameAs": [s["url"] for s in SITE["socials"]],
    }


def schema_game():
    return {
        "@type": "VideoGame",
        "@id": f"{BASE}/out-of-water#game",
        "name": SITE["game"]["name"],
        "url": f"{BASE}/out-of-water",
        "description": "A two player split screen 3D platformer collectathon. One player is Koopa, a turtle; the other is Kiko, a seagull.",
        "genre": ["Platformer", "Collectathon"],
        "gamePlatform": "PC",
        "playMode": ["CoOp", "SinglePlayer"],
        "numberOfPlayers": {"@type": "QuantitativeValue", "minValue": 1, "maxValue": 2},
        "author": {"@id": f"{BASE}/#studio"},
        "image": f"{BASE}/assets/img/og/out-of-water.jpg",
    }


def json_ld(*things):
    graph = {"@context": "https://schema.org", "@graph": list(things)}
    text = json.dumps(graph, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
    return f'<script type="application/ld+json">{text}</script>'


LAYOUT = (ROOT / "src" / "layout.html").read_text(encoding="utf-8")
TOKEN = re.compile(r"\{\{(.+?)\}\}", re.S)


def render(text, ctx):
    # Literal copy gets curly apostrophes; what the expressions produce is
    # left alone, so a tagline or bio is never touched.
    text = "".join(typo_html(p) if i % 2 == 0 else "{{" + p + "}}" for i, p in enumerate(TOKEN.split(text)))

    def run(m):
        try:
            return str(eval(m.group(1).strip(), {"__builtins__": {}}, ctx))
        except Exception as err:
            raise RuntimeError(f"in {{{{{m.group(1).strip()}}}}}: {err}") from err

    return TOKEN.sub(run, text)


def helpers():
    names = [
        "img", "sticker", "full", "src", "srcset", "people_grid", "faces", "crew", "count", "gallery", "service",
        "discipline_cards", "log", "game_facts", "studio_facts", "socials", "email", "newsletter", "video",
        "size", "e", "url", "first", "side_tag", "group_members", "piece", "news", "latest_posts",
    ]
    ctx = {n: globals()[n] for n in names}
    ctx.update(SITE=SITE, NEWS=NEWS, BY_SLUG=BY_SLUG, len=len)
    return ctx


def page(meta, body):
    path = meta["path"]
    title = typo(meta["title"] if meta.get("bare_title") else f"{meta['title']} | {SITE['name']}")
    og = meta.get("og", "/assets/img/og/studio.jpg")
    graph = [schema_org()] if meta.get("schema") in ("studio", "game") else []
    if meta.get("schema") == "game":
        graph.append(schema_game())
    if meta.get("person"):
        graph = [meta["person"]]
    ctx = helpers()
    ctx.update(
        title=e(title),
        description=e(typo(meta["description"])),
        canonical=f"{BASE}{path}",
        og_image=f"{BASE}{og}",
        og_type=meta.get("og_type", "website"),
        robots='<meta name="robots" content="noindex">' if meta.get("noindex") else "",
        csp=CSP,
        css=versioned("/assets/css/site.min.css"),
        js=versioned("/assets/js/site.js"),
        nav=nav_list(meta.get("nav")),
        contact_current=' aria-current="page"' if meta.get("nav") == "contact" else "",
        menu=nav_list(meta.get("nav"), with_contact=True),
        schema=json_ld(*graph) if graph else "",
        body=body,
        analytics=SITE["analytics"],
    )
    return render(LAYOUT, ctx)


def front_matter(text):
    m = re.match(r"---\n(.*?)\n---\n", text, re.S)
    meta = {}
    for line in m.group(1).splitlines():
        if line.strip():
            k, v = line.split(":", 1)
            v = v.strip()
            meta[k.strip()] = {"true": True, "false": False}.get(v, v)
    return meta, text[m.end():]


# ---- Profiles ----------------------------------------------------------------


def bio(paragraph):
    # Links between profiles are written as the other person's file name.
    return re.sub(r"href='([a-z-]+)\.html'", r'href="/team/\1"', paragraph)


def profile(p, prev, nxt):
    former = p.get("status") == "former"
    s = side(p)
    stick = sticker(s[0], sizes="130px") if s else ""
    kind = "Co-founder" if p.get("founder") else ("Talent pool" if p in TEAM["talent"] else "On the team")
    pron = f" <span>({e(p['pronouns'])})</span>" if p.get("pronouns") else ""
    about = "".join(f"<p>{bio(x)}</p>" for x in p["about"])
    links = ""
    if p.get("socials"):
        links = '<ul class="links">' + "".join(
            f'<li><a href="{e(x["url"])}" rel="me noopener">{e(x["label"])}</a></li>' for x in p["socials"]
        ) + "</ul>"
    work = ""
    if not former and pieces_for(by=p["slug"]):
        work = f'<section class="mt-l" aria-labelledby="work-title"><h2 id="work-title" class="small-heading">Work by {e(first(p))}</h2><div class="mt-m">{gallery(by=p["slug"])}</div></section>'
    tags = side_tag(p) + alumni_tag(p)
    pager = '<nav class="pager" aria-label="More people">'
    if prev:
        pager += f'<a href="{url(prev)}"><small>Previous</small>{e(prev["name"])}</a>'
    if nxt:
        pager += f'<a class="pager__next" href="{url(nxt)}"><small>Next</small>{e(nxt["name"])}</a>'
    pager += "</nav>"
    photo = img(f"team/{p['slug']}", f"{p['name']}", sizes="(min-width: 56em) 34vw, 92vw", eager=True, near=640)
    body = f"""<main id="main">
<div class="band band--tight"><div class="wrap">
<nav class="crumbs" aria-label="Breadcrumb"><a href="/team/">Team</a> / {e(p["name"])}</nav>
<article class="profile mt-m">
<div class="profile__photo"><div class="frame">{photo}</div>{stick}</div>
<div class="profile__body">
<p class="overline">{kind}</p>
<h1>{e(p["name"])}</h1>
<p class="profile__role">{e(p["role"])}{pron}</p>
<blockquote class="said"><p>{e(p["tagline"])}</p></blockquote>
<div class="prose">{about}</div>
{tags}
{links}
{work}
</div>
</article>
{pager}
</div></div>
</main>"""
    first_sentence = re.split(r"(?<=[.!?])\s", re.sub(r"<[^>]+>", "", p["about"][0]))[0]
    desc = p.get("metaDescription") or f"{p['name']}, {p['role']} at {SITE['name']}. {first_sentence}"
    person = {
        "@type": "Person",
        "name": p["name"],
        "jobTitle": p["role"],
        "url": f"{BASE}{url(p)}",
        "image": f"{BASE}{full('team/' + p['slug'])}",
        "sameAs": [x["url"] for x in p.get("socials") or []],
        ("alumniOf" if former else "worksFor"): {"@type": "Organization", "name": SITE["name"], "url": f"{BASE}/"},
    }
    if p.get("knowsAbout"):
        person["knowsAbout"] = p["knowsAbout"]
    meta = {
        "title": f"{p['name']}, {p['role'].split(' · ')[0]}",
        "description": desc[:300],
        "path": url(p),
        "nav": "team",
        "og_type": "profile",
        "person": person,
    }
    return page(meta, body)


# ---- Small files --------------------------------------------------------------


def redirect(to, title):
    return f"""<!doctype html>
<html lang="en-GB">
<head>
<meta charset="utf-8">
<title>{e(title)} | {SITE["name"]}</title>
<meta name="robots" content="noindex">
<meta http-equiv="refresh" content="0; url={to}">
<link rel="canonical" href="{BASE}{to}">
</head>
<body>
<p>This page has moved to <a href="{to}">{BASE.replace("https://", "")}{to}</a>.</p>
</body>
</html>
"""


def legacy_people():
    mapping = {p["id"]: p["slug"] for p in PEOPLE if listed(p)}
    return f"""<!doctype html>
<html lang="en-GB">
<head>
<meta charset="utf-8">
<title>Team | {SITE["name"]}</title>
<meta name="robots" content="noindex">
<meta http-equiv="Content-Security-Policy" content="{CSP}">
<link rel="canonical" href="{BASE}/team/">
<script src="{versioned('/assets/js/site.js')}" defer></script>
</head>
<body data-legacy-people="{e(json.dumps(mapping, separators=(',', ':')))}">
<p>Profiles have moved. <a href="/team/">Everyone at Shiverbug is on the team page.</a></p>
</body>
</html>
"""


def minify_css():
    css = (ROOT / "assets" / "css" / "site.css").read_text(encoding="utf-8")
    css = re.sub(r"/\*.*?\*/", "", css, flags=re.S)
    css = re.sub(r"\s+", " ", css)
    css = re.sub(r"\s*([{};,])\s*", r"\1", css)
    css = re.sub(r":\s+", ":", css)
    css = css.replace(";}", "}").strip()
    # None of the rules above touch the space before a colon, so a descendant
    # pseudo-class like ".band--deep :focus-visible" survives intact.
    write("assets/css/site.min.css", css + "\n")


def press_zips():
    readme = f"""{SITE['legalName']}
{BASE}

Press contact: {SITE['email']}

Everything in this archive is free to use in coverage of {SITE['name']} and
{SITE['game']['name']}. Please don't alter the logo. Screenshots are work in
progress and can be credited to {SITE['name']}.

Fact sheet, descriptions and the latest of all of this: {BASE}/press
"""
    groups = {
        "logos": sorted((ROOT / "assets" / "brand").glob("*")),
        "screenshots": [ROOT / "source" / "game" / n for n in ("cove.jpg", "hats.jpg", "title-scene.jpg")]
        + sorted((ROOT / "source" / "photos").glob("*.jpg")),
        "characters": [ROOT / "source" / "stickers" / "koopa.png", ROOT / "source" / "stickers" / "kiko.png"],
        "video": [ROOT / "assets" / "video" / "out-of-water-trailer.mp4", ROOT / "assets" / "video" / "title-loop.mp4"],
    }
    kits = {
        "shiverbug-logos.zip": ["logos"],
        "shiverbug-screenshots.zip": ["screenshots"],
        "shiverbug-press-kit.zip": ["logos", "screenshots", "characters", "video"],
    }
    rename = {"out-of-water-trailer.mp4": "koopa-and-kiko-prototype-trailer-2025.mp4"}
    for zipname, parts in kits.items():
        entries = [("README.txt", readme.encode("utf-8"))]
        for part in parts:
            for f in groups[part]:
                data = f.read_bytes()
                if f.suffix in (".svg", ".txt"):
                    data = lf(data)
                entries.append((f"{part}/{rename.get(f.name, f.name)}", data))
        buf = __import__("io").BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_STORED) as z:
            for name, data in sorted(entries):
                info = zipfile.ZipInfo(name, date_time=(2025, 5, 30, 0, 0, 0))
                info.external_attr = 0o644 << 16
                info.create_system = 3
                z.writestr(info, data)
        write(f"assets/press/{zipname}", buf.getvalue(), binary=True)


def llms():
    lines = [
        f"# {SITE['name']}",
        "",
        f"> An independent games studio in {SITE['town']}, {SITE['region']}, founded in {SITE['foundedText']}. "
        f"We are making {SITE['game']['name']}, a two-player split-screen 3D platformer collectathon, and we take on "
        "co-development work: concept art, stylised and hard-surface 3D, level design and gameplay programming.",
        "",
        f"Contact: {SITE['email']}",
        "",
        "## Pages",
        f"- [{SITE['game']['name']}]({BASE}/out-of-water): the game, its two heroes, and how to follow it",
        f"- [Co-development]({BASE}/co-development): what we make for other studios, who makes it, and how to start",
        f"- [Team]({BASE}/team/): everyone at the studio, in their own words",
        f"- [News]({BASE}/news): the studio's LinkedIn posts, with links to each one",
        f"- [Careers]({BASE}/careers): how people join us, mostly through Teesside University",
        f"- [Press kit]({BASE}/press): fact sheet, descriptions, logos and screenshots",
        f"- [Contact]({BASE}/contact)",
        "",
        "## The game",
        f"- Name: {SITE['game']['name']}",
        f"- Genre: {SITE['game']['genre']}",
        f"- Players: {SITE['game']['players']}",
        f"- Engine: {SITE['game']['engine']}",
        f"- Platform: {SITE['game']['platforms']}",
        f"- Status: {SITE['game']['status']}; release date and price not announced",
        "",
        "## People",
    ]
    for p in PEOPLE:
        if listed(p):
            note = " (talent pool, Shiverbug alumni)" if p.get("status") == "former" else (" (talent pool)" if p in TEAM["talent"] else "")
            lines.append(f"- [{p['name']}]({BASE}{url(p)}): {p['role']}{note}")
    lines += ["", f"{SITE['legalName']}, company number {SITE['companyNumber']}, registered in {SITE['registeredIn']}."]
    write("llms.txt", "\n".join(lines) + "\n")


# ---- Run ---------------------------------------------------------------------


def main():
    minify_css()
    press_zips()  # before the pages, which state the archive sizes
    sitemap = []

    for source in sorted((ROOT / "src" / "pages").glob("*.html")):
        meta, body = front_matter(source.read_text(encoding="utf-8"))
        body = render(body, helpers())
        write(meta["file"], page(meta, body))
        if not meta.get("noindex") and meta.get("sitemap") is not False:
            sitemap.append(meta["path"])

    shown = [p for p in PEOPLE if listed(p)]
    for i, p in enumerate(shown):
        write(f"team/{p['slug']}.html", profile(p, shown[i - 1] if i else None, shown[i + 1] if i + 1 < len(shown) else None))
        sitemap.append(url(p))

    for old, new, title in [
        ("games.html", "/out-of-water", "Out of Water"),
        ("co-dev.html", "/co-development", "Co-development"),
        ("join.html", "/careers", "Careers"),
    ]:
        write(old, redirect(new, title))
    write("team-member.html", legacy_people())

    write("sitemap.xml", '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
          + "".join(f"  <url><loc>{BASE}{p}</loc></url>\n" for p in sitemap) + "</urlset>\n")
    write("robots.txt", f"User-agent: *\nAllow: /\n\nSitemap: {BASE}/sitemap.xml\n")
    llms()

    # Profiles of people who have left the data, or pages whose source went.
    for f in (ROOT / "team").glob("*.html"):
        rel = f"team/{f.name}"
        if rel not in written:
            f.unlink()
            print("removed", rel)

    print(f"built {len(written)} files")


if __name__ == "__main__":
    main()
