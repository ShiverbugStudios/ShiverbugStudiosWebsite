# tools

Three PowerShell scripts. The two that run in CI need nothing installed: they
use the Windows PowerShell that's already on the machine. The third,
`make-variants.ps1`, resizes images and is the one exception. See below.

**Order matters when you add art:**

```powershell
powershell -ExecutionPolicy Bypass -File tools/make-variants.ps1   # only if images changed
powershell -ExecutionPolicy Bypass -File tools/build-team.ps1
powershell -ExecutionPolicy Bypass -File tools/validate-site.ps1
```

## build-team.ps1

`data/team.json` is the single source of truth for everyone at the studio.
This script reads it and writes:

| Output | What it is |
| --- | --- |
| `team/<slug>.html` | One real, crawlable page per person |
| `team/index.html` | The team hub at `/team/` |
| `index.html` | The team grid and the talent-pool line, between the `BUILD:TEAM` / `BUILD:TALENT` markers |
| `index.html` | Structured data graph, between the `BUILD:SCHEMA` markers |
| `team-member.html` | Legacy `?p=` redirect map and no-JS fallback list |
| `llms.txt` | Curated plain-text site map for AI agents |
| `sitemap.xml` | Every indexable URL |

```powershell
powershell -ExecutionPolicy Bypass -File tools/build-team.ps1
```

**To add or change someone:** edit `data/team.json`, run the script, commit
the result. Never hand-edit anything in `team/`, or the `BUILD:` blocks in
`index.html`. The next build overwrites them.

Notes:
- Bio paragraphs may contain HTML. Links to other profiles are sibling-relative,
  e.g. `<a href='lewis-mennim.html'>Lewis</a>`, because they render inside `team/`.
- `role` keeps `· Co-Founder`; the badge shows it, the role line strips it.
- Keep this file **pure ASCII**. Windows PowerShell 5.1 reads a BOM-less `.ps1`
  as ANSI, so a literal middot or em dash character in the source arrives mangled. Use
  `[char]0x00B7` or an HTML entity instead.

## make-variants.ps1

Writes `assets/.../<name>-<width>.<ext>` next to each source image. Every
`srcset` on the site is built from what this leaves on disk, so a full-size
photo is never sent to a 130px thumbnail.

```powershell
powershell -ExecutionPolicy Bypass -File tools/make-variants.ps1
powershell -ExecutionPolicy Bypass -File tools/make-variants.ps1 -Only codev-3d
```

It skips variants that already exist, so re-running it is cheap; pass `-Force`
to rebuild. A variant that comes out no smaller than its source is discarded
rather than committed, because the browser would pick it on a narrow screen and
download *more*.

Notes:
- **This is the one script that needs something installed**: the .NET SDK. It
  builds a throwaway console app in `%TEMP%` against SixLabors.ImageSharp. CI
  does not run it, and variants are committed like any other asset.
- The width list per image group lives at the top of the script. Two team widths
  are conditional and are read from where the condition actually lives: `640`
  from the `is-zoomed` entries in `data/team.json`, `160` from the avatar chips
  in `co-dev.html`. Nothing generates a file no page can request.
- **It cannot resize animated GIFs**. ImageSharp flattens them to one frame.
  `assets/img/art/codev-char-shell-sockets.gif` is therefore still full size at
  1.8 MB, and wants converting to a silent looping MP4 with ffmpeg instead.

**After adding art:** run this, then `build-team.ps1`, then `validate-site.ps1`.
The validator checks every `srcset` candidate resolves, so a missing variant
fails the build instead of 404ing on one screen size in production.

## validate-site.ps1

Checks every `.html` in the repo and exits non-zero on failure, so CI can gate
on it:

- internal links and asset references resolve to real files
- exactly one `<h1>`, plus a title, description and `lang`
- canonical, `twitter:card` and `og:image` on every indexable page
- every JSON-LD block parses and has an `@type` or `@graph`
- every `srcset` and `imagesrcset` candidate points at a file that exists
- sitemap URLs correspond to real files, and indexable pages are listed
- the analytics tag is present and not commented out

```powershell
powershell -ExecutionPolicy Bypass -File tools/validate-site.ps1
```

## build-css.ps1

Writes `css/style.min.css` from `css/style.css` by stripping comments and blank
space, and nothing else. Every page links the minified file, so run it after any
stylesheet change:

```powershell
powershell -ExecutionPolicy Bypass -File tools/build-css.ps1
```

All three run automatically on push and PR via
`.github/workflows/build-and-validate.yml`, which also fails if the committed
output doesn't match a fresh build.

## Local preview

`.claude/serve.ps1` serves the site at <http://localhost:5173>, including
directory index files so `/team/` resolves the same way GitHub Pages does.
