# ============================================================
# Shiverbug Studios - static team page generator
#
# Reads data/team.json and writes:
#   team/<slug>.html      one real, crawlable page per person
#   index.html            the team grids, between the BUILD markers
#   sitemap.xml           every team page listed
#
# Run from anywhere:  powershell -ExecutionPolicy Bypass -File tools/build-team.ps1
# ============================================================

$ErrorActionPreference = 'Stop'

$root    = Split-Path -Parent $PSScriptRoot
$dataFile = Join-Path $root 'data\team.json'
$teamDir = Join-Path $root 'team'
$baseUrl = 'https://shiverbugstudios.com'

# GitHub Pages cannot send HTTP headers, so the policy travels in a meta tag.
# Keep this in step with the identical tag in index.html, games.html, press.html,
# privacy.html, accessibility.html, 404.html and team-member.html.
# Note: frame-ancestors is ignored in a meta tag, it only works as a real header.
#
# The one hash in script-src is for the single inline script every page carries
# in its <head>: document.documentElement.classList.add('js'). It has to run
# before first paint, which is the one thing an external file cannot promise,
# and it is what lets the stylesheet hide .reveal content only when script is
# actually running. Change a byte of that script and the hash must change with
# it - tools/validate-site.ps1 recomputes it and fails the build if they differ.
# Fonts are self-hosted from assets/fonts, so nothing here names Google.
$csp = "default-src 'self'; " +
       "script-src 'self' 'sha256-Du+OJKJSbdUgz5nrHeWWINvez6XKDDU/tyj/5c2uvwo=' https://gc.zgo.at; " +
       "style-src 'self' 'unsafe-inline'; " +
       "font-src 'self'; " +
       "img-src 'self' data: https://oliverneal04.goatcounter.com; " +
       "media-src 'self'; " +
       "connect-src 'self' https://formspree.io https://buttondown.com https://oliverneal04.goatcounter.com; " +
       "form-action https://formspree.io https://buttondown.com; " +
       "base-uri 'none'; object-src 'none'"

# Companies Act 2006 trading disclosure. Required on the website, so it goes in
# every footer.
$legal = 'Shiverbug Studios Ltd is registered in England and Wales, company no. 16485763. ' +
         'Registered office: Victoria Building, Victoria Road, Middlesbrough, TS1 3AP, United Kingdom.'

# ---------- the studio's own profiles ----------
#
# One list, two jobs: the visible footer row on every page, and schema.org
# sameAs on the Organization. Both matter and they must agree, which is why
# they are generated from here rather than hand-written in nine places.
#
# sameAs is how a search engine or an AI assistant works out that the Bluesky
# account, the YouTube channel and this site are all the one studio, and which
# URL is the canonical home of that entity. Until this list existed the graph
# claimed a single Linktree, which is a redirect page and identifies nothing.
#
# 'inSameAs = $false' means the link is worth showing a human but is not an
# identity reference: a Discord invite is a door into a server, not a profile
# that describes the studio, and invite codes can be rotated.
$studioSocials = @(
  @{ label = 'Bluesky';   icon = 'bluesky';   url = 'https://bsky.app/profile/shiverbugstudios.bsky.social' }
  @{ label = 'X';         icon = 'x';         url = 'https://x.com/ShiverbugStudio' }
  @{ label = 'Instagram'; icon = 'instagram'; url = 'https://www.instagram.com/shiverbugstudios/' }
  @{ label = 'TikTok';    icon = 'tiktok';    url = 'https://www.tiktok.com/@shiverbugstudios' }
  @{ label = 'YouTube';   icon = 'youtube';   url = 'https://www.youtube.com/@ShiverbugStudios' }
  @{ label = 'LinkedIn';  icon = 'linkedin';  url = 'https://www.linkedin.com/company/shiverbug-studios' }
  @{ label = 'itch.io';   icon = 'itchio';    url = 'https://shiverbug-studios.itch.io/' }
  @{ label = 'Discord';   icon = 'discord';   url = 'https://discord.gg/gZDWdZEAxm'; inSameAs = $false }
)

# Reference pages that identify the studio without being ours to post on. The
# Companies House record is the strongest identity signal available to a company
# this young: it ties the name to registration 16485763, which is the same
# number the footer discloses on every page.
$studioRefs = @(
  'https://linktr.ee/shiverbugstudios'
  'https://find-and-update.company-information.service.gov.uk/company/16485763'
)

$studioSameAs = @(
  @($studioSocials | Where-Object { $_.inSameAs -ne $false } | ForEach-Object { $_.url })
) + $studioRefs

$data   = Get-Content $dataFile -Raw -Encoding UTF8 | ConvertFrom-Json
$team   = @($data.team)
$talent = @($data.talent)
$all    = @($team) + @($talent)

if (-not (Test-Path $teamDir)) { New-Item -ItemType Directory -Path $teamDir | Out-Null }

# ---------- helpers ----------

function HtmlEnc([string]$s) {
  if ([string]::IsNullOrEmpty($s)) { return '' }
  return $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
}

function StripTags([string]$s) {
  if ([string]::IsNullOrEmpty($s)) { return '' }
  return ([regex]::Replace($s, '<[^>]+>', '')).Trim()
}

function Truncate([string]$s, [int]$max) {
  if ($s.Length -le $max) { return $s }
  $cut = $s.Substring(0, $max)
  $sp = $cut.LastIndexOf(' ')
  if ($sp -gt 40) { $cut = $cut.Substring(0, $sp) }
  return $cut.TrimEnd(',', '.', ';', ':') + '...'
}

# Build a meta description that ends where a sentence ends.
#
# Google renders roughly 155-160 characters and drops the rest, so overshooting
# buys nothing. The old rule took the first 200 characters of the bio flat,
# which reliably cut somebody off mid-word: "First Class Honours in BSc (Hons)
# Games..." was a real search result for this site. A snippet that stops in the
# middle of a clause reads as broken text rather than as an answer.
#
# So: keep adding whole sentences while they fit. If not even the first one
# fits, fall back to the last clause boundary inside the limit, and only then
# to a hard truncation. Anyone whose bio resists all three gets a hand-written
# "metaDescription" in data/team.json, which wins outright.
$descLimit = 158
function SentenceClip([string]$lead, [string]$body, [int]$max) {
  $lead = $lead.Trim()
  if ([string]::IsNullOrWhiteSpace($body)) { return $lead }
  if ($lead.Length -ge $max) { return $lead }

  $out = $lead
  foreach ($sentence in [regex]::Split($body.Trim(), '(?<=[.!?])\s+')) {
    $s = $sentence.Trim()
    if ($s -eq '') { continue }
    $candidate = ($out + ' ' + $s).Trim()
    if ($candidate.Length -gt $max) { break }
    $out = $candidate
  }
  if ($out -ne $lead) { return $out }

  # No whole sentence fits. Cut at the last comma or semicolon that does, so the
  # snippet at least ends on a complete clause instead of mid-phrase.
  # -4 leaves room for the space after the lead and the three dots on the end,
  # so the fallback cannot overshoot $max the way a -2 here did.
  $room = $max - $lead.Length - 4
  if ($room -gt 60) {
    $head = $body.Trim().Substring(0, [Math]::Min($room, $body.Trim().Length))
    $stop = [Math]::Max($head.LastIndexOf(','), $head.LastIndexOf(';'))
    if ($stop -gt 50) {
      return ($lead + ' ' + $head.Substring(0, $stop).Trim() + '...')
    }
  }
  return (Truncate ($lead + ' ' + $body.Trim()) $max)
}

# A profile is "finished" once it has a written bio. Anything without one is a
# placeholder page, so the grids render it as a dead tile with a short note
# instead of a link, and the prev/next chain steps over it. Keeping the page
# itself means old links and the ?p= shim carry on working.
function IsFinished($person) {
  return [bool]($person.about -and @($person.about).Count -gt 0)
}

function RoleDisplay($person) {
  # NB: keep this file pure ASCII - PowerShell 5.1 reads a BOM-less .ps1 as ANSI,
  # so a literal middot here would arrive mangled. Build it from its code point.
  $middot = [char]0x00B7
  return [regex]::Replace($person.role, '\s*' + $middot + '\s*Co-Founder', '', 'IgnoreCase')
}

# Topics for schema.org knowsAbout - this is what an AI agent reads to answer
# "who at this studio does X?". Derived from the role title only, so it stays
# truthful; add a "knowsAbout" array in team.json to override for anyone.
$disciplines = @(
  @{ match = 'gameplay programmer|programmer'; topics = @('Gameplay Programming', 'Game Programming') },
  @{ match = 'character concept artist';       topics = @('Concept Art', 'Character Design') },
  @{ match = 'concept artist';                 topics = @('Concept Art') },
  @{ match = 'character artist';               topics = @('Character Art', '3D Art') },
  @{ match = 'lead artist';                    topics = @('Art Direction', '3D Art') },
  @{ match = '3d artist';                      topics = @('3D Art', 'Environment Art') },
  @{ match = '3d animator|animator';           topics = @('3D Animation') },
  @{ match = 'level designer';                 topics = @('Level Design', 'Game Design') },
  @{ match = 'narrative designer';             topics = @('Narrative Design', 'Game Writing') },
  @{ match = 'sound designer';                 topics = @('Sound Design', 'Game Audio') },
  @{ match = 'social media';                   topics = @('Social Media Marketing') },
  @{ match = 'ceo|cfo';                        topics = @('Game Studio Management') }
)

function KnowsAbout($person) {
  if ($person.knowsAbout -and @($person.knowsAbout).Count -gt 0) { return @($person.knowsAbout) }
  $topics = @('Video Game Development')
  foreach ($d in $disciplines) {
    if ($person.role -match ('(?i)' + $d.match)) { $topics += $d.topics; break }
  }
  return @($topics)
}

