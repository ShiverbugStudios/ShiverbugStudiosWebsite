# ============================================================
# Shiverbug Studios - static site validator
#
# Checks, across every .html file in the repo:
#   - internal links and asset references resolve to real files
#   - each page has exactly one <h1>, a title, a description and a canonical
#   - every JSON-LD block is valid JSON with an @type
#   - sitemap URLs all correspond to files that exist
#   - no page accidentally lost its analytics tag
#
# Exits 1 if anything fails, so CI can gate on it.
#   powershell -ExecutionPolicy Bypass -File tools/validate-site.ps1
# ============================================================

$ErrorActionPreference = 'Stop'

$root    = Split-Path -Parent $PSScriptRoot
$baseUrl = 'https://shiverbugstudios.com'
# The path every site-absolute reference must carry. Was '/ShiverbugStudiosWebsite'
# on the project Pages site; empty now that we serve from the custom domain apex.
$sitePrefix = ([uri]$baseUrl).AbsolutePath.TrimEnd('/')
$errors  = New-Object System.Collections.ArrayList
$warns   = New-Object System.Collections.ArrayList

function Fail([string]$m) { [void]$errors.Add($m) }
function Warn([string]$m) { [void]$warns.Add($m) }

# Google renders roughly this much of a meta description and silently drops the
# rest. Overshooting is not a penalty, it just means the tail never appears -
# which is how this site once shipped snippets ending "BSc (Hons) Games...".
$descLimit = 158

# Walk a parsed JSON-LD tree, recording which @ids this page actually defines
# (an object carrying both @type and @id) and which ones its mainEntity points
# at. Structured data resolves per page, so a mainEntity aimed at an @id that is
# only defined somewhere else leaves the page with no machine-readable statement
# of what it is about. Cross-page refs for supporting nodes (#studio, #website)
# are normal and deliberately not checked here.
function CollectLd($node, $defined, $mainEntities) {
  if ($null -eq $node) { return }
  if (($node -is [System.Collections.IEnumerable]) -and ($node -isnot [string])) {
    foreach ($item in $node) { CollectLd $item $defined $mainEntities }
    return
  }
  if ($node -isnot [PSCustomObject]) { return }
  $names = @($node.PSObject.Properties.Name)
  if (($names -contains '@id') -and ($names -contains '@type')) {
    [void]$defined.Add([string]$node.'@id')
  }
  if ($names -contains 'mainEntity') {
    $me = $node.'mainEntity'
    if ($me -is [PSCustomObject]) {
      $meNames = @($me.PSObject.Properties.Name)
      if (($meNames -contains '@id') -and ($meNames -notcontains '@type')) {
        [void]$mainEntities.Add([string]$me.'@id')
      }
    }
  }
  foreach ($p in $node.PSObject.Properties) { CollectLd $p.Value $defined $mainEntities }
}

# Pages that are deliberately not indexed and so need no canonical.
$noIndex = @('404.html', 'team-member.html')

$htmlFiles = Get-ChildItem -Path $root -Filter *.html -Recurse |
             Where-Object { $_.FullName -notmatch '\\_originals\\' -and $_.FullName -notmatch '\\.git\\' }

Write-Host "Validating $($htmlFiles.Count) HTML files..." -ForegroundColor Cyan

