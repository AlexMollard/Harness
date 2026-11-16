#requires -Version 7
<#
  Machine -> repo. Captures the Claude Code and omp configuration this PC is
  running, so install.ps1 can rebuild it on another one.

  Secrets never enter the repo. A real API key is rewritten to an ALL_CAPS env
  var name, matching the convention models.yml already uses for GPUStack, and
  install.ps1 refuses to run until those vars are set. The export FAILS if a
  secret-shaped string survives the rewrite - better a broken export than a
  leaked key.

  Absolute home paths are rewritten to __HOME__ so another machine's username
  does not break the hooks.
#>
[CmdletBinding()]
param([switch]$WhatIf, [switch]$SkipSkills)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Cfg = Join-Path $Root 'configs'

function Save-Text {
  param([string]$Dest, [string]$Content)
  if ($WhatIf) { Write-Host "  would write $Dest" -ForegroundColor Yellow; return }
  $dir = Split-Path -Parent $Dest
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  [System.IO.File]::WriteAllText($Dest, (($Content -replace "`r`n", "`n") -replace "`n", "`r`n"))
  Write-Host "  + $($Dest.Replace($Root,'.'))" -ForegroundColor Green
}

# Portability: this machine's home -> placeholder install.ps1 expands again.
function ConvertTo-Portable { param([string]$s) $s -replace [regex]::Escape($HOME), '__HOME__' -replace [regex]::Escape($HOME.Replace('\', '\\')), '__HOME__' }

Write-Host "agent-core config export" -ForegroundColor Cyan

# --- Claude Code -----------------------------------------------------------
$s = Get-Content -Raw "$HOME/.claude/settings.json"
Save-Text (Join-Path $Cfg 'claude/settings.json') (ConvertTo-Portable $s)

# Only hooks that are actually wired in settings.json travel. The cbm-* scripts
# were unwired on 2026-09-16 and must not come back on a fresh machine.
$wired = [regex]::Matches($s, '~/\.claude/hooks/([A-Za-z0-9._-]+)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
foreach ($h in $wired) {
  $src = "$HOME/.claude/hooks/$h"
  if (Test-Path $src) { Save-Text (Join-Path $Cfg "claude/hooks/$h") (Get-Content -Raw $src) }
  else { Write-Host "  ! wired hook missing on disk: $h" -ForegroundColor Red }
}
Write-Host "  hooks exported: $($wired -join ', ')" -ForegroundColor DarkGray

# --- omp -------------------------------------------------------------------
foreach ($f in 'config.yml', 'mcp.json') {
  $src = "$HOME/.omp/agent/$f"
  if (Test-Path $src) { Save-Text (Join-Path $Cfg "omp/$f") (ConvertTo-Portable (Get-Content -Raw $src)) }
}

# models.yml carries provider API keys. Rewrite any literal key to the env-var
# name for its provider; leave values that are already env-var names alone.
$models = Get-Content "$HOME/.omp/agent/models.yml"
$provider = $null; $redacted = @()
$out = foreach ($line in $models) {
  if ($line -match '^\s{2}([A-Za-z0-9_-]+):\s*$') { $provider = $Matches[1] }
  if ($line -match '^(\s*apiKey:\s*)(.+?)\s*$') {
    $val = $Matches[2]
    if ($val -notmatch '^[A-Z][A-Z0-9_]*$') {
      $name = ($provider -replace '[^A-Za-z0-9]', '_').ToUpper() + '_API_KEY'
      $redacted += $name
      "$($Matches[1])$name"
      continue
    }
  }
  $line
}
Save-Text (Join-Path $Cfg 'omp/models.yml') ($out -join "`n")
if ($redacted) { Write-Host "  redacted to env vars: $($redacted -join ', ')" -ForegroundColor Yellow }

# --- omp managed skills ----------------------------------------------------
if (-not $SkipSkills) {
  $src = "$HOME/.omp/agent/managed-skills"
  $dst = Join-Path $Root 'skills/managed'
  if (Test-Path $src) {
    if ($WhatIf) { Write-Host "  would sync $((Get-ChildItem $src -Directory).Count) managed skills" -ForegroundColor Yellow }
    else {
      if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
      Copy-Item $src $dst -Recurse -Force
      Write-Host "  + skills/managed ($((Get-ChildItem $dst -Directory).Count) skills)" -ForegroundColor Green
    }
  }
}

# --- refuse to finish if anything secret-shaped survived --------------------
if (-not $WhatIf) {
  $patterns = 'gh[pous]_[A-Za-z0-9]{20,}', 'github_pat_[A-Za-z0-9_]{20,}', 'sk-[A-Za-z0-9_-]{20,}',
  'AKIA[0-9A-Z]{16}', 'xox[baprs]-[A-Za-z0-9-]{10,}', '-----BEGIN [A-Z ]*PRIVATE KEY',
  '[a-f0-9]{32}\.[A-Za-z0-9]{16}'          # zhipu/GLM style
  $bad = Get-ChildItem $Cfg -Recurse -File -EA SilentlyContinue | ForEach-Object {
    $t = Get-Content -Raw $_.FullName
    foreach ($p in $patterns) { if ($t -match $p) { "$($_.FullName): $p" } }
  }
  if ($bad) {
    Write-Host "`nEXPORT FAILED - secret-shaped content in configs/:" -ForegroundColor Red
    $bad | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    throw "refusing to leave secrets in the repo"
  }
  Write-Host "  secret scan: clean" -ForegroundColor Green
}

Write-Host "done. commit configs/ and skills/managed to carry this machine." -ForegroundColor Cyan