function WriteFileUtf8([string]$path, [string]$text) {
  # UTF-8 without BOM, CRLF endings to match the rest of the working tree
  $text = $text.Replace("`r`n", "`n").Replace("`n", "`r`n")
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($path, $text, $enc)
}

# ---------- social icons (ported from the old js/member.js) ----------

$icons = @{
  'linkedin'   = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M20.447 20.452h-3.554v-5.569c0-1.328-.027-3.037-1.852-3.037-1.853 0-2.136 1.445-2.136 2.939v5.667H9.351V9h3.414v1.561h.046c.477-.9 1.637-1.85 3.37-1.85 3.601 0 4.267 2.37 4.267 5.455v6.286zM5.337 7.433c-1.144 0-2.063-.926-2.063-2.065 0-1.138.92-2.063 2.063-2.063 1.14 0 2.064.925 2.064 2.063 0 1.139-.925 2.065-2.064 2.065zm1.782 13.019H3.555V9h3.564v11.452zM22.225 0H1.771C.792 0 0 .774 0 1.729v20.542C0 23.227.792 24 1.771 24h20.451C23.2 24 24 23.227 24 22.271V1.729C24 .774 23.2 0 22.225 0z"/></svg>'
  'github'     = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12"/></svg>'
  'instagram'  = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><rect x="3" y="3" width="18" height="18" rx="5"/><circle cx="12" cy="12" r="4.2"/><circle cx="17.3" cy="6.7" r="1.2" fill="currentColor" stroke="none"/></svg>'
  'artstation' = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M0 17.723l2.027 3.505a2.424 2.424 0 0 0 2.164 1.333h13.457l-2.792-4.838H0zm24-.025c0-.484-.143-.935-.388-1.314L15.728 2.728a2.424 2.424 0 0 0-2.142-1.289h-4.19l12.06 20.902 2.028-3.513c.388-.672.516-.973.516-1.13zm-11.35-10.85l-4.277 7.408h8.552l-4.275-7.408z"/></svg>'
  'bluesky'    = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 10.8C10.913 8.686 7.954 4.747 5.202 2.805 2.566.944 1.561 1.266.902 1.565.139 1.908 0 3.08 0 3.768c0 .69.378 5.65.624 6.479.815 2.736 3.713 3.66 6.383 3.364-3.912.58-7.387 2.005-2.83 7.078 5.013 5.19 6.87-1.113 7.823-4.308.953 3.195 2.05 9.271 7.733 4.308 4.267-4.308 1.172-6.498-2.74-7.078 2.67.297 5.568-.628 6.383-3.364.246-.828.624-5.79.624-6.478 0-.69-.139-1.861-.902-2.206-.659-.298-1.664-.62-4.3 1.24C16.046 4.748 13.087 8.687 12 10.8Z"/></svg>'
  'itchio'     = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 12h.01M10 10v4M8 12h4"/><path d="M17.5 10.5h.01M15.5 13.5h.01"/><path d="M7.2 6h9.6c2.3 0 4.1 1.8 4.2 4.1l.4 5.2a3.6 3.6 0 0 1-6.3 2.7l-1-1.2a2.6 2.6 0 0 0-4.2 0l-1 1.2A3.6 3.6 0 0 1 2.6 15.3l.4-5.2C3.1 7.8 4.9 6 7.2 6z"/></svg>'
  'x'          = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M18.901 1.153h3.68l-8.04 9.19L24 22.846h-7.406l-5.8-7.584-6.638 7.584H.474l8.6-9.83L0 1.154h7.594l5.243 6.932ZM17.61 20.644h2.039L6.486 3.24H4.298Z"/></svg>'
  'sketchfab'  = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 2.3 20.5 7v10L12 21.7 3.5 17V7z"/><path d="M12 21.7V12M12 12 3.5 7M12 12l8.5-5"/></svg>'
  'website'    = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><circle cx="12" cy="12" r="9"/><ellipse cx="12" cy="12" rx="4" ry="9"/><path d="M3.6 9h16.8M3.6 15h16.8"/></svg>'
  'youtube'    = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M23.498 6.186a3.016 3.016 0 0 0-2.122-2.136C19.505 3.545 12 3.545 12 3.545s-7.505 0-9.377.505A3.017 3.017 0 0 0 .502 6.186C0 8.07 0 12 0 12s0 3.93.502 5.814a3.016 3.016 0 0 0 2.122 2.136c1.871.505 9.376.505 9.376.505s7.505 0 9.377-.505a3.015 3.015 0 0 0 2.122-2.136C24 15.93 24 12 24 12s0-3.93-.502-5.814zM9.545 15.568V8.432L15.818 12l-6.273 3.568z"/></svg>'
  'tiktok'     = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12.525.02c1.31-.02 2.61-.01 3.91-.02.08 1.53.63 3.09 1.75 4.17 1.12 1.11 2.7 1.62 4.24 1.79v4.03c-1.44-.05-2.89-.35-4.2-.97-.57-.26-1.1-.59-1.62-.93-.01 2.92.01 5.84-.02 8.75-.08 1.4-.54 2.79-1.35 3.94-1.31 1.92-3.58 3.17-5.91 3.21-1.43.08-2.86-.31-4.08-1.03-2.02-1.19-3.44-3.37-3.65-5.71-.02-.5-.03-1-.01-1.49.18-1.9 1.12-3.72 2.58-4.96 1.66-1.44 3.98-2.13 6.15-1.72.02 1.48-.04 2.96-.04 4.44-.99-.32-2.15-.23-3.02.37-.63.41-1.11 1.04-1.36 1.75-.21.51-.15 1.07-.14 1.61.24 1.64 1.82 3.02 3.5 2.87 1.12-.01 2.19-.66 2.77-1.61.19-.33.4-.67.41-1.06.1-1.79.06-3.57.07-5.36.01-4.03-.01-8.05.02-12.07z"/></svg>'
  'discord'    = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M20.317 4.3698a19.7913 19.7913 0 0 0-4.8851-1.5152.0741.0741 0 0 0-.0785.0371c-.211.3753-.4447.8648-.6083 1.2495-1.8447-.2762-3.68-.2762-5.4868 0-.1636-.3933-.4058-.8742-.6177-1.2495a.077.077 0 0 0-.0785-.037 19.7363 19.7363 0 0 0-4.8852 1.515.0699.0699 0 0 0-.0321.0277C.5334 9.0458-.319 13.5799.0992 18.0578a.0824.0824 0 0 0 .0312.0561c2.0528 1.5076 4.0413 2.4228 5.9929 3.0294a.0777.0777 0 0 0 .0842-.0276c.4616-.6304.8731-1.2952 1.226-1.9942a.076.076 0 0 0-.0416-.1057c-.6528-.2476-1.2743-.5495-1.8722-.8923a.077.077 0 0 1-.0076-.1277c.1258-.0943.2517-.1923.3718-.2914a.0743.0743 0 0 1 .0776-.0105c3.9278 1.7933 8.18 1.7933 12.0614 0a.0739.0739 0 0 1 .0785.0095c.1202.099.246.1981.3728.2924a.077.077 0 0 1-.0066.1276 12.2986 12.2986 0 0 1-1.873.8914.0766.0766 0 0 0-.0407.1067c.3604.698.7719 1.3628 1.225 1.9932a.076.076 0 0 0 .0842.0286c1.961-.6067 3.9495-1.5219 6.0023-3.0294a.077.077 0 0 0 .0313-.0552c.5004-5.177-.8382-9.6739-3.5485-13.6604a.061.061 0 0 0-.0312-.0286zM8.02 15.3312c-1.1825 0-2.1569-1.0857-2.1569-2.419 0-1.3332.9555-2.4189 2.157-2.4189 1.2108 0 2.1757 1.0952 2.1568 2.419 0 1.3332-.9555 2.4189-2.1569 2.4189zm7.9748 0c-1.1825 0-2.1569-1.0857-2.1569-2.419 0-1.3332.9554-2.4189 2.1569-2.4189 1.2108 0 2.1757 1.0952 2.1568 2.419 0 1.3332-.946 2.4189-2.1568 2.4189z"/></svg>'
}

function IconFor([string]$label) {
  $key = ([regex]::Replace($label.ToLower(), '[^a-z]', ''))
  if ($icons.ContainsKey($key)) { return $icons[$key] }
  return $icons['website']
}

# ---------- the footer social row ----------
#
# Rendered into every page through the BUILD:SOCIALS markers. Two details that
# are easy to lose in a redesign:
#   rel="me"  - the microformats identity claim. sameAs in the JSON-LD says
#               "these profiles are us"; rel="me" says the same thing in the
#               markup, and between them a crawler gets the link from both
#               directions once the profiles link back here.
#   the label - a visually-hidden span rather than aria-label, so the name is
#               real text that survives translation and shows up in a text-only
#               crawl. The icon itself is aria-hidden, so nothing reads twice.
function FooterSocialsHtml([string]$indent) {
  $items = @($studioSocials | ForEach-Object {
    $indent + '    <li><a href="' + (HtmlEnc $_.url) + '" target="_blank" rel="me noopener" title="' + (HtmlEnc $_.label) + '">' +
    (IconFor $_.icon) + '<span class="visually-hidden">Shiverbug Studios on ' + (HtmlEnc $_.label) + '</span></a></li>'
  }) -join "`n"
  # Each element is parenthesised on purpose. PowerShell binds the comma tighter
  # than +, so an unbracketed "$indent + '<nav>', $indent + '  <ul>'" parses as
  # $indent + ('<nav>', $indent) + '  <ul>' - the inner array collapses to a
  # string joined by $OFS and -join never sees separate elements. The symptom is
  # a footer that renders correctly but arrives as one very long line.
  return @(
    ($indent + '<nav class="footer__socials" aria-label="Shiverbug Studios elsewhere">'),
    ($indent + '  <ul>'),
    $items,
    ($indent + '  </ul>'),
    ($indent + '</nav>')
  ) -join "`n"
}

