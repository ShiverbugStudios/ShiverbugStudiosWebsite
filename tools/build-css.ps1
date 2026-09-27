# ============================================================
# Shiverbug Studios - stylesheet build
#
# Reads css/style.css and writes css/style.min.css, which is what every page
# actually links.
#
# Why this exists: style.css is written to be read. Its comments explain why each
# decision was made, and they are worth keeping - but they were 43% of the file,
# and a stylesheet blocks rendering, so every first visit downloaded ~23 KB of
# gzipped prose before it could paint anything. This keeps the commented source
# as the thing you edit and ships the same rules without the essay.
#
# It only strips comments and blank space. It does not rename, merge, reorder or
# "optimise" a single rule, so there is nothing here that can change how the site
# looks - diff the two files if you ever need to convince yourself of that.
#
# Run it after touching css/style.css (CI fails if you forget, the same drift
# check that covers the team pages):
#   powershell -ExecutionPolicy Bypass -File tools/build-css.ps1
#
# Keep this file pure ASCII - see tools/README.md.
# ============================================================

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$src  = Join-Path $root 'css\style.css'
$dst  = Join-Path $root 'css\style.min.css'

$css = [System.IO.File]::ReadAllText($src, [System.Text.Encoding]::UTF8)

# Strings first in the alternation, so a "/*" inside a quoted url() or content
# value is matched as part of the string and handed back untouched, and only a
# real comment is dropped.
$pattern = '("(?:\\.|[^"\\])*"|''(?:\\.|[^''\\])*'')|/\*[\s\S]*?\*/'
$css = [regex]::Replace($css, $pattern, {
  param($m)
  if ($m.Groups[1].Success) { return $m.Value }
  return ''
})

# Leading indentation, trailing space and blank lines carry no meaning in CSS.
$css = $css.Replace("`r`n", "`n")
$css = [regex]::Replace($css, '(?m)^[ \t]+', '')
$css = [regex]::Replace($css, '(?m)[ \t]+$', '')
$css = [regex]::Replace($css, '\n{2,}', "`n")
$css = $css.Trim()

$header = '/* Generated from css/style.css by tools/build-css.ps1 - edit that file, not this one. */'
$out = $header + "`n" + $css + "`n"
# CRLF and no BOM, matching every other generated file in the working tree
$out = $out.Replace("`n", "`r`n")
[System.IO.File]::WriteAllText($dst, $out, (New-Object System.Text.UTF8Encoding($false)))

$before = (Get-Item $src).Length
$after  = (Get-Item $dst).Length
Write-Host ("Wrote css/style.min.css: {0:N0} bytes, from {1:N0} ({2:P0} smaller)" -f $after, $before, (1 - $after / $before))
