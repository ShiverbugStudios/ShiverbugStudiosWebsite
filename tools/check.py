"""Check the built site before it ships.

    python tools/check.py

Exits non-zero on any problem, so CI can gate on it. For every published page
it checks: one h1, a title, a description, a canonical, the company details the
Companies Act asks for, alt text on every image, no inline style or script
(the Content Security Policy would block them in the browser and nothing else
would tell you), structured data that parses, and that every internal link,
image, srcset candidate, poster and in-page anchor points at something real,
resolved the way GitHub Pages resolves it.

It also holds the studio's own copy to the house rule of no em dashes. The
people's bios and taglines are exempt: those are theirs.
"""

import json
import re
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
PRIVATE = {"source", "src", "data", "tools", ".github", ".claude", ".git", "node_modules"}
REDIRECTS = {"games.html", "co-dev.html", "join.html", "team-member.html"}
problems = []


def fail(page, message):
    problems.append(f"{page}: {message}")


class Page(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.refs = []  # (attribute, value)
        self.ids = set()
        self.h1 = 0
        self.title = False
        self.description = False
        self.canonical = False
        self.images_without_alt = 0
        self.inline_styles = 0
        self.inline_scripts = 0
        self.jsonld = []
        self._in = None
        self._buf = ""
        self.text = []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if "id" in a:
            self.ids.add(a["id"])
        if "style" in a:
            self.inline_styles += 1
        if tag == "h1":
            self.h1 += 1
        if tag == "title":
            self.title = True
        if tag == "meta" and a.get("name") == "description" and a.get("content"):
            self.description = True
        if tag == "link" and a.get("rel") == "canonical":
            self.canonical = True
        if tag == "img" and "alt" not in a:
            self.images_without_alt += 1
        if tag == "script":
            if a.get("type") == "application/ld+json":
                self._in, self._buf = "jsonld", ""
            elif "src" not in a:
                self.inline_scripts += 1
        for attr in ("href", "src", "poster"):
            if a.get(attr):
                self.refs.append((attr, a[attr]))
        if a.get("srcset"):
            for candidate in a["srcset"].split(","):
                self.refs.append(("srcset", candidate.strip().split(" ")[0]))

    def handle_endtag(self, tag):
        if tag == "script" and self._in == "jsonld":
            self.jsonld.append(self._buf)
            self._in = None

    def handle_data(self, data):
        if self._in == "jsonld":
            self._buf += data
        else:
            self.text.append(data)


def resolve(path):
    """The file GitHub Pages would serve for a site path, or None."""
    rel = unquote(path).lstrip("/")
    first = rel.split("/", 1)[0]
    if first in PRIVATE or first.startswith("_"):
        return None
    target = ROOT / rel
    if path.endswith("/") or rel == "":
        target = target / "index.html"
        return target if target.is_file() else None
    if target.is_file():
        return target
    if target.with_name(target.name + ".html").is_file():
        return target.with_name(target.name + ".html")
    if (target / "index.html").is_file():
        return target / "index.html"
    return None


def site_path(file):
    rel = file.relative_to(ROOT).as_posix()
    if rel.endswith("index.html"):
        return "/" + rel[: -len("index.html")]
    return "/" + rel


pages = [
    f for f in ROOT.rglob("*.html")
    if not (set(f.relative_to(ROOT).parts[:-1]) & PRIVATE) and not f.relative_to(ROOT).parts[0].startswith("_")
]
parsed = {}
for f in pages:
    p = Page()
    p.feed(f.read_text(encoding="utf-8"))
    parsed[f] = p

for f, p in parsed.items():
    name = f.relative_to(ROOT).as_posix()
    here = site_path(f)
    if name not in REDIRECTS:
        if p.h1 != 1:
            fail(name, f"has {p.h1} h1 elements, wants exactly one")
        if not p.title:
            fail(name, "no <title>")
        if not p.description:
            fail(name, "no meta description")
        if not p.canonical and name != "404.html":
            fail(name, "no canonical link")
        body = "".join(p.text)
        if "16485763" not in body or "Registered office" not in body:
            fail(name, "footer is missing the company number or registered office")
    if p.images_without_alt:
        fail(name, f"{p.images_without_alt} image(s) without an alt attribute")
    if p.inline_styles:
        fail(name, f"{p.inline_styles} inline style attribute(s); the CSP blocks them")
    if p.inline_scripts:
        fail(name, f"{p.inline_scripts} inline script(s); the CSP blocks them")
    for block in p.jsonld:
        try:
            json.loads(block)
        except ValueError as err:
            fail(name, f"structured data does not parse: {err}")

    for attr, ref in p.refs:
        parts = urlsplit(ref)
        if parts.scheme in ("http", "https", "mailto", "tel", "data") or ref.startswith("//"):
            continue
        path = parts.path
        if not path:  # "#anchor" on this page
            if parts.fragment and parts.fragment not in p.ids:
                fail(name, f"link to #{parts.fragment}, which is not on the page")
            continue
        if not path.startswith("/"):
            path = here.rsplit("/", 1)[0] + "/" + path
        target = resolve(path)
        if target is None:
            fail(name, f"{attr} {ref} points at nothing")
            continue
        if parts.fragment and target in parsed and parts.fragment not in parsed[target].ids:
            fail(name, f"link to {ref}, but that page has no #{parts.fragment}")

# House style: the studio's own words carry no em dashes.
for f in list((ROOT / "src").rglob("*.html")) + [ROOT / "data" / "site.json", ROOT / "data" / "work.json"]:
    for i, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
        if "—" in line:
            fail(f.relative_to(ROOT).as_posix(), f"line {i} has an em dash")

if problems:
    print("\n".join(problems))
    print(f"\n{len(problems)} problem(s) in {len(pages)} pages")
    sys.exit(1)
print(f"{len(pages)} pages checked, no problems")