# lastmod / dateModified both answer "has this changed?", and neither is the
# build date: stamping every page with today on every build tells search engines
# the whole site changes daily, which is the fastest way to have the field
# ignored altogether. Defined up here because the structured data below needs
# the same dates as the sitemap.
#
# These used to come from `git log -1` on each file. That could never be
# self-consistent - the date written into a file was computed before the commit
# that wrote it, and that commit moved the date again - so the CI drift check
# went red the first time a change crossed midnight. They are declared in
# data/team.json now, which makes this build deterministic and lets that check
# compare its output strictly.
#
# Missing keys are fatal rather than defaulted to today. A silent fallback is
# how the old version hid the problem, and a page quietly claiming it changed on
# whatever day the build ran is worse than a build that stops and names it.
function PageDate([string]$relPath) {
  $key = $relPath -replace '\\', '/'
  $entry = $data.dateModified.PSObject.Properties[$key]
  if (-not $entry) {
    throw "No dateModified for '$key' in data/team.json. Add it under `"dateModified`", using the date that page's content last actually changed."
  }
  if ($entry.Value -notmatch '^\d{4}-\d{2}-\d{2}$') {
    throw "dateModified for '$key' is '$($entry.Value)', which is not a yyyy-MM-dd date."
  }
  return $entry.Value
}

# ---------- page template ----------

$template = @'
<!DOCTYPE html>
<html lang="en-GB">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta http-equiv="Content-Security-Policy" content="{{CSP}}">
  <title>{{NAME}} | Shiverbug Studios</title>
  <meta name="description" content="{{DESC}}">
{{ROBOTS}}  <link rel="canonical" href="{{CANONICAL}}">
  <meta property="og:title" content="{{NAME}}, {{ROLE}} | Shiverbug Studios">
  <meta property="og:description" content="{{DESC}}">
  <meta property="og:image" content="{{OGIMAGE}}">
  <meta property="og:image:alt" content="{{OGALT}}">
  <meta property="og:url" content="{{CANONICAL}}">
  <meta property="og:type" content="profile">
  <meta property="og:site_name" content="Shiverbug Studios">
  <meta property="og:locale" content="en_GB">
  <meta name="twitter:card" content="summary">
  <meta name="twitter:title" content="{{NAME}}, {{ROLE}} | Shiverbug Studios">
  <meta name="twitter:description" content="{{DESC}}">
  <meta name="twitter:image" content="{{OGIMAGE}}">
  <meta name="theme-color" content="#050b13">
  <link rel="icon" type="image/png" href="../assets/img/favicon.png">
  <link rel="apple-touch-icon" href="../assets/img/favicon.png">
  <link rel="preload" href="../assets/fonts/bricolage-grotesque-latin.woff2" as="font" type="font/woff2" crossorigin>
  <link rel="preload" href="../assets/fonts/instrument-sans-latin.woff2" as="font" type="font/woff2" crossorigin>
  <link rel="stylesheet" href="../css/style.min.css">
  <script>document.documentElement.classList.add('js')</script>
  <script type="application/ld+json">
{{JSONLD}}
  </script>
</head>
<body>

  <a class="skip-link" href="#top">Skip to content</a>

  <!-- ======= NAV ======= -->
  <header class="nav" id="nav">
    <div class="nav__inner">
      <a class="nav__brand" href="../" aria-label="Shiverbug Studios, home"><img src="../assets/img/nav-wordmark.webp" alt="" class="nav__wordmark" width="316" height="138"></a>
      <nav class="nav__links" id="navLinks" aria-label="Primary">
        <a href="../#services">Co-Dev</a>
        <a href="../games.html">Our Games</a>
        <a href="../#studio">Studio</a>
        <a href="../#team">Team</a>
        <a href="../join.html">Join Us</a>
        <a href="../press.html">Press</a>
        <a class="nav__cta" href="../#contact">Get in touch</a>
      </nav>
      <button class="nav__burger" id="navBurger" aria-label="Open menu" aria-expanded="false" aria-controls="navLinks">
        <span></span><span></span>
      </button>
    </div>
  </header>

  <main class="profile" id="top">
    <div class="container">
      <a class="backlink" href="{{BACKHREF}}">
        <svg viewBox="0 0 16 16" aria-hidden="true"><path d="M14 8H3M7 3.5 2.5 8 7 12.5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>
        {{BACKTEXT}}
      </a>
      <div class="profile__inner">
        <figure class="profile__photo">{{PHOTO}}</figure>
        <div>
          <h1 class="profile__name">{{NAME}}</h1>
          <p class="kicker kicker--sand profile__role">{{ROLELINE}}</p>
          {{TAGLINE}}
          <div class="profile__badges">{{BADGES}}</div>
          <section class="profile__section">
            <h2>About</h2>
            {{ABOUT}}
          </section>
{{ASKME}}
          <section class="profile__section">
            <h2>Find me</h2>
            <div class="profile__socials">{{SOCIALS}}</div>
          </section>
        </div>
      </div>
      <nav class="profile__nav" aria-label="Team">
        <a href="{{PREVHREF}}">&larr; {{PREVNAME}}</a>
        <a class="is-back" href="./">All shiverbugs</a>
        <a href="{{NEXTHREF}}">{{NEXTNAME}} &rarr;</a>
      </nav>
    </div>
  </main>

  <footer class="footer footer--mini">
    <div class="container">
{{SOCIALSROW}}
      <div class="footer__meta">
        <p>&copy; <span id="year">2026</span> Shiverbug Studios Ltd &middot; North East England, UK &middot; <a class="footer__press" href="../press.html">Press kit</a> &middot; <a class="footer__press" href="../privacy.html">Privacy</a> &middot; <a class="footer__press" href="../accessibility.html">Accessibility</a></p>
        <p class="footer__tag">Bringing family game night back to the sofa.</p>
        <p class="footer__legal">{{LEGAL}}</p>
      </div>
    </div>
  </footer>

  <script src="../js/main.js"></script>
  <script src="../js/profile.js"></script>
  <!-- Analytics: GoatCounter. Cookieless, no personal data, no consent banner needed. -->
  <script data-goatcounter="https://oliverneal04.goatcounter.com/count" async src="https://gc.zgo.at/count.js"></script>
</body>
</html>
'@

# ---------- build one page per person ----------

$favourites = @{
  'turtle'  = @{ cls = 'badge--turtle';  text = 'Team Turtle' }
  'seagull' = @{ cls = 'badge--seagull'; text = 'Team Seagull' }
  'crab'    = @{ cls = 'badge--crab';    text = 'Team Crab (the army)' }
}

$written = @()

foreach ($list in @($team, $talent)) {
  $order = @($list)
  for ($i = 0; $i -lt $order.Count; $i++) {
    $p = $order[$i]
    $firstName = ($p.name -split ' ')[0]
    $roleDisp = RoleDisplay $p
    $canonical = "$baseUrl/team/$($p.slug).html"

    # --- description: role first, then as much of the bio as ends cleanly ---
    # The lead has to say where someone stands, because it is the sentence a
    # search result shows: a former shiverbug is not "X at Shiverbug Studios".
    $lead = "$($p.name) - $roleDisp at Shiverbug Studios."
    if ($p.status -eq 'former') { $lead = "$($p.name) - former $roleDisp at Shiverbug Studios." }
    elseif ($p.status -eq 'active') { $lead = "$($p.name) - $roleDisp in the Shiverbug Studios talent pool." }
    if ($p.metaDescription) {
      $desc = $p.metaDescription
    } elseif ($p.about -and @($p.about).Count -gt 0) {
      $desc = SentenceClip $lead (StripTags (@($p.about)[0])) $descLimit
    } elseif ($p.tagline) {
      $desc = SentenceClip $lead ('"' + $p.tagline + '"') $descLimit
    } else {
      $desc = SentenceClip $lead 'Shiverbug Studios is an indie game studio in North East England making couch co-op games.' $descLimit
    }

    # --- photo ---
    if ($p.photo) {
      # The photo is the largest thing on the page, so it is the one fetch that
      # jumps the queue.
      $photo = '<img src="../' + $p.photo + '" alt="' + (HtmlEnc $p.name) + '" width="600" height="800" fetchpriority="high" decoding="async">'
      $ogImage = "$baseUrl/$($p.photo)"
    } else {
      $photo = '<div class="profile__photo--empty"><span>' + (HtmlEnc $p.initials) + '</span></div>'
      $ogImage = "$baseUrl/assets/press/shiverbug-logo.png"
    }

    # --- role line ---
    $roleLine = HtmlEnc $roleDisp
    if ($p.pronouns) { $roleLine = $roleLine + ' &middot; ' + (HtmlEnc $p.pronouns) }

    # --- tagline ---
    if ($p.tagline) {
      $tagline = '<p class="profile__tagline">&ldquo;' + (HtmlEnc $p.tagline) + '&rdquo;</p>'
    } else {
      $tagline = '<p class="profile__tagline">' + (HtmlEnc $firstName) + " hasn't picked a tagline yet. We're on it.</p>"
    }

    # --- badges ---
    $badges = ''
    if ($p.role -match '(?i)co-founder') { $badges += '<span class="badge badge--founder">&#9733; Co-Founder</span>' }
    if ($p.favourite -and $favourites.ContainsKey($p.favourite)) {
      $f = $favourites[$p.favourite]
      $badges += '<span class="badge ' + $f.cls + '">' + $f.text + '</span>'
    } else {
      $badges += '<span class="badge">Turtle or seagull? Undecided.</span>'
    }
    if ($p.status -eq 'active') { $badges += '<span class="badge badge--active">Actively contributing</span>' }
    elseif ($p.status -eq 'former') { $badges += '<span class="badge badge--former">Former shiverbug</span>' }

    # --- about: always rendered in full, JS only adds the read-more clamp ---
    if ($p.about -and @($p.about).Count -gt 0) {
      $paras = (@($p.about) | ForEach-Object { '<p>' + $_ + '</p>' }) -join "`n            "
      $joined = (@($p.about) -join ' ')
      $clampAttr = ''
      if ($joined.Length -gt 600) { $clampAttr = ' data-clamp="true"' }
      $about = '<div class="profile__about" id="aboutText"' + $clampAttr + '>' + "`n            " + $paras + "`n            " + '</div>'
    } else {
      $about = '<p class="is-placeholder">We&rsquo;re still squeezing a bio out of ' + (HtmlEnc $firstName) + '. Check back soon.</p>'
    }

    # --- ask me about ---
    $askMe = ''
    if ($p.askMeAbout -and @($p.askMeAbout).Count -gt 0) {
      $chips = (@($p.askMeAbout) | ForEach-Object { '<span class="chip">' + (HtmlEnc $_) + '</span>' }) -join ''
      $askMe = @"
          <section class="profile__section">
            <h2>Ask me about</h2>
            <div class="profile__chips">$chips</div>
          </section>
"@
    }

    # --- socials ---
    if ($p.socials -and @($p.socials).Count -gt 0) {
      $socials = (@($p.socials) | ForEach-Object {
        '<a class="social" href="' + (HtmlEnc $_.url) + '" target="_blank" rel="noopener">' +
        '<span class="social__icon">' + (IconFor $_.label) + '</span>' +
        '<span class="social__label">' + (HtmlEnc $_.label) + '</span></a>'
      }) -join "`n            "
    } else {
      $socials = '<p class="is-placeholder">Links on the way.</p>'
    }

    # --- prev / next, wrapping inside this person's own list ---
    # Step over anyone whose profile is still a placeholder, so walking the team
    # never dumps you on a page with nothing on it. Falls back to the immediate
    # neighbour if this list has no finished people to point at.
    function NeighbourAt($list, [int]$from, [int]$step) {
      for ($n = 1; $n -lt $list.Count; $n++) {
        $cand = $list[(($from + ($step * $n)) % $list.Count + $list.Count) % $list.Count]
        if (IsFinished $cand) { return $cand }
      }
      return $list[(($from + $step) % $list.Count + $list.Count) % $list.Count]
    }
    $prev = NeighbourAt $order $i -1
    $next = NeighbourAt $order $i 1

    # --- JSON-LD: ProfilePage wrapping a Person, plus a breadcrumb trail.
    #     The @id refs let a crawler stitch person -> studio -> other people. ---
    $studioRef = [ordered]@{
      '@type' = 'Organization'
      '@id'   = "$baseUrl/#studio"
      'name'  = 'Shiverbug Studios'
      'url'   = "$baseUrl/"
    }
    $person = [ordered]@{
      '@type'       = 'Person'
      '@id'         = "$canonical#person"
      'name'        = $p.name
      'jobTitle'    = $roleDisp
      'url'         = $canonical
      'image'       = $ogImage
      'description' = (StripTags $desc)
      'knowsAbout'  = @(KnowsAbout $p)
    }
    # Only the studio roster works for the studio. A talent pool regular is an
    # affiliate, and a former shiverbug is an alumnus: telling a search engine
    # that someone who has left still works here is the kind of claim that ends
    # up quoted back at them in a search result for years.
    if (-not $p.status) { $person['worksFor'] = $studioRef }
    elseif ($p.status -eq 'former') { $person['alumniOf'] = $studioRef }
    else { $person['affiliation'] = $studioRef }
    if ($p.socials -and @($p.socials).Count -gt 0) {
      $person['sameAs'] = @(@($p.socials) | ForEach-Object { $_.url })
    }

    $crumbs = [ordered]@{
      '@type'           = 'BreadcrumbList'
      'itemListElement' = @(
        [ordered]@{ '@type' = 'ListItem'; 'position' = 1; 'name' = 'Shiverbug Studios'; 'item' = "$baseUrl/" },
        [ordered]@{ '@type' = 'ListItem'; 'position' = 2; 'name' = 'Team'; 'item' = "$baseUrl/team/" },
        [ordered]@{ '@type' = 'ListItem'; 'position' = 3; 'name' = $p.name }
      )
    }

    $ld = [ordered]@{
      '@context' = 'https://schema.org'
      '@graph'   = @(
        [ordered]@{
          '@type'      = 'ProfilePage'
          '@id'        = $canonical
          'url'        = $canonical
          'name'       = "$($p.name) | Shiverbug Studios"
          'description' = (StripTags $desc)
          'dateModified' = (PageDate "team/$($p.slug).html")
          'mainEntity' = @{ '@id' = "$canonical#person" }
          'breadcrumb' = $crumbs
          'isPartOf'   = @{ '@id' = "$baseUrl/#website" }
          'about'      = @{ '@id' = "$baseUrl/#studio" }
          'inLanguage' = 'en-GB'
        },
        $person
      )
    }
    $jsonld = ($ld | ConvertTo-Json -Depth 12).Replace('<', '\u003c')

    # A profile with no bio has nothing worth ranking, and nothing on the site
    # links to it any more. Keep the page (old links, the ?p= shim) but tell
    # crawlers to skip it, and follow so the links out of it still count.
    $robots = ''
    if (-not (IsFinished $p)) {
      $robots = '  <meta name="robots" content="noindex, follow">' + "`n"
    }

    $html = $template.
      Replace('{{ROBOTS}}',    $robots).
      Replace('{{CSP}}',       (HtmlEnc $csp)).
      Replace('{{LEGAL}}',     (HtmlEnc $legal)).
      Replace('{{SOCIALSROW}}', (FooterSocialsHtml '      ')).
      Replace('{{NAME}}',      (HtmlEnc $p.name)).
      Replace('{{ROLE}}',      (HtmlEnc $roleDisp)).
      Replace('{{ROLELINE}}',  $roleLine).
      Replace('{{DESC}}',      (HtmlEnc (StripTags $desc))).
      Replace('{{CANONICAL}}', $canonical).
      Replace('{{OGIMAGE}}',   $ogImage).
      Replace('{{OGALT}}',     (HtmlEnc ("Portrait of " + $p.name))).
      Replace('{{BACKHREF}}',  $(if ($p.status) { '../#talent-pool' } else { '../#team' })).
      Replace('{{BACKTEXT}}',  $(if ($p.status) { 'Back to the talent pool' } else { 'Back to the team' })).
      Replace('{{JSONLD}}',    $jsonld).
      Replace('{{PHOTO}}',     $photo).
      Replace('{{TAGLINE}}',   $tagline).
      Replace('{{BADGES}}',    $badges).
      Replace('{{ABOUT}}',     $about).
      Replace('{{ASKME}}',     $askMe).
      Replace('{{SOCIALS}}',   $socials).
      Replace('{{PREVHREF}}',  ($prev.slug + '.html')).
      Replace('{{PREVNAME}}',  (HtmlEnc (($prev.name -split ' ')[0]))).
      Replace('{{NEXTHREF}}',  ($next.slug + '.html')).
      Replace('{{NEXTNAME}}',  (HtmlEnc (($next.name -split ' ')[0])))

    WriteFileUtf8 (Join-Path $teamDir "$($p.slug).html") $html
    $written += $p.slug
  }
}

