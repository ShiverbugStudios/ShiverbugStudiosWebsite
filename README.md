# Shiverbug Studios website

The studio site for [Shiverbug Studios](https://shiverbugstudios.com/):
our debut game *Out of Water*, the team, and our co-development services.

Static HTML, CSS and vanilla JavaScript. No framework, no bundler, no
`node_modules`. It is served straight off GitHub Pages, and the tooling is
PowerShell that already ships with Windows.

## Read this before you change anything

**Do not hand-edit the generated files.** These are written by
`tools/build-team.ps1`, and CI fails if what you commit does not match what the
script produces:

| Generated | From |
| --- | --- |
| `team/*.html` (one page per person) | `data/team.json` |
| `team/index.html` (the roster hub) | `data/team.json` |
| The team and talent-pool grids in `index.html`, between the `BUILD:TEAM` / `BUILD:TALENT` markers | `data/team.json` |
| The intake faces in `join.html`, between the `BUILD:JOIN` markers | `data/team.json` |
| The structured-data block in `index.html`, between the `BUILD:SCHEMA` markers | `data/team.json` |
| The roster in `team-member.html`, between the `BUILD:REDIRECT-LIST` markers | `data/team.json` |
| `js/legacy-redirect.js` | `data/team.json` |
| `llms.txt` | `data/team.json` |
| `sitemap.xml` | the page list in the script, plus `dateModified` in `data/team.json` |
| `css/style.min.css` | `css/style.css`, by `tools/build-css.ps1` |

The three press archives in `assets/press/` are generated too, by
`tools/build-press-kit.ps1`, from files already in the repo:

| Generated | Contains |
| --- | --- |
| `shiverbug-press-kit.zip` | brand, screenshots, studio photography, trailer |
| `shiverbug-screenshots.zip` | screenshots and studio photography |
| `shiverbug-logos.zip` | brand only |

Each one's `README.txt` is written by that script, so the press contact and the
site address are stated in exactly one place. Rebuilding without changing an
input produces a byte-identical zip, so `git status` stays quiet.

`data/team.json` is the single source of truth for everyone on the site. Its
`_readme` key documents every field.

Everything else (`index.html` outside the markers, `co-dev.html`, `press.html`,
`privacy.html`, `accessibility.html`, `404.html`, `css/style.css` and the JS) is
written by hand.

**Edit `css/style.css`, never `css/style.min.css`.** Every page links the
minified file, so after touching the stylesheet run:

```bash
powershell -ExecutionPolicy Bypass -File tools/build-css.ps1
```

It only strips comments and blank space, so the two files always describe the
same rules. The source is heavily commented on purpose - those comments are why
the site looks the way it does - and shipping them used to cost every first
visit ~23 KB of render-blocking prose.

## Working on it

Run the build after touching `data/team.json`:

```bash
powershell -ExecutionPolicy Bypass -File tools/build-team.ps1
```

Then the validator, then commit the result:

```bash
powershell -ExecutionPolicy Bypass -File tools/validate-site.ps1
```

The validator checks every page for a single `<h1>`, a title, a description, a
canonical, a CSP tag, the Companies Act footer disclosure, valid JSON-LD, and
that every internal link and every `srcset` candidate resolves to a real file.
It also opens the three press archives and checks that no entry uses a backslash
separator and that each `README.txt` carries the current site address and the
press contact. It exits non-zero, so CI gates on it.

If you touched a logo, a screenshot or the blurb in the press archives, rebuild
them first:

```bash
powershell -ExecutionPolicy Bypass -File tools/build-press-kit.ps1
```

If you added images, run the resizer first:

```bash
powershell -ExecutionPolicy Bypass -File tools/make-variants.ps1
```

That one is the exception to "no dependencies": it needs the .NET SDK, which it
uses to pull ImageSharp into a scratch project. It is a one-off asset step and
CI never runs it. Full order after adding art: **make-variants → build-team →
validate-site**. See `tools/README.md` for the detail.

To preview locally, use the dev server config in `.claude/launch.json`, or serve
the folder with anything that hands out static files.

## Things that will bite you

**Do not add a `.nojekyll` file without thinking.** GitHub Pages runs Jekyll on
this repo, and Jekyll skips any directory whose name starts with `_`. That is
load-bearing: it is what kept `_originals/` (full-resolution team photos and
art, around 145 MB) off the public site while it was still committed. It is
untracked now, so this is no longer a live hazard, but the same trap applies to
anything else parked under an underscore.

**Everything committed here is published.** Pages serves the whole repo at a
guessable URL, so a file dropped in "just to look at" goes public the moment it
is pushed. `.gitignore` blocks the usual suspects; the habit matters more.

This has already happened once. A `docs/` folder of transcribed feedback was
committed and served at `/docs/`, naming individual people and what was wrong
with their photos and their work, with nothing in `robots.txt` to stop a crawler
reading it, and that file explicitly invites every AI and search crawler in.
`docs/` is ignored now. Notes about the site do not live on the site.

**The site address lives in two places.** `$baseUrl` in
`tools/build-team.ps1`, and every absolute reference in `404.html` (which Pages
serves for a missing path at *any* depth, so relative URLs there would resolve
against the wrong directory). The site is on the custom domain's root now, so
those are plain `/...` paths; moving under a sub-path again means updating both.

**One inline script, allowed by hash.** Every page's `<head>` runs
`document.documentElement.classList.add('js')`, which is what lets the
stylesheet hide scroll-reveal content only when script is running. The CSP
allows that exact script by its SHA-256 and nothing else inline. Change a byte of
it and the hash in `$csp` (and the hand-written pages) must change too;
`tools/validate-site.ps1` recomputes it and fails if they disagree.

**Fonts are self-hosted** in `assets/fonts` (both SIL Open Font License), so no
page contacts Google. Don't add a Google Fonts link back: the CSP no longer
allows it, and the privacy policy no longer mentions it.

**Former shiverbugs.** Setting `"status": "former"` on someone in the talent
pool changes more than their badge: their structured data says `alumniOf`
rather than `worksFor`, their search snippet says "former", and their tile
shows a Former chip. Take their work out of the co-dev
galleries by hand at the same time - the page promises those are people you can
hire through us.

**`js/main.js` is one script scope.** It is a classic script, not a module, so a
top-level `const` collides with any other top-level `const` of the same name and
takes the whole file down with a `SyntaxError`. Check the name is free first.

**The site is dark, and there is no light variant.** The stylesheet has one
palette, in a bare `:root` with no `[data-theme]` switch and no JavaScript
behind it. There used to be a toggle; it was removed because a site that is
dark as a *choice* and a site that is dark as a *mode* want different colours,
and trying to be both produced the worst of each. If a light variant ever comes
back, it is a redesign, not a second set of values.

Three things about that palette are easy to undo by accident:

*The surfaces are deep blue, not grey.* Darkening a light palette lands on grey,
and grey reads as a light design with the lights off. Every surface carries the
same cold cast the game does.

*The bands are not separated from the page by lightness.* Four near-blacks
cannot do what cream-against-near-black did, so the hero, proof and footer are
told apart by the teal and sand light bleeding in from their corners, and by the
wave dividers. If those glows get dialled back "because they're strong", the
page flattens into one slab.

*Depth is elevation, not outline.* On paper every card was a white plate behind a
2px near-black rule with the same rule offset below it. Inverted, that is a pale
grey box around everything, which is the single most inverted-looking thing a
dark page can do. Cards are a lighter fill, a one-pixel rim and a soft shadow.
`.sticker` is the one survivor of the old idiom, because it is sand on a
photograph rather than a surface on a surface.

`--ink`, `--line` and `--heading` were one token once. They went three separate
ways when the site went dark. Don't collapse them.

**A profile with no `about` text is treated as unfinished.** Its tile stops being
a link, the page gets a `noindex`, it drops out of `sitemap.xml`, and the
prev/next chain steps over it. Fill in `about` in `data/team.json` and all of
that reverses itself on the next build.

## Accessibility

The site targets WCAG 2.2 Level AA and holds itself to the AAA 44×44 target size
throughout. `accessibility.html` is the public statement, including what is not
right yet. Keep it honest when you change behaviour.

## Licence

Code is free to learn from. The Shiverbug Studios name, logo, artwork,
screenshots and team photographs are not: they are © Shiverbug Studios Ltd and
are not licensed for reuse.
