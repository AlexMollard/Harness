#requires -Version 7
<#
  Repo -> machine. Sets up Claude Code, omp and Hermes on a fresh PC from this repo.

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
function Get-MemoryBlock {
  param([string]$Text)
  [regex]::Match($Text, '(?m)^memory:[^\r\n]*(?:\r?\n(?:[ \t]+[^\r\n]*|[ \t]*))*')
}

function Set-OmpMemoryOff {
  param([string]$Text)
  $block = Get-MemoryBlock $Text
  if (-not $block.Success) { return $Text.TrimEnd("`r", "`n") + "`nmemory:`n  backend: `"off`"`n" }
  $value = $block.Value
  if ($value -notmatch '^memory:[ \t]*(?:#.*)?(?:\r?\n|$)') {
    throw 'Cannot safely update the existing omp memory setting: expected a block mapping.'
  }
  if ($value -match '(?m)^  backend:') {
    $value = [regex]::Replace($value, '(?m)^  backend:[^\r\n]*', '  backend: "off"')
  }
  else {
    $value = [regex]::Replace($value, '^(memory:[^\r\n]*)', "`$1`n  backend: `"off`"")
  }
  return $Text.Substring(0, $block.Index) + $value + $Text.Substring($block.Index + $block.Length)
}

function Write-Crlf {
  param([string]$Path, [string]$Text)
  [System.IO.File]::WriteAllText($Path, (($Text -replace "`r`n", "`n") -replace "`n", "`r`n"))
}

function Preserve-MemorySettings {
  param([string]$Src, [string]$Dest, [string]$Text)
  if (-not (Test-Path -LiteralPath $Dest -PathType Leaf)) { return $Text }
  $old = Get-Content -Raw -LiteralPath $Dest
  if ($Src -eq (Join-Path $Cfg 'claude/settings.json')) {
    $previous = ConvertFrom-Json -InputObject $old -AsHashtable
    if ($previous.ContainsKey('autoMemoryEnabled')) {
      $settings = ConvertFrom-Json -InputObject $Text -AsHashtable
      $settings['autoMemoryEnabled'] = $previous['autoMemoryEnabled']
      return (ConvertTo-Json -InputObject $settings -Depth 100) + "`n"
    }
  }
  elseif ($Src -eq (Join-Path $Cfg 'omp/config.yml')) {
    $block = Get-MemoryBlock $old
    if ($block.Success) { return $Text.TrimEnd("`r", "`n") + "`n" + $block.Value.TrimEnd("`r", "`n") + "`n" }
  }
  return $Text
}

function Disable-CompetingMemory {
  $claudePath = Join-Path $HOME '.claude/settings.json'
  $ompPath = Join-Path $HOME '.omp/agent/config.yml'
  $claude = ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $claudePath) -AsHashtable
  $omp = Set-OmpMemoryOff (Get-Content -Raw -LiteralPath $ompPath)
  $claude['autoMemoryEnabled'] = $false
  Write-Crlf $claudePath ((ConvertTo-Json -InputObject $claude -Depth 100) + "`n")
  Write-Crlf $ompPath $omp
}