Write-Host "Wrote $($written.Count) team pages to team/"

# ---------- index.html team grids ----------

# ---------- responsive thumbnails ----------
#
# tools/make-variants.ps1 writes assets/img/<name>-<width>.<ext> beside each
# original. A grid tile is never wider than ~274 CSS px, so handing it the
# 900px original was costing roughly ten times the bytes it could use.
#
# The srcset is built from whatever is actually on disk: the narrower portraits
# (Charlie A at 610px, Connor at 676px) have no 640 variant, and nothing here
# should have to know that.
# A plain tile is at most 274 CSS px, so 480 already covers a 2x desktop screen
# and is 2.7x what a 390px phone shows it at. Offering 640 as well only meant
# every 3x phone pulled it, for a difference nobody can see on a 100px thumbnail.
# The .is-zoomed tiles do keep it: CSS paints those at up to 2.1x their box.
$thumbWidths       = @(240, 320, 480)
$thumbWidthsZoomed = @(240, 320, 480, 640)

function VariantPath($photo, [int]$w) {
  # 'assets/img/team-lewis.webp' -> 'assets/img/team-lewis-480.webp'
  $ext = [System.IO.Path]::GetExtension($photo)
  return ($photo.Substring(0, $photo.Length - $ext.Length) + '-' + $w + $ext)
}

