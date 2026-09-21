#requires -Version 7
<#
  Guided setup. setup.bat calls this; you can also run it directly.

  It is a front-end, not a second installer: it checks the environment, collects
  any API keys that are missing, then hands over to install.ps1, which remains
  the authoritative gate.

  Keys are read with a masked prompt and written straight to the user
  environment via .NET. Nothing is echoed, logged, or passed on a command line
  (which is why this does not shell out to setx - a process command line is
  readable by other processes while it runs).
#>
[CmdletBinding()]
param(
  [switch]$WhatIf,
  [switch]$SkipSkills,
  [switch]$NonInteractive   # CI: never prompt, just report
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Cfg = Join-Path $Root 'configs'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$e = [char]27
function Hue { param([string]$t, [string]$c = '0') "$e[${c}m$t$e[0m" }
function Head {
  param([int]$n, [string]$t)
  Write-Host ""
  Write-Host (Hue "  $n " '1;44') -NoNewline
  Write-Host (Hue " $t" '1')
}
function Row {
  param([string]$icon, [string]$c, [string]$name, [string]$note = '')
  $line = if ($note) { "$($name.PadRight(22)) $(Hue $note '90')" } else { $name }
  Write-Host "     $(Hue $icon $c) $line"
}
function Ok { param($n, $note = '') Row '✓' '32' $n $note }
function Opt { param($n, $note = '') Row '○' '33' $n $note }
function No { param($n, $note = '') Row '✗' '31' $n $note }
function Say { param([string]$t) Write-Host "       $(Hue $t '90')" }

Write-Host ""
$title = 'Harness'
$sub = 'one agent configuration for Claude Code and omp'
$w = $title.Length + 2 + $sub.Length + 2      # "  " between, one pad each side
Write-Host (Hue "  ┌$('─' * $w)┐" '36')
Write-Host (Hue '  │ ' '36') -NoNewline
Write-Host (Hue $title '1;97') -NoNewline
Write-Host "  $(Hue $sub '37') " -NoNewline
Write-Host (Hue '│' '36')
Write-Host (Hue "  └$('─' * $w)┘" '36')
if ($WhatIf) { Write-Host (Hue "     dry run - nothing will be written" '33') }

# --- 1. environment --------------------------------------------------------
# Every command here was verified against a primary source, not recalled:
# winget IDs against the live registry, Claude Code against code.claude.com/docs,
# graphify against its own README (the PyPI package really is "graphifyy" - the
# plain name is being reclaimed), omp against this machine's bun manifest.
$Tools = @(
  @{ n = 'git'; req = $true; why = 'version control'
    cmd = 'winget install --id Git.Git -e --accept-package-agreements --accept-source-agreements'
  }
  @{ n = 'claude'; req = $true; why = 'Claude Code CLI'
    cmd = 'winget install --id Anthropic.ClaudeCode -e --accept-package-agreements --accept-source-agreements'
    note = 'winget builds do not auto-update; set CLAUDE_CODE_PACKAGE_MANAGER_AUTO_UPDATE=1 if you want that'
  }
  @{ n = 'omp'; req = $false; why = 'the second harness'
    needs = 'bun'
    needsCmd = 'winget install --id Oven-sh.Bun -e --accept-package-agreements --accept-source-agreements'
    cmd = 'bun install -g @oh-my-pi/pi-coding-agent'
  }
  @{ n = 'rtk'; req = $false; why = 'token-optimising Bash proxy'
    cmd = 'winget install --id rtk-ai.rtk -e --accept-package-agreements --accept-source-agreements'
  }
  @{ n = 'graphify'; req = $false; why = 'code knowledge graph - core/40-code-discovery.md uses it'
    needs = 'uv'
    needsCmd = 'winget install --id astral-sh.uv -e --accept-package-agreements --accept-source-agreements'
    cmd = 'uv tool install graphifyy'
    note = 'run "graphify install" afterwards to finish setup'
  }
)

# A winget or uv install lands outside this process's PATH, so a re-check would
# wrongly report failure without this.
function Sync-Path {
  $env:Path = @(
    [Environment]::GetEnvironmentVariable('Path', 'Machine')
    [Environment]::GetEnvironmentVariable('Path', 'User')
  ) -join ';'
}

function Invoke-Offered {
  param([string]$Label, [string]$Cmd)
  Say "would run: $Cmd"
  if ($NonInteractive -or $WhatIf) { Say '(not offered in this mode)'; return $false }
  if ((Read-Host "       Install $Label now? [y/N]") -notmatch '^(y|yes)$') { Say 'skipped'; return $false }
  Write-Host ""
  Invoke-Expression $Cmd
  Write-Host ""
  Sync-Path
  return $true
}

Head 1 'Environment'
$missing = @()
Ok "PowerShell $($PSVersionTable.PSVersion)"
foreach ($t in $Tools) {
  if (Get-Command $t.n -EA SilentlyContinue) { Ok $t.n; continue }

  if ($t.req) { No $t.n $t.why } else { Opt $t.n $t.why }

  # Bootstrap whatever installs it (bun for omp, uv for graphify) first.
  if ($t.needs -and -not (Get-Command $t.needs -EA SilentlyContinue)) {
    Say "$($t.n) is installed by $($t.needs), which is also missing."
    [void](Invoke-Offered $t.needs $t.needsCmd)
    if (-not (Get-Command $t.needs -EA SilentlyContinue)) {
      Say "Without $($t.needs) there is no way to install $($t.n)."
      if ($t.req) { $missing += $t }
      continue
    }
  }

  [void](Invoke-Offered $t.n $t.cmd)
  if (Get-Command $t.n -EA SilentlyContinue) {
    Ok $t.n 'installed'
    if ($t.note) { Say $t.note }
  }
  elseif ($t.req) { $missing += $t }
}
if ($missing) {
  Write-Host ""
  Say 'Still missing something required. Install it, then run setup again:'
  foreach ($m in $missing) { Say "  $($m.cmd)" }
  Write-Host ""
  exit 1
}

# --- 2. credentials --------------------------------------------------------
Head 2 'Credentials'

# Which env var each provider's key comes from, and whether the baseline config
# actually routes a role at that provider. Same rule install.ps1 applies: a key
# is only required if something would break without it.
$providerKey = [ordered]@{}
$mf = Join-Path $Cfg 'omp/models.yml'
if (Test-Path $mf) {
  $p = $null
  foreach ($line in (Get-Content $mf)) {
    if ($line -match '^\s{2}([A-Za-z0-9_-]+):\s*$') { $p = $Matches[1] }
    elseif ($p -and $line -match '^\s*apiKey:\s*([A-Z][A-Z0-9_]*)\s*$') { $providerKey[$p] = $Matches[1] }
  }
}
$used = @()
$cy = Join-Path $Cfg 'omp/config.yml'
if (Test-Path $cy) {
  $used = Select-String -Path $cy -Pattern '^\s+[A-Za-z][A-Za-z0-9_-]*:\s*([a-z0-9_-]+)/' |
  ForEach-Object { $_.Matches[0].Groups[1].Value } | Sort-Object -Unique
}
# What an optional key buys you, straight from the role policy.
$unlocks = @{}
$rp = Join-Path $Cfg 'omp/roles.psd1'
if (Test-Path $rp) {
  foreach ($o in (Import-PowerShellDataFile $rp).overlays) { $unlocks[$o.key] = $o.why }
}

function Read-Secret {
  param([string]$Name)
  $sec = Read-Host "       Paste $Name (blank to skip)" -AsSecureString
  if ($sec.Length -eq 0) { return $null }
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

$blocked = $false
foreach ($prov in $providerKey.Keys) {
  $v = $providerKey[$prov]
  $required = $prov -in $used
  $tag = if ($required) { 'required' } else { 'optional' }
  $cur = [Environment]::GetEnvironmentVariable($v, 'User')
  if (-not $cur) { $cur = [Environment]::GetEnvironmentVariable($v) }

  if ($cur) { Ok $v "$tag - already set"; continue }
  if ($required) { No $v "$tag - $prov models will not work" } else { Opt $v "$tag" }
  if ($unlocks[$v]) { Say $unlocks[$v] }

  if ($NonInteractive -or $WhatIf) {
    if ($required) { $blocked = $true }
    Say "(skipped - no prompt in this mode)"
    continue
  }

  $val = Read-Secret $v
  if (-not $val) {
    if ($required) { Say "Skipped, but $prov roles need it. Set it and re-run."; $blocked = $true }
    else { Say "Skipped. Claude models are used instead." }
    continue
  }
  [Environment]::SetEnvironmentVariable($v, $val, 'User')  # persists
  Set-Item "env:$v" $val                                    # and this session
  $val = $null
  Ok $v "$tag - saved"
}
if (-not $providerKey.Count) { Say 'none needed' }
if ($blocked) {
  Write-Host ""
  Write-Host (Hue "  ✗ A required key is missing - set it and run setup again." '1;31')
  # A dry run still walks the rest so you can see the whole plan, but it must not
  # end by claiming success it could not deliver.
  if (-not $WhatIf) { exit 1 }
}

# --- 3. hand over ----------------------------------------------------------
Head 3 'Install'
Write-Host ""
$a = @{}
if ($WhatIf) { $a.WhatIf = $true }
if ($SkipSkills) { $a.SkipSkills = $true }

& (Join-Path $Root 'install.ps1') @a
$code = $LASTEXITCODE

Write-Host ""
if ($code) {
  Write-Host (Hue "  ✗ Setup stopped - see above." '1;31')
  exit $code
}
if ($blocked) {
  Write-Host (Hue "  ✗ Dry run finished, but a required key is missing." '1;31')
  exit 1
}
Write-Host (Hue "  ✓ Ready." '1;32')
Say "Open a NEW terminal so the environment variables take effect."
Say "Then: ./verify.ps1   (proves each harness really loads the rules)"
Write-Host ""
