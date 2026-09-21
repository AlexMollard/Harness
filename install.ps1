#requires -Version 7
<#
  Repo -> machine. Sets up Claude Code and omp on a fresh PC from this repo.

    git clone https://github.com/AlexMollard/Harness.git ~/agent-core
    cd ~/agent-core; ./install.ps1 -WhatIf     # see what it would do
    cd ~/agent-core; ./install.ps1

  Order matters: check prerequisites, then secrets, then write config, then wire
  the instruction files and skills, then prove it loaded. It stops at the first
  failed gate rather than leaving a half-configured machine.

  Existing files are never overwritten blind - each is copied to <file>.pre-install
  first. Re-running is safe: the wiring steps are idempotent.
#>
[CmdletBinding()]
param(
  [switch]$WhatIf,
  [switch]$SkipSkills,
  [switch]$Force        # proceed even if optional prerequisites are missing
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Cfg = Join-Path $Root 'configs'
$problems = @()

function Step { param([string]$m) Write-Host "`n$m" -ForegroundColor Cyan }
function Ok { param([string]$m) Write-Host "  ok   $m" -ForegroundColor Green }
function Warn { param([string]$m) Write-Host "  warn $m" -ForegroundColor Yellow }
function Bad { param([string]$m) Write-Host "  FAIL $m" -ForegroundColor Red; $script:problems += $m }

function Install-File {
  param([string]$Src, [string]$Dest)
  if (-not (Test-Path $Src)) { Warn "missing in repo: $Src"; return }
  $text = (Get-Content -Raw $Src) -replace '__HOME__', $HOME.Replace('\', '\\')
  if ($WhatIf) {
    $state = if (Test-Path $Dest) { 'would REPLACE (backup kept)' } else { 'would create' }
    Write-Host "  $state $Dest" -ForegroundColor Yellow; return
  }
  $dir = Split-Path -Parent $Dest
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  if (Test-Path $Dest) { Copy-Item $Dest "$Dest.pre-install" -Force }
  [System.IO.File]::WriteAllText($Dest, (($text -replace "`r`n", "`n") -replace "`n", "`r`n"))
  Ok $Dest.Replace($HOME, '~')
}

Write-Host "agent-core install" -ForegroundColor Cyan
if ($WhatIf) { Write-Host "(dry run - nothing will be written)" -ForegroundColor Yellow }

# --- 1. prerequisites ------------------------------------------------------
Step "1. prerequisites"
foreach ($t in @(
    @{ n = 'claude'; req = $true; why = 'Claude Code CLI' }
    @{ n = 'omp'; req = $false; why = 'omp harness' }
    @{ n = 'git'; req = $true; why = 'version control' }
    @{ n = 'rtk'; req = $false; why = 'Bash PreToolUse hook' }
  )) {
  if (Get-Command $t.n -EA SilentlyContinue) { Ok "$($t.n) found" }
  elseif ($t.req) { Bad "$($t.n) not on PATH - $($t.why)" }
  else { Warn "$($t.n) not on PATH - $($t.why); its hook will no-op" }
}

# --- 2. secrets the exported config expects --------------------------------
Step "2. secrets (export rewrote real keys to env var names)"
# Which env var each provider's key comes from.
$providerKey = @{}
$mf = Join-Path $Cfg 'omp/models.yml'
if (Test-Path $mf) {
  $p = $null
  foreach ($line in (Get-Content $mf)) {
    if ($line -match '^\s{2}([A-Za-z0-9_-]+):\s*$') { $p = $Matches[1] }
    elseif ($p -and $line -match '^\s*apiKey:\s*([A-Z][A-Z0-9_]*)\s*$') { $providerKey[$p] = $Matches[1] }
  }
}
# A key is REQUIRED only if the baseline config.yml actually routes a role at that
# provider. Anything else - zai, say - merely unlocks an overlay, so its absence is
# a normal, fully working install rather than a failure.
$used = @()
$cy = Join-Path $Cfg 'omp/config.yml'
if (Test-Path $cy) {
  $used = Select-String -Path $cy -Pattern '^\s+[A-Za-z][A-Za-z0-9_-]*:\s*([a-z0-9_-]+)/' |
  ForEach-Object { $_.Matches[0].Groups[1].Value } | Sort-Object -Unique
}
if (-not $providerKey.Count) { Ok "none required" }
foreach ($p in ($providerKey.Keys | Sort-Object)) {
  $v = $providerKey[$p]
  if ([Environment]::GetEnvironmentVariable($v)) { Ok "$v is set" }
  elseif ($p -in $used) { Bad "$v is not set - setx $v `"<value>`" then restart the shell" }
  else { Warn "$v is not set - optional; $p models stay unused" }
}

if ($problems -and -not $Force) {
  Write-Host "`nStopping: $($problems.Count) prerequisite(s) unmet. Fix them, or re-run with -Force." -ForegroundColor Red
  exit 1
}

# --- 3. config files -------------------------------------------------------
Step "3. config files"
Install-File (Join-Path $Cfg 'claude/settings.json') "$HOME/.claude/settings.json"
foreach ($h in (Get-ChildItem (Join-Path $Cfg 'claude/hooks') -File -EA SilentlyContinue)) {
  Install-File $h.FullName "$HOME/.claude/hooks/$($h.Name)"
  # parens matter: without them -and binds tighter and macOS chmods during -WhatIf
  if (-not $WhatIf -and ($IsLinux -or $IsMacOS)) { chmod +x "$HOME/.claude/hooks/$($h.Name)" 2>$null }
}
foreach ($f in 'config.yml', 'mcp.json', 'models.yml') {
  Install-File (Join-Path $Cfg "omp/$f") "$HOME/.omp/agent/$f"
}

# --- 4. omp model roles ----------------------------------------------------
Step "4. omp model roles"
if ($WhatIf) { Write-Host "  would apply configs/omp/roles.psd1 to ~/.omp/agent/config.yml" -ForegroundColor Yellow }
else { & (Join-Path $Root 'set-omp-roles.ps1') -Path "$HOME/.omp/agent/config.yml" -Mode auto | Out-Null }

# --- 5. omp managed skills -------------------------------------------------
if (-not $SkipSkills) {
  Step "5. omp managed skills"
  $src = Join-Path $Root 'skills/managed'
  $dst = "$HOME/.omp/agent/managed-skills"
  if (-not (Test-Path $src)) { Warn "skills/managed not in repo" }
  elseif ($WhatIf) { Write-Host "  would install $((Get-ChildItem $src -Directory).Count) skills -> $dst" -ForegroundColor Yellow }
  else {
    New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
    if (Test-Path $dst) { Move-Item $dst "$dst.pre-install" -Force }
    Copy-Item $src $dst -Recurse -Force
    Ok "$((Get-ChildItem $dst -Directory).Count) skills -> ~/.omp/agent/managed-skills"
  }
}

# --- 6. wire instructions and skills --------------------------------------
Step "6. wire instructions, skills and commands"
if ($WhatIf) { Write-Host "  would run build.ps1 and sync-skills.ps1 -Link" -ForegroundColor Yellow }
else {
  & (Join-Path $Root 'build.ps1')
  & (Join-Path $Root 'sync-skills.ps1') -Link
}

# --- 7. prove it -----------------------------------------------------------
Step "7. verify"
if ($WhatIf) { Write-Host "  would run verify.ps1" -ForegroundColor Yellow; return }
& (Join-Path $Root 'verify.ps1') -Static
Write-Host "`nStatic wiring passed. Run ./verify.ps1 (no -Static) to prove each harness" -ForegroundColor Cyan
Write-Host "actually loads the rules - it calls each one once." -ForegroundColor Cyan
Write-Host "Anything replaced was kept alongside as <file>.pre-install." -ForegroundColor DarkGray