function SrcSetFor($photo, [int[]]$widths) {
  $parts = @()
  $largest = $null
  foreach ($w in $widths) {
    $rel = VariantPath $photo $w
    if (Test-Path (Join-Path $root ($rel -replace '/', '\'))) {
      $parts += "$rel ${w}w"
      $largest = $rel
    }
  }
  if ($parts.Count -eq 0) { return $null }
  return @{ srcset = ($parts -join ', '); src = $largest }
}

# The main grid: 2 columns under 760px, 3 under 980px, 4 above, inside a
# min(1160px, 92vw) container with a 1.3rem gap.
$thumbSizes = '(max-width: 760px) 46vw, (max-width: 980px) 30vw, (max-width: 1260px) 22vw, 274px'
# The founders row is 3 columns at every width - it never drops to 2 - and above
# 980px it is narrowed so its tiles match the 4-column grid exactly.
$founderSizes = '(max-width: 980px) 30vw, (max-width: 1260px) 22vw, 274px'
# .is-zoomed paints the photo at 1.5x-2.1x its box, and `sizes` only describes
# the box, so the zoomed tiles are told to ask for roughly double.
$thumbSizesZoomed = '(max-width: 760px) 92vw, (max-width: 980px) 60vw, (max-width: 1260px) 44vw, 548px'
$founderSizesZoomed = '(max-width: 980px) 60vw, (max-width: 1260px) 44vw, 548px'

# $forceLink is for team-member.html only. That page exists to catch old ?p=
# links and point them at the page that replaced them, and those pages do exist.
# Turning them into inert tiles there would strand anyone arriving on an old
# link with JavaScript off: the redirect can't run, and the note explaining the
# dead tile needs JS to appear.
# $hTag is the heading level of the name, which depends on where the grid sits:
# under an h3 group label on the home page, under an h2 on the team hub.
# $eager is for tiles that are on screen at load (the founders row at the top of
# the hub), where loading="lazy" only delays the picture everyone is looking at.
function MemberTile($p, [bool]$withStatus, [string]$grid = 'main', [bool]$forceLink = $false, [string]$hTag = 'h3', [bool]$eager = $false) {
  $finished = (IsFinished $p) -or $forceLink
  $firstName = ($p.name -split ' ')[0]
  $cls = 'member reveal'
  if (-not $p.photo) { $cls = 'member member--placeholder reveal' }
  # An unfinished profile is a <div>, not an <a>: there is nothing worth landing
  # on, and a link to a placeholder page is a dead end. js/main.js upgrades it
  # into a button that reveals the note below. Without JS it is simply inert,
  # which is the same bargain the gallery viewer makes.
  if ($finished) {
    $out = '          <a class="' + $cls + '" href="team/' + $p.slug + '.html">' + "`n"
  } else {
    $out = '          <div class="' + $cls + ' member--unfinished">' + "`n"
  }
  if ($withStatus -and $p.status) {
    $label = if ($p.status -eq 'active') { 'Active' } else { 'Former' }
    $out += '            <span class="member__status member__status--' + $p.status + '">' + $label + '</span>' + "`n"
  }
  # The "no profile yet" flag lives INSIDE the photo. As a sibling of it, it was
  # positioned against the whole tile and had to be nudged clear of the
  # Active/Former chip, which left it floating at a different height depending on
  # who it was on. Anchored to the photo it sits in one place every time.
  $flag = ''
  if (-not $finished) { $flag = '<span class="member__flag">No profile yet</span>' }
  if ($p.photo) {
    $imgCls = ''
    if ($p.thumbClass) { $imgCls = ' class="' + $p.thumbClass + '"' }
    $imgStyle = ''
    if ($p.thumbStyle) { $imgStyle = ' style="' + $p.thumbStyle + '"' }
    $zoomed = $p.thumbClass -match 'is-zoomed'
    $set = SrcSetFor $p.photo $(if ($zoomed) { $thumbWidthsZoomed } else { $thumbWidths })
    $src = $p.photo
    $responsive = ''
    if ($set) {
      $src = $set.src
      $sizes = if ($grid -eq 'founders') {
        if ($zoomed) { $founderSizesZoomed } else { $founderSizes }
      } else {
        if ($zoomed) { $thumbSizesZoomed } else { $thumbSizes }
      }
      $responsive = ' srcset="' + $set.srcset + '" sizes="' + $sizes + '"'
    }
    $loading = if ($eager) { ' decoding="async"' } else { ' loading="lazy"' }
    $out += '            <div class="member__photo"><img src="' + $src + '"' + $responsive + ' alt=""' + $loading + $imgCls + $imgStyle + '>' + $flag + '</div>' + "`n"
  } else {
    $out += '            <div class="member__photo member__photo--empty"><span aria-hidden="true">' + (HtmlEnc $p.initials) + '</span>' + $flag + '</div>' + "`n"
  }
  $out += '            <' + $hTag + '>' + (HtmlEnc $p.name) + '</' + $hTag + '><p>' + (HtmlEnc (RoleDisplay $p)) + '</p>' + "`n"
  if ($finished) {
    $out += '          </a>'
  } else {
    # The flag went in with the photo above. This note is the fuller explanation,
    # revealed by js/main.js for anyone who selects the tile anyway.
    $out += '            <p class="member__soon" hidden>We haven&rsquo;t written up ' + (HtmlEnc $firstName) + '&rsquo;s profile yet. Check back soon.</p>' + "`n"
    $out += '          </div>'
  }
  return $out
}

$founders = @($team | Where-Object { $_.role -match '(?i)co-founder' })
$rest     = @($team | Where-Object { $_.role -notmatch '(?i)co-founder' })

# On the home page these grids sit inside the "Meet the Team" section, whose
# heading is an h2. The group labels are h3 under it and the names h4 under
# those; as h2s they claimed to be siblings of the section they belong to.
$teamBlock = @()
$teamBlock += '        <h3 class="team__label reveal">Founders</h3>'
$teamBlock += '        <div class="team__grid team__grid--founders">'
$teamBlock += (@($founders | ForEach-Object { MemberTile $_ $false 'founders' $false 'h4' }) -join "`n")
$teamBlock += '        </div>'
$teamBlock += ''
# Without this second label the studio tiles below sit under "Founders" in the
# heading outline, which is what a screen reader announces them as.
$teamBlock += '        <h3 class="team__label reveal">The studio</h3>'
$teamBlock += '        <div class="team__grid">'
$teamBlock += (@($rest | ForEach-Object { MemberTile $_ $false 'main' $false 'h4' }) -join "`n")
$teamBlock += '        </div>'
$teamHtml = $teamBlock -join "`n"

# The talent pool is guest contributors and former shiverbugs, not the studio
# roster. Same tiles as the team grid, but --pool packs them tighter and smaller
# so the hierarchy reads at a glance, and each carries its Active/Former chip.
$talentHtml = @(
  '        <div class="team__grid team__grid--pool">',
  (@($talent | ForEach-Object { MemberTile $_ $true }) -join "`n"),
  '        </div>'
) -join "`n"

$indexPath = Join-Path $root 'index.html'
$index = Get-Content $indexPath -Raw -Encoding UTF8

function ReplaceBlock([string]$text, [string]$marker, [string]$body) {
  $pattern = '(?s)(<!-- BUILD:' + $marker + ':START -->).*?(<!-- BUILD:' + $marker + ':END -->)'
  if ($text -notmatch $pattern) {
    throw "Marker BUILD:$marker not found in index.html - add <!-- BUILD:$marker`:START --> / <!-- BUILD:$marker`:END --> around the block."
  }
  return [regex]::Replace($text, $pattern, { param($m) $m.Groups[1].Value + "`n" + $body + "`n        " + $m.Groups[2].Value })
}

$index = ReplaceBlock $index 'TEAM' $teamHtml
$index = ReplaceBlock $index 'TALENT' $talentHtml
WriteFileUtf8 $indexPath $index
Write-Host "Updated the team grids in index.html"

# ---------- the intake faces on join.html ----------
#
# The join page argues that most of the studio arrived through the Teesside
# intake, and these people are the evidence for it. A row each: the photo and the
# role come from data/team.json like every other face on the site, so a new photo
# has one place to change, and the sentence beside it lives here because it is
# written for this page and exists nowhere else.
#
# Keep the notes to things a reader can verify from the profile it links to. A
# slug that is not in the roster fails the build rather than quietly leaving a
# gap on the page.
#
# The order is by how much weight the evidence carries with someone deciding
# whether to apply, not by how good anyone is, which is not a thing this file
# could know. A shipped commercial title outranks a named award, a named award
# outranks a degree classification, and a classification on its own comes last.
# Three of the seven people who came in this way are here because the other four
# have no course, class or credit written down anywhere for a stranger to weigh.
# Only people still on the studio roster belong here: the page says these are
# people on the intake right now, so someone who has moved on to the talent pool
# comes off this list even though they arrived the same way.
$joinFaces = @(
  @{ slug = 'kyle-kerr'
     note = "Shipped Fallout 76: Burning Springs as a placement level designer in 2025, then graduated from Teesside in 2026. He had been building levels for a decade before that, starting in Halo: Reach's Forge." },
  @{ slug = 'oliver-neal'
     note = "First Class Honours in Games Development, and a final-year project that won Teesside's Best Games Programming award. Writes the gameplay in Unity and C#." },
  @{ slug = 'charlie-ashall'
     note = 'First Class Honours in Game Design, working in Unreal and Unity, and taking a masters in Game Design alongside the job.' }
)

$joinRows = @()
foreach ($face in $joinFaces) {
  $person = $team | Where-Object { $_.slug -eq $face.slug } | Select-Object -First 1
  if (-not $person) { throw "join.html face '$($face.slug)' is not on the studio roster in data/team.json" }

  # .member__photo carries the square, the crop and the .is-zoomed transform that
  # every other thumbnail on the site already uses. Reusing it means these faces
  # are framed exactly as they are elsewhere instead of being cropped a second
  # way here, and .join-person__photo only has to set the size.
  $zoomed = $person.thumbClass -match 'is-zoomed'
  $imgCls = ''
  if ($person.thumbClass) { $imgCls = ' class="' + $person.thumbClass + '"' }
  $imgStyle = ''
  if ($person.thumbStyle) { $imgStyle = ' style="' + $person.thumbStyle + '"' }
  # 96px box, so 240 covers 2x and 320 covers 3x. A zoomed photo is painted at
  # 1.5x its box, so it is told to ask for double.
  $set = SrcSetFor $person.photo @(240, 320)
  $src = $person.photo
  $responsive = ''
  if ($set) {
    $src = $set.src
    $sizes = if ($zoomed) { '192px' } else { '96px' }
    $responsive = ' srcset="' + $set.srcset + '" sizes="' + $sizes + '"'
  }

  $joinRows += '          <li class="join-person">'
  $joinRows += '            <div class="member__photo join-person__photo">'
  $joinRows += '              <img src="' + $src + '"' + $responsive + ' alt="" loading="lazy" decoding="async"' + $imgCls + $imgStyle + '>'
  $joinRows += '            </div>'
  $joinRows += '            <div class="join-person__copy">'
  $joinRows += '              <h3><a href="team/' + $person.slug + '.html">' + (HtmlEnc $person.name) + '</a></h3>'
  $joinRows += '              <p class="join-person__role">' + (HtmlEnc (RoleDisplay $person)) + '</p>'
  $joinRows += '              <p>' + (HtmlEnc $face.note) + '</p>'
  $joinRows += '            </div>'
  $joinRows += '          </li>'
}
$joinHtml = @(
  '        <ul class="join-people">',
  ($joinRows -join "`n"),
  '        </ul>'
) -join "`n"

$joinPath = Join-Path $root 'join.html'
$joinText = Get-Content $joinPath -Raw -Encoding UTF8
$joinPattern = '(?s)(<!-- BUILD:JOIN:START -->).*?(<!-- BUILD:JOIN:END -->)'
if ($joinText -notmatch $joinPattern) {
  throw "Marker BUILD:JOIN not found in join.html - add the marker pair around the people list."
}
$joinText = [regex]::Replace($joinText, $joinPattern, {
  param($m) $m.Groups[1].Value + "`n" + $joinHtml + "`n        " + $m.Groups[2].Value
})
WriteFileUtf8 $joinPath $joinText
Write-Host "Updated the intake faces in join.html"

# ---------- legacy ?p= redirect shim ----------

# The slug map is a real .js file, not an inline <script>, so team-member.html can
# run under the same strict CSP as every other page.
$mapLines = (@($all | ForEach-Object { "    '" + $_.id + "': '" + $_.slug + "'" }) -join ",`n")
$redirectJs = @"
// Generated by tools/build-team.ps1 - do not edit by hand.
// Profiles used to live at team-member.html?p=<id>. Keep those links working.
(function () {
  var MAP = {
$mapLines
  };
  var p = new URLSearchParams(location.search).get('p');
  // own keys only: ?p=constructor would otherwise find Object.prototype's
  var slug = p && Object.prototype.hasOwnProperty.call(MAP, p) ? MAP[p] : null;
  if (slug) location.replace('team/' + slug + '.html' + location.hash);
})();
"@
WriteFileUtf8 (Join-Path $root 'js\legacy-redirect.js') $redirectJs
Write-Host "Wrote js/legacy-redirect.js"

$listHtml = @(
  '      <div class="team__grid">',
  (@($all | ForEach-Object { MemberTile $_ $false 'main' $true }) -join "`n"),
  '      </div>'
) -join "`n"

$shimPath = Join-Path $root 'team-member.html'
$shim = Get-Content $shimPath -Raw -Encoding UTF8

function ReplaceIn([string]$text, [string]$marker, [string]$body, [string]$indent) {
  $pattern = '(?s)(<!-- BUILD:' + $marker + ':START -->).*?(<!-- BUILD:' + $marker + ':END -->)'
  if ($text -notmatch $pattern) { throw "Marker BUILD:$marker not found in team-member.html" }
  return [regex]::Replace($text, $pattern, { param($m) $m.Groups[1].Value + "`n" + $body + "`n" + $indent + $m.Groups[2].Value })
}

$shim = ReplaceIn $shim 'REDIRECT-LIST' $listHtml '      '
WriteFileUtf8 $shimPath $shim
Write-Host "Updated the legacy profile list in team-member.html"

# ---------- team/index.html : a real hub page at a clean URL ----------

$teamIndexTemplate = @'
<!DOCTYPE html>
<html lang="en-GB">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta http-equiv="Content-Security-Policy" content="{{CSP}}">
  <title>The Team | Shiverbug Studios</title>
  <meta name="description" content="{{DESC}}">
  <link rel="canonical" href="{{BASE}}/team/">
  <meta property="og:title" content="The Team | Shiverbug Studios">
  <meta property="og:description" content="{{DESC}}">
  <meta property="og:image" content="{{BASE}}/assets/img/founders.jpg">
  <meta property="og:url" content="{{BASE}}/team/">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="Shiverbug Studios">
  <meta property="og:locale" content="en_GB">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="The Team | Shiverbug Studios">
  <meta name="twitter:description" content="{{DESC}}">
  <meta name="twitter:image" content="{{BASE}}/assets/img/founders.jpg">
  <meta name="theme-color" content="#050b13">
  <link rel="icon" type="image/png" href="../assets/img/favicon.png">
  <link rel="apple-touch-icon" href="../assets/img/favicon.png">
  <link rel="preload" href="../assets/fonts/bricolage-grotesque-latin.woff2" as="font" type="font/woff2" crossorigin>
  <link rel="preload" href="../assets/fonts/instrument-sans-latin.woff2" as="font" type="font/woff2" crossorigin>
  <link rel="stylesheet" href="../css/style.min.css">
  <script>document.documentElement.classList.add('js')</script>
  <script type="application/ld+json">
{{JSONLD}}
  </script>
</head>
<body>

  <a class="skip-link" href="#top">Skip to content</a>

  <!-- ======= NAV ======= -->
  <header class="nav" id="nav">
    <div class="nav__inner">
      <a class="nav__brand" href="../" aria-label="Shiverbug Studios, home"><img src="../assets/img/nav-wordmark.webp" alt="" class="nav__wordmark" width="316" height="138"></a>
      <nav class="nav__links" id="navLinks" aria-label="Primary">
        <a href="../#services">Co-Dev</a>
        <a href="../games.html">Our Games</a>
        <a href="../#studio">Studio</a>
        <a href="./" aria-current="page">Team</a>
        <a href="../join.html">Join Us</a>
        <a href="../press.html">Press</a>
        <a class="nav__cta" href="../#contact">Get in touch</a>
      </nav>
      <button class="nav__burger" id="navBurger" aria-label="Open menu" aria-expanded="false" aria-controls="navLinks">
        <span></span><span></span>
      </button>
    </div>
  </header>

  <main class="profile team" id="top">
    <div class="container">
      <a class="backlink" href="../">
        <svg viewBox="0 0 16 16" aria-hidden="true"><path d="M14 8H3M7 3.5 2.5 8 7 12.5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>
        Back to home
      </a>
      <header class="section__head">
        <p class="kicker kicker--sand">The shiverbugs</p>
        <h1>Meet the <span class="underline-sand">Team</span></h1>
        <p class="section__lede">
          {{LEDE}}
        </p>
      </header>

      <h2 class="team__label">Founders</h2>
      <div class="team__grid team__grid--founders">
{{FOUNDERS}}
      </div>

      <h2 class="team__label">The studio</h2>
      <div class="team__grid">
{{CORE}}
      </div>

      <header class="section__head team__pool-head" id="talent-pool">
        <p class="kicker kicker--sand">The talent pool</p>
        <h2>Friends of the <span class="underline-sand">Studio</span></h2>
        <p class="section__lede">Brilliant people who've helped shape our games, from guest contributors to former shiverbugs.</p>
      </header>

      <div class="team__grid team__grid--pool">
{{TALENT}}
      </div>
    </div>
  </main>

  <footer class="footer footer--mini">
    <div class="container">
{{SOCIALSROW}}
      <div class="footer__meta">
        <p>&copy; <span id="year">2026</span> Shiverbug Studios Ltd &middot; North East England, UK &middot; <a class="footer__press" href="../press.html">Press kit</a> &middot; <a class="footer__press" href="../privacy.html">Privacy</a> &middot; <a class="footer__press" href="../accessibility.html">Accessibility</a></p>
        <p class="footer__tag">Bringing family game night back to the sofa.</p>
        <p class="footer__legal">{{LEGAL}}</p>
      </div>
    </div>
  </footer>

  <script src="../js/main.js"></script>
  <!-- Analytics: GoatCounter. Cookieless, no personal data, no consent banner needed. -->
  <script data-goatcounter="https://oliverneal04.goatcounter.com/count" async src="https://gc.zgo.at/count.js"></script>
</body>
</html>
'@

$teamCount = @($team).Count
$talentCount = @($talent).Count
# Kept under the same 158 characters as the profile descriptions. The old one
# ran to 204 and lost its last sentence in the search result anyway.
$hubDesc = "The $teamCount designers, artists and programmers building Out of Water at Shiverbug Studios in North East England, plus $talentCount friends of the studio."
$hubLede = "Everyone who makes Shiverbug work. Click anyone to read their story, see their portfolio and find them elsewhere."

# ItemList of every person, so one fetch of /team/ gives a crawler the whole roster
$listItems = @()
$pos = 0
foreach ($p in $all) {
  $pos++
  $listItems += [ordered]@{
    '@type'    = 'ListItem'
    'position' = $pos
    'item'     = [ordered]@{
      '@type'    = 'Person'
      '@id'      = "$baseUrl/team/$($p.slug).html#person"
      'name'     = $p.name
      'jobTitle' = (RoleDisplay $p)
      'url'      = "$baseUrl/team/$($p.slug).html"
    }
  }
}
$hubLd = [ordered]@{
  '@context'   = 'https://schema.org'
  '@type'      = 'CollectionPage'
  '@id'        = "$baseUrl/team/"
  'url'        = "$baseUrl/team/"
  'name'       = 'The Team | Shiverbug Studios'
  'description' = $hubDesc
  'isPartOf'   = @{ '@id' = "$baseUrl/#website" }
  'about'      = @{ '@id' = "$baseUrl/#studio" }
  'dateModified' = (PageDate 'team/index.html')
  'inLanguage' = 'en-GB'
  'breadcrumb' = [ordered]@{
    '@type'           = 'BreadcrumbList'
    'itemListElement' = @(
      [ordered]@{ '@type' = 'ListItem'; 'position' = 1; 'name' = 'Shiverbug Studios'; 'item' = "$baseUrl/" },
      [ordered]@{ '@type' = 'ListItem'; 'position' = 2; 'name' = 'Team' }
    )
  }
  'mainEntity' = [ordered]@{
    '@type'           = 'ItemList'
    'numberOfItems'   = $all.Count
    'itemListElement' = $listItems
  }
}

$hubHtml = $teamIndexTemplate.
  Replace('{{CSP}}',    (HtmlEnc $csp)).
  Replace('{{LEGAL}}',  (HtmlEnc $legal)).
  Replace('{{SOCIALSROW}}', (FooterSocialsHtml '      ')).
  Replace('{{BASE}}',   $baseUrl).
  Replace('{{DESC}}',   (HtmlEnc $hubDesc)).
  Replace('{{LEDE}}',   (HtmlEnc $hubLede)).
  Replace('{{JSONLD}}', (($hubLd | ConvertTo-Json -Depth 12).Replace('<', '\u003c'))).
  Replace('{{FOUNDERS}}', (@($founders | ForEach-Object { MemberTile $_ $false 'founders' $false 'h3' $true }) -join "`n")).
  Replace('{{CORE}}',     (@($rest     | ForEach-Object { MemberTile $_ $false }) -join "`n")).
  Replace('{{TALENT}}',   (@($talent   | ForEach-Object { MemberTile $_ $true  }) -join "`n"))

# MemberTile emits root-relative paths for index.html; inside team/ they need one
# level up. A srcset holds several of them, so the comma-separated entries after
# the first need the same treatment as the one in the attribute's opening quote.
$hubHtml = $hubHtml.Replace('href="team/', 'href="').
                    Replace('="assets/', '="../assets/').
                    Replace(', assets/', ', ../assets/')
WriteFileUtf8 (Join-Path $teamDir 'index.html') $hubHtml
Write-Host "Wrote the team hub page at team/index.html"

# ---------- llms.txt : a curated map for AI agents ----------

$llms = @()
$llms += '# Shiverbug Studios'
$llms += ''
$llms += '> Independent video game studio in North East England, founded in 2025. Building Out of Water, a 2-player split-screen collectathon platformer, and taking on co-development and work-for-hire: concept art, 3D art, level design and gameplay programming.'
$llms += ''
$llms += ("Team of {0} people plus a talent pool of {1} regular collaborators. Contact: contact@shiverbugstudios.com" -f $teamCount, $talentCount)
$llms += ''
$llms += '## Studio'
$llms += ''
$llms += ("- [Home]({0}/): studio overview, Out of Water, the team" -f $baseUrl)
$llms += ("- [Co-development and work-for-hire]({0}/): services, galleries, packages, process, FAQ - this is the home page" -f $baseUrl)
$llms += ("- [Our games]({0}/games.html): Out of Water - a 2-player split-screen collectathon platformer built in Unity, targeting PC (Steam and Steam Deck), Xbox, PlayStation and Nintendo Switch. In development, no release date announced. Features, screenshots and development news" -f $baseUrl)
$llms += ("- [Press kit]({0}/press.html): fact sheet, logos, screenshots, trailer" -f $baseUrl)
$llms += ("- [Join us]({0}/join.html): how the Teesside University internship intake works, who came through it, and how speculative approaches from everyone else are handled. Applications for the intake go through the university, not this site" -f $baseUrl)
$llms += ("- [Privacy policy]({0}/privacy.html)" -f $baseUrl)
$llms += ("- [Accessibility statement]({0}/accessibility.html): WCAG 2.2 AA conformance, known gaps, how to report a problem" -f $baseUrl)
$llms += ''
$llms += '## Team'
$llms += ''
$llms += ("- [Full roster]({0}/team/): all {1} people, {2} in the studio plus {3} in the talent pool" -f $baseUrl, $all.Count, $teamCount, $talentCount)
# Unfinished profiles stay on the roster - they are real people on the team -
# but without a link, because the page behind it is noindexed and empty.
foreach ($p in $team) {
  if (IsFinished $p) {
    $bio = ': ' + (Truncate (StripTags (@($p.about)[0])) 150)
    $llms += ("- [{0} - {1}]({2}/team/{3}.html){4}" -f $p.name, (RoleDisplay $p), $baseUrl, $p.slug, $bio)
  } else {
    $llms += ("- {0} - {1} (no profile written up yet)" -f $p.name, (RoleDisplay $p))
  }
}
$llms += ''
$llms += '## Talent pool'
$llms += ''
foreach ($p in $talent) {
  $state = if ($p.status -eq 'former') { 'former shiverbug' } else { 'active contributor' }
  if (IsFinished $p) {
    $bio = ': ' + (Truncate (StripTags (@($p.about)[0])) 150)
    $llms += ("- [{0} - {1}]({2}/team/{3}.html) ({4}){5}" -f $p.name, (RoleDisplay $p), $baseUrl, $p.slug, $state, $bio)
  } else {
    $llms += ("- {0} - {1} ({2}, no profile written up yet)" -f $p.name, (RoleDisplay $p), $state)
  }
}

# The same profiles the footer links and sameAs claims. An assistant reading
# llms.txt to answer "where can I follow this studio?" was previously being
# handed a Linktree and left to guess.
$llms += ''
$llms += '## Elsewhere'
$llms += ''
foreach ($s in $studioSocials) {
  $llms += ("- [{0}]({1})" -f $s.label, $s.url)
}
foreach ($r in $studioRefs) {
  $llms += ("- {0}" -f $r)
}

$llms += ''
WriteFileUtf8 (Join-Path $root 'llms.txt') (($llms -join "`n") + "`n")
Write-Host "Wrote llms.txt"

# ---------- index.html structured data graph ----------

$employees = @()
foreach ($p in $team) {
  $employees += [ordered]@{
    '@type'    = 'Person'
    '@id'      = "$baseUrl/team/$($p.slug).html#person"
    'name'     = $p.name
    'jobTitle' = (RoleDisplay $p)
    'url'      = "$baseUrl/team/$($p.slug).html"
  }
}
$foundersLd = @()
foreach ($p in $founders) {
  $foundersLd += @{ '@id' = "$baseUrl/team/$($p.slug).html#person" }
}

# Out of Water, defined once and emitted on every page that refers to it.
#
# index.html, games.html and press.html all point mainEntity at #out-of-water,
# but structured data resolves per page: an @id that is only defined on the home
# page is a reference to nothing on the other two, and games.html - the page
# actually about the game - was the worst place to have that gap. Rather than
# paste the node into three files and watch them drift, the build writes it into
# each of them from here.
$gameLd = [ordered]@{
  '@type'       = 'VideoGame'
  '@id'         = "$baseUrl/#out-of-water"
  'name'        = 'Out of Water'
  'url'         = "$baseUrl/games.html"
  'description' = 'A 2-player split-screen collectathon platformer. One player is a turtle, the other a seagull, exploring a colourful world full of charm, clever challenges and an army of crabs.'
  'image'       = "$baseUrl/assets/img/out-of-water-screenshot.jpg"
  'screenshot'  = @(
    "$baseUrl/assets/press/oow-screenshot-cove.jpg",
    "$baseUrl/assets/press/oow-screenshot-characters.jpg"
  )
  'genre'       = @('Platform game', 'Collectathon', 'Cooperative video game')
  # Target platforms, not shipped ones - the game is unreleased and carries no
  # datePublished, so nothing here reads as "buy it now". This is what answers
  # "what can I play it on?" for a search engine or an AI agent.
  # Steam is a store, not a platform, so it is not listed; Steam Deck is hardware.
  'gamePlatform' = @('PC', 'Steam Deck', 'Xbox', 'PlayStation', 'Nintendo Switch')
  'gameEngine'  = 'Unity'
  'playMode'    = 'https://schema.org/CoOp'
  'numberOfPlayers' = [ordered]@{ '@type' = 'QuantitativeValue'; 'minValue' = 2; 'maxValue' = 2 }
  'author'      = @{ '@id' = "$baseUrl/#studio" }
  'publisher'   = @{ '@id' = "$baseUrl/#studio" }
  'inLanguage'  = 'en'
}

$siteLd = [ordered]@{
  '@context' = 'https://schema.org'
  '@graph'   = @(
    [ordered]@{
      '@type'       = 'Organization'
      '@id'         = "$baseUrl/#studio"
      'name'        = 'Shiverbug Studios'
      'legalName'   = 'Shiverbug Studios Ltd'
      'url'         = "$baseUrl/"
      'logo'        = "$baseUrl/assets/press/shiverbug-logo.png"
      'image'       = "$baseUrl/assets/img/out-of-water-screenshot.jpg"
      'email'       = 'contact@shiverbugstudios.com'
      'foundingDate' = '2025'
      'description' = 'Indie game development studio in North East England making couch co-op games, including debut title Out of Water, and offering co-development services: concept art, 3D art, level design and gameplay programming.'
      # The registered office, the same address the footer discloses on every page.
      'address'     = [ordered]@{
        '@type'           = 'PostalAddress'
        'streetAddress'   = 'Victoria Building, Victoria Road'
        'addressLocality' = 'Middlesbrough'
        'postalCode'      = 'TS1 3AP'
        'addressRegion'   = 'North East England'
        'addressCountry'  = 'GB'
      }
      'award'       = 'Tranzfuser 2025 Public Vote Winner, ProtoPlay 2025'
      'numberOfEmployees' = [ordered]@{ '@type' = 'QuantitativeValue'; 'value' = $teamCount }
      'knowsAbout'  = @('Video Game Development', 'Concept Art', '3D Art', 'Level Design', 'Gameplay Programming', 'Unity', 'Unreal Engine', 'Co-development')
      'founder'     = $foundersLd
      'employee'    = $employees
      'sameAs'      = $studioSameAs
    },
    [ordered]@{
      '@type'       = 'WebSite'
      '@id'         = "$baseUrl/#website"
      'url'         = "$baseUrl/"
      'name'        = 'Shiverbug Studios'
      'publisher'   = @{ '@id' = "$baseUrl/#studio" }
      'inLanguage'  = 'en-GB'
    },
    # The home page had no node of its own: every subpage declared a WebPage,
    # CollectionPage or ProfilePage and pointed isPartOf at #website, while the
    # page doing the pointing-at was missing from its own graph. This is also
    # the only place a dateModified for the home page can live.
    [ordered]@{
      '@type'       = 'WebPage'
      '@id'         = "$baseUrl/#webpage"
      'url'         = "$baseUrl/"
      'name'        = 'Shiverbug Studios | Game Co-Development and Work-for-Hire'
      'description' = 'Shiverbug Studios: an indie game studio in North East England. Co-development, concept art and 3D art for studios, plus our couch co-op game, Out of Water.'
      'isPartOf'    = @{ '@id' = "$baseUrl/#website" }
      'about'       = @{ '@id' = "$baseUrl/#studio" }
      'primaryImageOfPage' = "$baseUrl/assets/img/out-of-water-screenshot.jpg"
      'dateModified' = (PageDate 'index.html')
      'inLanguage'  = 'en-GB'
    },
    $gameLd
  )
}

$siteLdJson = ($siteLd | ConvertTo-Json -Depth 12).Replace('<', '\u003c')

$index = Get-Content $indexPath -Raw -Encoding UTF8
$index = ReplaceBlock $index 'SCHEMA' ('  <script type="application/ld+json">' + "`n" + $siteLdJson + "`n" + '  </script>')
WriteFileUtf8 $indexPath $index
Write-Host "Updated the structured data graph in index.html"

# ---------- the Out of Water node on games.html and press.html ----------
#
# This goes in a second <script type="application/ld+json"> rather than inside
# the hand-written graph already on those pages, because an HTML comment cannot
# sit inside a JSON block without breaking the JSON - so the BUILD markers have
# to live outside the script element. Several JSON-LD blocks on one page is
# valid and a crawler merges them.
#
# The stub node alongside it carries only the page's own @id and a dateModified.
# Nodes that share an @id merge, so that hangs a build-stamped date on the
# CollectionPage / AboutPage declared above it without this script having to own
# those hand-written nodes.
$gamePages = @(
  @{ file = 'games.html'; id = "$baseUrl/games.html" },
  @{ file = 'press.html'; id = "$baseUrl/press.html" }
)
foreach ($gp in $gamePages) {
  $path = Join-Path $root $gp.file
  $text = Get-Content $path -Raw -Encoding UTF8
  if ($text -notmatch '<!-- BUILD:GAME:START -->') {
    throw "Marker BUILD:GAME not found in $($gp.file) - add the marker pair after the existing JSON-LD block."
  }
  $gameGraph = [ordered]@{
    '@context' = 'https://schema.org'
    '@graph'   = @(
      $gameLd,
      [ordered]@{ '@id' = $gp.id; 'dateModified' = (PageDate $gp.file) }
    )
  }
  $gameJson = ($gameGraph | ConvertTo-Json -Depth 12).Replace('<', '\u003c')
  $gameBlock = '  <script type="application/ld+json">' + "`n" + $gameJson + "`n" + '  </script>'
  $text = [regex]::Replace($text, '(?s)(<!-- BUILD:GAME:START -->).*?(<!-- BUILD:GAME:END -->)', {
    param($m) $m.Groups[1].Value + "`n" + $gameBlock + "`n  " + $m.Groups[2].Value
  })
  WriteFileUtf8 $path $text
  Write-Host "Wrote the Out of Water node into $($gp.file)"
}

# ---------- WebPage graphs for the flat pages ----------
#
# privacy.html and accessibility.html carried no structured data at all, so they
# sat outside the graph the rest of the site builds: nothing tied them to the
# studio, and neither could offer a dateModified. That matters more than it
# looks for the accessibility statement, which is a dated claim about a moving
# target - "as of when?" is the first thing anyone checks.
#
# The descriptions here must stay in step with each page's own meta description.
# validate-site.ps1 fails the build if they drift.
$flatPages = @(
  @{
    file  = 'page-join'
    path  = 'join.html'
    name  = 'Join Us | Shiverbug Studios'
    crumb = 'Join Us'
    desc  = "Everyone at Shiverbug who isn't a founder joined as an intern. How the Teesside intake works, and how to approach us if you're not on it."
  },
  @{
    file  = 'policy-privacy'
    path  = 'privacy.html'
    name  = 'Privacy | Shiverbug Studios'
    crumb = 'Privacy'
    desc  = 'How Shiverbug Studios handles your data. Short version: we collect almost nothing, and we never sell it.'
  },
  @{
    file  = 'policy-accessibility'
    path  = 'accessibility.html'
    name  = 'Accessibility | Shiverbug Studios'
    crumb = 'Accessibility'
    desc  = "How accessible the Shiverbug Studios website is, what we've tested, what we know isn't perfect yet, and how to tell us if something doesn't work for you."
  }
)
foreach ($pp in $flatPages) {
  $path = Join-Path $root $pp.path
  $text = Get-Content $path -Raw -Encoding UTF8
  if ($text -notmatch '<!-- BUILD:PAGE:START -->') {
    throw "Marker BUILD:PAGE not found in $($pp.path) - add the marker pair before </head>."
  }
  $pageLd = [ordered]@{
    '@context' = 'https://schema.org'
    '@graph'   = @(
      [ordered]@{
        '@type'        = 'WebPage'
        '@id'          = "$baseUrl/$($pp.path)"
        'url'          = "$baseUrl/$($pp.path)"
        'name'         = $pp.name
        'description'  = $pp.desc
        'isPartOf'     = @{ '@id' = "$baseUrl/#website" }
        'about'        = @{ '@id' = "$baseUrl/#studio" }
        'dateModified' = (PageDate $pp.path)
        'inLanguage'   = 'en-GB'
      },
      [ordered]@{
        '@type'           = 'BreadcrumbList'
        'itemListElement' = @(
          [ordered]@{ '@type' = 'ListItem'; 'position' = 1; 'name' = 'Shiverbug Studios'; 'item' = "$baseUrl/" },
          [ordered]@{ '@type' = 'ListItem'; 'position' = 2; 'name' = $pp.crumb }
        )
      }
    )
  }
  $pageJson = ($pageLd | ConvertTo-Json -Depth 12).Replace('<', '\u003c')
  $pageBlock = '  <script type="application/ld+json">' + "`n" + $pageJson + "`n" + '  </script>'
  $text = [regex]::Replace($text, '(?s)(<!-- BUILD:PAGE:START -->).*?(<!-- BUILD:PAGE:END -->)', {
    param($m) $m.Groups[1].Value + "`n" + $pageBlock + "`n  " + $m.Groups[2].Value
  })
  WriteFileUtf8 $path $text
  Write-Host "Wrote the WebPage graph into $($pp.path)"
}

# ---------- sitemap ----------

$pages = @(
  @{ loc = "$baseUrl/";              pri = '1.0'; file = 'index.html' },
  @{ loc = "$baseUrl/games.html";    pri = '0.9'; file = 'games.html' },
  @{ loc = "$baseUrl/team/";         pri = '0.8'; file = 'team/index.html' },
  @{ loc = "$baseUrl/press.html";    pri = '0.7'; file = 'press.html' },
  @{ loc = "$baseUrl/join.html";     pri = '0.6'; file = 'join.html' },
  @{ loc = "$baseUrl/privacy.html";  pri = '0.3'; file = 'privacy.html' },
  @{ loc = "$baseUrl/accessibility.html"; pri = '0.3'; file = 'accessibility.html' }
)
# Only finished profiles go in. The rest carry a noindex, and listing a page you
# have asked not to be indexed just sends a crawler somewhere to be turned away.
foreach ($p in $all) {
  if (-not (IsFinished $p)) { continue }
  $pages += @{ loc = "$baseUrl/team/$($p.slug).html"; pri = '0.5'; file = "team/$($p.slug).html" }
}

# lastmod comes from PageDate, defined with the other helpers at the top of this
# script because the structured data needs the same dates.

$sm = @('<?xml version="1.0" encoding="UTF-8"?>', '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">')
foreach ($pg in $pages) {
  $sm += '  <url>'
  $sm += '    <loc>' + $pg.loc + '</loc>'
  $sm += '    <lastmod>' + (PageDate $pg.file) + '</lastmod>'
  $sm += '    <priority>' + $pg.pri + '</priority>'
  $sm += '  </url>'
}
$sm += '</urlset>'
WriteFileUtf8 (Join-Path $root 'sitemap.xml') (($sm -join "`n") + "`n")
Write-Host "Updated sitemap.xml with $($pages.Count) URLs"

# ---------- footer social row, injected into the hand-written pages ----------
#
# The team pages get the row from their template. index.html, games.html and the
# rest are hand-maintained, so it travels to them through BUILD:SOCIALS markers
# instead. Any page that grows the markers picks the links up on the next build,
# and CI's drift check stops anyone editing the generated copy by hand.
$socialsRow = FooterSocialsHtml '        '
$socialPattern = '(?s)(<!-- BUILD:SOCIALS:START -->).*?(<!-- BUILD:SOCIALS:END -->)'
$socialPages = @(Get-ChildItem -Path $root -Filter *.html -Recurse |
                 Where-Object { $_.FullName -notmatch '\\_originals\\' -and $_.FullName -notmatch '\\team\\' })
$injected = @()
foreach ($f in $socialPages) {
  $text = Get-Content $f.FullName -Raw -Encoding UTF8
  if ($text -notmatch '<!-- BUILD:SOCIALS:START -->') { continue }
  $updated = [regex]::Replace($text, $socialPattern, {
    param($m) $m.Groups[1].Value + "`n" + $socialsRow + "`n        " + $m.Groups[2].Value
  })
  WriteFileUtf8 $f.FullName $updated
  $injected += $f.Name
}
Write-Host "Injected the footer social row into $($injected.Count) pages: $($injected -join ', ')"

Write-Host ""
Write-Host "Done."
