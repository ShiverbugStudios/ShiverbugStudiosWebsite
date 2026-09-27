# Shiverbug Studios website

The site at [shiverbugstudios.com](https://shiverbugstudios.com): the studio,
*Out of Water*, co-development, the team, careers and the press kit.

Static HTML built by a Python script, a hand-written stylesheet and one small
script. No framework and no `node_modules`. GitHub Pages serves this
repository as it is, so the built pages are committed.

## Working on it

```bash
python tools/build.py      # build every page from src/ and data/
python tools/check.py      # links, headings, alt text, CSP rules, structured data
python tools/serve.py      # preview at http://localhost:5173, served the way Pages serves it
```

The build and the checker need nothing but Python 3.10 or later. CI runs both
on every push and pull request, and fails if the committed pages differ from
what the build produces, so always commit the build output with the change
that caused it.

## Where things live

| Path | What it is | Published? |
| --- | --- | --- |
| `src/layout.html` | The page shell: head, header, footer | No |
| `src/pages/*.html` | One file per page: front matter, then the page | No |
| `data/team.json` | Everyone on the site, and their words | No |
| `data/work.json` | Disciplines and portfolio pieces for co-development | No |
| `data/site.json` | Studio facts, socials, form endpoints, the dated log on the home page | No |
| `data/news.json` | The News page: the studio's LinkedIn posts, linked back to LinkedIn | No |
| `data/images.json` | Written by `tools/images.py`: every image and its sizes | No |
| `source/` | Master images the site's WebP files are made from | No |
| `assets/css/site.css` | The stylesheet. Edit this one; the build writes `site.min.css` | Yes |
| `assets/js/site.js` | Video pause controls, the work viewer, the contact form | Yes |
| `assets/img/` | Generated WebP images. Never edit by hand | Yes |
| `assets/brand/` | The logo in every colourway, plus the header lockups | Yes |
| `assets/press/*.zip` | Press archives, written by the build | Yes |
| `*.html`, `team/*.html`, `sitemap.xml`, `llms.txt`, `robots.txt` | Written by the build | Yes |

`_config.yml` is what keeps `source/`, `src/`, `data/` and `tools/` off the
public site. GitHub Pages runs Jekyll over the repository, and that file's
`exclude` list is the only thing between those folders and a public URL.
Anything else you commit is published, so notes about the site do not live in
this repository.

## Common jobs

**Change someone's details.** Edit `data/team.json` and rebuild. The `tagline`
and `about` fields are the person's own words: never rewrite them, not even to
fix a typo, without asking them. The build deliberately leaves them untouched
(the curly-apostrophe pass that tidies the studio's own copy skips them).

**Add a person.** Put their photo in `source/team/`, add them to
`data/team.json` (the `_readme` key lists every field), then run
`python tools/images.py` to cut the portrait and `python tools/build.py`. If
the framing is off, give them a `crop` of `[left, top, width]` as fractions of
the photo and run `tools/images.py` again; it notices a changed crop. Aim for
what the others have: the face centred, its middle about 42% of the way down,
and about a third of the frame wide, or as close as the photo allows.

**Someone leaves.** Move them to `talent` with `"status": "former"`. They stay
in the talent pool on the team page with a Shiverbug alumni badge (Shana the
moth, `assets/brand/moth-ink.svg`, which `tools/logo.py` writes), their
structured data says `alumniOf`, and their pieces drop out of the
co-development galleries on their own, because that page promises the work is
by people you can hire through us.

**Add a portfolio piece.** Put the image in `source/work/`, add an entry to
`data/work.json` (credited to one person, filed under one discipline, with alt
text), run `python tools/images.py`, then build. Client work never goes on the
site.

**Add an entry to the log on the home page.** Add it to `log` in
`data/site.json`. A photo is optional and needs an image in `data/images.json`.

**Add a LinkedIn post to News.** Add it to `data/news.json`: the number from
the post's `feed/update/urn:li:activity:<id>` address, our headline, and a
short extract copied exactly from the post. The date is worked out from the
id. To show the post's picture, save it as `source/news/<id>.jpg` and run
`python tools/images.py`. The newest three also appear on the home page.

**Change a page.** Edit its file in `src/pages/`. Inside a page, `{{ ... }}` is
a call to one of the helpers at the bottom of `tools/build.py`, for example
`{{ img("game/cove", "alt text", sizes="50vw") }}`, `{{ people_grid("founders") }}`
or `{{ email() }}`.

## Images

`tools/images.py` makes every image the site serves from the masters in
`source/`, at several widths, as WebP, and records them in `data/images.json`.
It needs Pillow and fontTools (`pip install pillow fonttools brotli`). It only
redoes what changed; `--force` redoes everything, including the social cards
in `assets/img/og/` and the icons in `assets/icons/`.

The stickers (Koopa, Kiko and the crabs with a white die-cut border) are made
from the game's own UI icons and from renders of the prefabs in the Unity
project, taken from the Out of Water wiki. `tools/images.py` adds the border.

## Design notes

The reasoning is at the top of `assets/css/site.css`, and it is worth reading
before changing the look. In short:

- **The colours are the game's.** Ink is the outline colour Out of Water draws
  round its title and UI text, cream is its UI text colour, gold is its "you
  are here" colour, and the deep sea tones are its menu surfaces. Cyan is the
  logo's.
- **Buttons are the game's menu tiles**, a flat fill with a darker bottom edge
  that disappears when pressed. Nothing else gets that edge.
- **Headings are Fraunces, fully soft; text is Instrument Sans.** Both are
  self-hosted, so no page contacts Google.
- **Nothing moves on its own** apart from the game footage, which has a pause
  button and does not play for anyone who has asked for reduced motion.
- **Copy has no em dashes**, the same house rule as the wiki. `tools/check.py`
  enforces it in `src/` and in `data/site.json` and `data/work.json`.

## Hosting

GitHub Pages, from the root of `main`, on the custom domain in `CNAME`. Pages
serves `out-of-water.html` at `/out-of-water`, which is the address every
link uses. The old addresses (`games.html`, `co-dev.html`, `join.html`,
`team-member.html?p=...`) are small redirect pages written by the build so
old links keep working.

## Licence

The code is free to learn from. The Shiverbug Studios name, logo, the Out of
Water characters, artwork, screenshots and team photographs are © Shiverbug
Studios Ltd or the people who made them, and are not licensed for reuse.