function Install-File {
  param([string]$Src, [string]$Dest)
  if (-not (Test-Path $Src)) { Warn "missing in repo: $Src"; return }
  $text = (Get-Content -Raw $Src) -replace '__HOME__', $HOME.Replace('\', '\\')
  $text = Preserve-MemorySettings $Src $Dest $text
  if ($WhatIf) {
    $state = if (Test-Path $Dest) { 'would REPLACE (backup kept)' } else { 'would create' }
    Write-Host "  $state $Dest" -ForegroundColor Yellow; return
  }
  $dir = Split-Path -Parent $Dest
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  if (Test-Path $Dest) { Copy-Item $Dest "$Dest.pre-install" -Force }
  Write-Crlf $Dest $text
  Ok $Dest.Replace($HOME, '~')
}

Write-Host "agent-core install" -ForegroundColor Cyan
if ($WhatIf) { Write-Host "(dry run - nothing will be written)" -ForegroundColor Yellow }

# --- 1. prerequisites ------------------------------------------------------
Step "1. prerequisites"
foreach ($t in @(
    @{ n = 'claude'; req = $true; why = 'Claude Code CLI' }
    @{ n = 'omp'; req = $false; why = 'omp harness' }
    @{ n = 'hermes'; req = $false; why = 'Hermes harness: iex (irm https://hermes-agent.nousresearch.com/install.ps1)' }
    @{ n = 'git'; req = $true; why = 'version control' }
    @{ n = 'node'; req = $false; why = 'optional Axiom integration requires Node.js 22+' }
    @{ n = 'rtk'; req = $false; why = 'Bash PreToolUse hook' }
  )) {
  if (Get-Command $t.n -EA SilentlyContinue) { Ok "$($t.n) found" }
  elseif ($t.req) { Bad "$($t.n) not on PATH - $($t.why)" }
  else { Warn "$($t.n) not on PATH - $($t.why)" }
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
# provider. Any other provider key is optional, so its absence is a normal, fully
# working install rather than a failure.
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
Write-Host "  owned by omp-maestro: run /maestro <ensemble> inside omp" -ForegroundColor DarkGray

# --- 5. omp managed skills -------------------------------------------------
Step "5. omp managed skills"
if ($SkipSkills) { Write-Host "  skipped (-SkipSkills)" -ForegroundColor DarkGray }
else {
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

# --- 5b. Hermes settings ---------------------------------------------------
Step "5b. Hermes settings"
if (-not (Get-Command hermes -EA SilentlyContinue)) { Write-Host "  skipped: hermes not on PATH" -ForegroundColor DarkGray }
else {
  # Hermes owns config.yaml (and migrates it); agent-core owns only these keys.
  $home_ = $HOME.Replace('\', '/')
  $sets = Get-Content (Join-Path $Cfg 'hermes/settings.yaml') |
  Where-Object { $_ -match '^([A-Za-z0-9_.]+):\s+(.+)$' } |
  ForEach-Object { [pscustomobject]@{ Key = $Matches[1]; Value = $Matches[2].Replace('__HOME__', $home_) } }
  foreach ($s in $sets) {
    if ($WhatIf) { Write-Host "  would set $($s.Key)" -ForegroundColor Yellow; continue }
    hermes config set $s.Key $s.Value | Out-Null
    if ($LASTEXITCODE -ne 0) { Bad "hermes config set $($s.Key) failed" } else { Ok $s.Key }
  }
  if (-not $WhatIf) {
    Write-Host "  shell hooks need one-time consent: run 'hermes hooks doctor' and approve if listed" -ForegroundColor DarkGray
    if (-not (hermes auth list 2>$null | Select-String 'openai-codex')) { Warn "not signed in: run 'hermes auth add openai-codex'" }
  }
}

# --- 6. wire instructions and skills --------------------------------------
Step "6. wire instructions, skills and commands"
if ($WhatIf) { Write-Host "  would run build.ps1 and sync-skills.ps1 -Link" -ForegroundColor Yellow }
else {
  & (Join-Path $Root 'build.ps1')
  & (Join-Path $Root 'sync-skills.ps1') -Link
}

Step "6b. wire optional Axiom integration"
$axiomInstaller = Join-Path $HOME 'Axiom/scripts/install.mjs'
$axiomConfig = if ($env:SHARED_BRAIN_CONFIG) { $env:SHARED_BRAIN_CONFIG } else {
  $configBase = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $HOME '.config' }
  Join-Path $configBase 'Axiom/config.json'
}
if (-not (Test-Path -LiteralPath $axiomInstaller -PathType Leaf)) {
  Write-Host "  skipped: ~/Axiom/scripts/install.mjs not found" -ForegroundColor DarkGray
}
elseif (-not (Test-Path -LiteralPath $axiomConfig -PathType Leaf)) {
  Write-Host "  skipped: private Axiom config not found ($axiomConfig)" -ForegroundColor DarkGray
}
elseif (-not (Get-Command node -EA SilentlyContinue)) {
  Warn "Axiom integration skipped: node not on PATH"
}
elseif ($WhatIf) { Write-Host "  would run ~/Axiom/scripts/install.mjs" -ForegroundColor Yellow }
else {
  & node $axiomInstaller
  if ($LASTEXITCODE -ne 0) { throw 'Axiom installation failed. Check its private configuration before retrying.' }
  Disable-CompetingMemory
}

# --- 7. prove it -----------------------------------------------------------
Step "7. verify"
if ($WhatIf) { Write-Host "  would run verify.ps1" -ForegroundColor Yellow; return }
& (Join-Path $Root 'verify.ps1') -Static
Write-Host "`nStatic wiring passed. Run ./verify.ps1 (no -Static) to prove each harness" -ForegroundColor Cyan
Write-Host "actually loads the rules - it calls each one once." -ForegroundColor Cyan
Write-Host "Anything replaced was kept alongside as <file>.pre-install." -ForegroundColor DarkGray