foreach ($f in $htmlFiles) {
  $rel  = $f.FullName.Substring($root.Length + 1).Replace('\', '/')
  $html = Get-Content $f.FullName -Raw -Encoding UTF8
  $dir  = $f.Directory.FullName

  # ---- head essentials ----
  $h1Count = ([regex]::Matches($html, '<h1[\s>]')).Count
  if ($h1Count -ne 1) { Fail "$rel : expected exactly 1 <h1>, found $h1Count" }

  if ($html -notmatch '<title>[^<]{5,}</title>') { Fail "$rel : missing or empty <title>" }
  if ($html -notmatch 'name="description"\s+content="[^"]{30,}"') { Fail "$rel : missing or too-short meta description" }
  if ($html -notmatch 'lang="en-GB"') { Fail "$rel : <html> missing lang=en-GB" }

  $isNoIndex = ($noIndex -contains $rel) -or ($html -match 'name="robots"\s+content="noindex')
  if (-not $isNoIndex) {
    if ($html -notmatch 'rel="canonical"')            { Fail "$rel : missing rel=canonical" }
    if ($html -notmatch 'name="twitter:card"')        { Fail "$rel : missing twitter:card" }
    if ($html -notmatch 'property="og:image"')        { Fail "$rel : missing og:image" }
  }

  if ($html -notmatch 'goatcounter') { Warn "$rel : no analytics tag" }
  if ($html -match '<!--\s*<script data-goatcounter') { Fail "$rel : analytics tag is still commented out" }

  # ---- security + legal boilerplate that must not drift between pages ----
  if ($html -notmatch 'http-equiv="Content-Security-Policy"') {
    Fail "$rel : missing the Content-Security-Policy meta tag"
  }
  if ($html -notmatch 'company no\. 16485763') {
    Fail "$rel : missing the Companies Act trading disclosure in the footer"
  }
  # An inline <script> is blocked by our own CSP unless the policy names its exact
  # hash. JSON-LD is data, not script, and is left alone. Everything else must be
  # hashed in this page's own CSP, which catches both a new inline script nobody
  # allowed and an edit to the allowed one that forgot to move the hash.
  $cspMatch = [regex]::Match($html, 'http-equiv="Content-Security-Policy"\s+content="([^"]*)"')
  $cspText = if ($cspMatch.Success) { $cspMatch.Groups[1].Value } else { '' }
  foreach ($m in [regex]::Matches($html, '(?s)<script(?![^>]*\ssrc=)([^>]*)>(.*?)</script>')) {
    if ($m.Groups[1].Value -match 'application/ld\+json') { continue }
    $sha = [Security.Cryptography.SHA256]::Create()
    $digest = [Convert]::ToBase64String($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($m.Groups[2].Value)))
    if (-not $cspText.Contains("'sha256-$digest'")) {
      Fail "$rel : inline <script> is not allowed by the page's own CSP (its hash is sha256-$digest) - move it to a .js file or add the hash"
    }
  }
  if ($cspText -match 'fonts\.(googleapis|gstatic)\.com') {
    Fail "$rel : CSP still allows Google Fonts - the fonts are self-hosted in assets/fonts"
  }

  # ---- JSON-LD blocks parse ----
  # Several blocks per page is valid and this site uses that: the hand-written
  # graph plus whatever tools/build-team.ps1 injects. They are collected together
  # so an @id defined in one block satisfies a reference in another.
  $ldDefined = New-Object System.Collections.ArrayList
  $ldMain    = New-Object System.Collections.ArrayList
  foreach ($m in [regex]::Matches($html, '(?s)<script type="application/ld\+json">(.*?)</script>')) {
    $raw = $m.Groups[1].Value
    try {
      $obj = $raw | ConvertFrom-Json
      $hasType = $obj.PSObject.Properties.Name -contains '@type'
      $hasGraph = $obj.PSObject.Properties.Name -contains '@graph'
      if (-not ($hasType -or $hasGraph)) { Fail "$rel : JSON-LD block has neither @type nor @graph" }
      CollectLd $obj $ldDefined $ldMain
    } catch {
      Fail "$rel : JSON-LD does not parse - $($_.Exception.Message)"
    }
  }
  foreach ($me in ($ldMain | Sort-Object -Unique)) {
    if ($ldDefined -notcontains $me) {
      Fail "$rel : mainEntity points at $me, which no JSON-LD block on this page defines"
    }
  }

  # ---- search snippet quality ----
  if (-not $isNoIndex) {
    $dm = [regex]::Match($html, 'name="description"\s+content="([^"]*)"')
    if ($dm.Success) {
      $desc = $dm.Groups[1].Value
      if ($desc.Length -gt $descLimit) {
        Fail "$rel : meta description is $($desc.Length) chars, past the $descLimit Google renders"
      }
      if ($desc -match '\.\.\.\s*$') {
        Fail "$rel : meta description trails off in an ellipsis - it needs to be a whole sentence (set metaDescription in data/team.json for a profile)"
      }
    }
    # The footer row is the only place the site links its own profiles, and
    # sameAs on its own is a claim with nothing backing it in the markup.
    if ($html -notmatch 'class="footer__socials"') {
      Warn "$rel : no footer social row - add the BUILD:SOCIALS marker pair and rerun tools/build-team.ps1"
    }
  }

  # ---- internal links and assets resolve ----
  $refs = @()
  $refs += [regex]::Matches($html, '(?:href|src)="([^"#][^"]*)"') | ForEach-Object { $_.Groups[1].Value }
  # Responsive candidates: srcset="a-360.jpg 360w, a-560.jpg 560w" and the
  # imagesrcset on a preload. The plain href|src pass above cannot see these,
  # so a typo in a variant name would 404 silently on exactly the screen sizes
  # nobody tests on.
  foreach ($m in [regex]::Matches($html, '(?:image)?srcset="([^"]+)"')) {
    $refs += ($m.Groups[1].Value -split ',') | ForEach-Object { ($_.Trim() -split '\s+')[0] } |
             Where-Object { $_ }
  }
  foreach ($ref in ($refs | Sort-Object -Unique)) {
    if ($ref -match '^(https?:|mailto:|data:|//|#)') { continue }
    $clean = ($ref -split '[?#]')[0]
    if ([string]::IsNullOrWhiteSpace($clean)) { continue }
    if ($clean.StartsWith('/')) {
      # Site-absolute, as used by 404.html (which GitHub Pages serves at any depth).
      # Resolve from the repo root, and insist the project prefix is present.
      if ($sitePrefix -and -not $clean.StartsWith("$sitePrefix/")) {
        Fail "$rel : site-absolute reference is missing the $sitePrefix prefix -> $ref"
        continue
      }
      $rootRel = $clean.Substring($sitePrefix.Length).TrimStart('/')
      if ($rootRel -eq '') { $rootRel = 'index.html' }
      $target = Join-Path $root ($rootRel -replace '/', '\')
    } else {
      $target = Join-Path $dir ($clean -replace '/', '\')
    }
    if (Test-Path $target -PathType Container) { $target = Join-Path $target 'index.html' }
    if (-not (Test-Path $target)) { Fail "$rel : broken reference -> $ref" }
  }
}

# ---- sitemap points at real files ----
$sitemapPath = Join-Path $root 'sitemap.xml'
if (Test-Path $sitemapPath) {
  [xml]$sm = Get-Content $sitemapPath -Raw -Encoding UTF8
  $locs = @($sm.urlset.url.loc)
  Write-Host "Checking $($locs.Count) sitemap URLs..." -ForegroundColor Cyan
  foreach ($loc in $locs) {
    if (-not $loc.StartsWith($baseUrl)) { Fail "sitemap.xml : $loc is not under $baseUrl"; continue }
    $path = $loc.Substring($baseUrl.Length).TrimStart('/')
    if ($path -eq '' -or $path.EndsWith('/')) { $path = $path + 'index.html' }
    $target = Join-Path $root ($path -replace '/', '\')
    if (-not (Test-Path $target)) { Fail "sitemap.xml : $loc has no matching file ($path)" }
  }
  # every non-noindex page should be listed
  foreach ($f in $htmlFiles) {
    $rel = $f.FullName.Substring($root.Length + 1).Replace('\', '/')
    $html = Get-Content $f.FullName -Raw -Encoding UTF8
    if (($noIndex -contains $rel) -or ($html -match 'name="robots"\s+content="noindex')) { continue }
    $expect = "$baseUrl/" + ($rel -replace 'index\.html$', '')
    if ($locs -notcontains $expect -and $locs -notcontains "$baseUrl/$rel") {
      Warn "sitemap.xml : $rel is indexable but not listed"
    }
  }
} else {
  Fail "sitemap.xml is missing"
}

# ---- press bundles ----
# The three zips are the one thing on this site nobody reviews after download.
# All three once shipped a README pointing at the retired github.io address and
# stored their paths with backslashes, so they unpacked as a flat heap of
# oddly-named files on every Mac and Linux box in games press. Neither fault is
# visible from a page, and neither showed up in a diff. Rebuild with
# tools/build-press-kit.ps1.
$zips = Get-ChildItem -Path (Join-Path $root 'assets\press') -Filter *.zip -ErrorAction SilentlyContinue
if (-not $zips) { Fail 'assets/press : no press bundles found' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
foreach ($z in $zips) {
  $rel = "assets/press/$($z.Name)"
  # A truncated or half-written zip throws out of OpenRead, and with
  # $ErrorActionPreference = 'Stop' that would abort the run before the report
  # is printed - the one failure mode where you most want to be told which file.
  try { $archive = [IO.Compression.ZipFile]::OpenRead($z.FullName) }
  catch { Fail "$rel : not a readable zip - $($_.Exception.Message)"; continue }
  try {
    foreach ($entry in $archive.Entries) {
      if ($entry.FullName.Contains([char]92)) {
        Fail "$rel : entry uses a backslash separator, so it will not unpack into folders off Windows -> $($entry.FullName)"
      }
    }
    $readme = $archive.Entries | Where-Object { $_.FullName -eq 'README.txt' }
    if (-not $readme) {
      Fail "$rel : no README.txt - press has nothing telling them where the kit came from or what they may do with it"
    } else {
      $reader = New-Object IO.StreamReader($readme.Open())
      $text = $reader.ReadToEnd()
      $reader.Dispose()
      if ($text -match 'github\.io') { Fail "$rel : README.txt still points at the retired github.io address" }
      if ($text -notmatch [regex]::Escape($baseUrl)) { Fail "$rel : README.txt does not mention $baseUrl" }
      if ($text -notmatch 'contact@shiverbugstudios\.com') { Fail "$rel : README.txt has no press contact" }
    }
  } finally {
    $archive.Dispose()
  }
}

# ---- llms.txt sanity ----
$llmsPath = Join-Path $root 'llms.txt'
if (Test-Path $llmsPath) {
  $llms = Get-Content $llmsPath -Raw -Encoding UTF8
  if ($llms -notmatch '^# ')      { Fail 'llms.txt : missing top-level "# " heading' }
  if ($llms -notmatch '(?m)^> ')  { Fail 'llms.txt : missing "> " summary line' }
} else {
  Fail 'llms.txt is missing'
}

# ---- the studio's identity links ----
# sameAs is how a search engine and an AI assistant work out that the Bluesky
# account, the YouTube channel and this site are one studio. The graph once
# claimed a single Linktree, which is a redirect page identifying nothing, and
# nothing in the markup caught it. Sourced from $studioSocials in
# tools/build-team.ps1 - fix it there, not in index.html.
$indexHtml = Get-Content (Join-Path $root 'index.html') -Raw -Encoding UTF8
$org = $null
foreach ($m in [regex]::Matches($indexHtml, '(?s)<script type="application/ld\+json">(.*?)</script>')) {
  try { $obj = $m.Groups[1].Value | ConvertFrom-Json } catch { continue }
  if ($obj.PSObject.Properties.Name -notcontains '@graph') { continue }
  foreach ($node in $obj.'@graph') {
    if ($node.'@type' -eq 'Organization') { $org = $node }
  }
}
if (-not $org) {
  Fail 'index.html : no Organization node in the structured data graph'
} else {
  $sameAs = @($org.sameAs)
  if ($sameAs.Count -lt 5) {
    Fail "index.html : Organization sameAs lists only $($sameAs.Count) profiles - the studio has more, and each one is an identity signal"
  }
  foreach ($needed in @('bsky.app', 'youtube.com', 'linkedin.com', 'instagram.com')) {
    if (-not ($sameAs | Where-Object { $_ -like "*$needed*" })) {
      Warn "index.html : Organization sameAs has no $needed profile"
    }
  }
}

# ---- report ----
Write-Host ''
foreach ($w in $warns)  { Write-Host "WARN  $w" -ForegroundColor Yellow }
foreach ($e in $errors) { Write-Host "FAIL  $e" -ForegroundColor Red }
Write-Host ''
if ($errors.Count -eq 0) {
  Write-Host "PASS - $($htmlFiles.Count) pages, 0 errors, $($warns.Count) warnings" -ForegroundColor Green
  exit 0
} else {
  Write-Host "FAILED - $($errors.Count) errors, $($warns.Count) warnings" -ForegroundColor Red
  exit 1
}
