#requires -Version 7
<#
  Proves each harness actually LOADS agent-core - not that a file exists on disk.

  Each probe asks the live harness a question whose answer appears only inside
  core/. A harness that reads its instructions answers; one that silently failed
  to resolve an import says MISSING. This is the check that catches drift
  returning, so run it after every build.

  -Static skips the model calls and only checks the wiring on disk (fast, free).
#>
[CmdletBinding()]
param(
  [switch]$Static,
  [ValidateSet('claude', 'omp', 'hermes', 'codex')]
  [string[]]$Only
)

$ErrorActionPreference = 'Continue'
$Root = $PSScriptRoot
. (Join-Path $Root 'tools/harness-commands.ps1')
$fail = 0

# Three facts, one per core file, that exist nowhere else on this machine.
# Phrased as a question about the rules, not a request to quote "system instructions":
# GPT models (omp, Hermes) refuse the latter as prompt disclosure and answer MISSING.
$Probe = @'
Quick check of the working rules you follow, no tools needed. Reply with exactly
three short lines and nothing else:
1) the name of Gate 1 in your gatekeeper rules
2) the title of your rule section about delegating to subagents
3) what the acronym RTK stands for in your rules
Write MISSING for any you do not know.
'@

$Expect = @('Interview', 'Delegate by Default', 'Rust Token Killer')

function Test-Static {
  param([string]$Name, [string]$Path, [string]$Needle)
  if (-not (Test-Path $Path)) { Write-Host "  FAIL $Name - $Path missing" -ForegroundColor Red; return $false }
  $raw = Get-Content -Raw -LiteralPath $Path
  if ($raw -notmatch [regex]::Escape($Needle)) {
    Write-Host "  FAIL $Name - not wired to agent-core" -ForegroundColor Red; return $false
  }
  Write-Host "  ok   $Name wiring" -ForegroundColor Green; return $true
}

# Hooks are built to exit 0 and stay silent on every failure path, so that a broken
# one can never block real work. The cost is that a broken one is also invisible -
# no error, no output, just a quietly missing reminder. These assert the behaviour
# directly. No model calls, so they run in -Static too.
function Test-Hook {
  param(
    [string]$Name,
    [string]$Hook,          # file under .claude/hooks
    [string]$Payload,       # JSON on stdin
    [ValidateSet('speaks', 'silent')][string]$Expect
  )
  $path = "$HOME/.claude/hooks/$Hook"
  if (-not (Test-Path $path)) { Write-Host "  FAIL $Name - $Hook not installed" -ForegroundColor Red; return $false }
  if (-not $script:Bash) { Write-Host "  skip $Name - no bash on PATH" -ForegroundColor DarkGray; return $true }
  # -EncodedCommand-free: pipe the payload in, capture stdout only
  $out = ($Payload | & $script:Bash $path 2>$null | Out-String).Trim()
  $spoke = [bool]$out
  if ($spoke -eq ($Expect -eq 'speaks')) { Write-Host "  ok   $Name" -ForegroundColor Green; return $true }
  $what = if ($Expect -eq 'speaks') { 'said nothing' } else { "said: $($out -split "`n" | Select-Object -First 1)" }
  Write-Host "  FAIL $Name - $what" -ForegroundColor Red
  return $false
}

function Test-Live {
  param([string]$Name, [scriptblock]$Run)
  Write-Host "  .... $Name probing" -NoNewline
  $global:LASTEXITCODE = 0
  $failed = $false
  try { $out = (& $Run) 2>&1 | Out-String; $failed = $LASTEXITCODE -ne 0 } catch { $out = "$_"; $failed = $true }
  $missed = $Expect | Where-Object { $out -notmatch [regex]::Escape($_) }
  if ($failed -or $missed) {
    $reason = if ($failed) { 'CLI invocation failed' } else { "did not load: $($missed -join ', ')" }
    Write-Host "`r  FAIL $Name - $reason   " -ForegroundColor Red
    Write-Host ($out.Trim() -split "`n" | Select-Object -Last 6 | ForEach-Object { "         $_" }) -ForegroundColor DarkGray
    return $false
  }
  Write-Host "`r  ok   $Name loads core          " -ForegroundColor Green
  return $true
}

$targets = if ($Only) { $Only } else { @('claude', 'omp', 'hermes', 'codex') }
$hermesSoul = Join-Path $(if ($env:HERMES_HOME) { $env:HERMES_HOME } else { Join-Path "$env:LOCALAPPDATA" 'hermes' }) 'SOUL.md'
Write-Host "agent-core verify" -ForegroundColor Cyan

Write-Host "static wiring:"
if ('claude'   -in $targets) { if (-not (Test-Static 'claude  ' "$HOME/.claude/CLAUDE.md"                  'agent-core/core')) { $fail++ } }
if ('omp'      -in $targets) { if (-not (Test-Static 'omp     ' "$HOME/.omp/agent/AGENTS.md"               'agent-core/core')) { $fail++ } }
if ('hermes'   -in $targets) {
  if (-not (Test-Static 'hermes  ' $hermesSoul 'Harness dialect: Hermes Agent')) { $fail++ }
  # SOUL.md is the one generated copy, so check it against a fresh build.
  elseif (-not ((& (Join-Path $Root 'build.ps1') -WhatIf -Only hermes 6>&1 | Out-String) -match '\(unchanged\)')) {
    Write-Host "  FAIL hermes   - SOUL.md drifted from agent-core; run build.ps1" -ForegroundColor Red; $fail++
  }
}

if ('codex' -in $targets) {
  $codexDir = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
  $codexPath = Join-Path $codexDir 'AGENTS.md'
  $override = Join-Path $codexDir 'AGENTS.override.md'
  if ((Test-Path -LiteralPath $override -PathType Leaf) -and
      -not [string]::IsNullOrWhiteSpace((Get-Content -Raw -LiteralPath $override))) { $codexPath = $override }
  if (-not (Test-Static 'codex   ' $codexPath 'Harness dialect: Codex')) { $fail++ }
  else {
    try {
      $preview = & (Join-Path $Root 'build.ps1') -WhatIf -Only codex 6>&1 | Out-String
      if ($preview -notmatch '\(unchanged\)') { throw 'managed instructions drifted; run build.ps1 -Only codex' }
      Write-Host '  ok   codex managed instructions match agent-core' -ForegroundColor Green
    }
    catch { Write-Host "  FAIL codex - $_" -ForegroundColor Red; $fail++ }
  }
  foreach ($skill in (Get-ChildItem (Join-Path $Root 'skills/global') -Directory | Where-Object { $_.Name -ne '.system' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md')) })) {
    if (Test-Path -LiteralPath (Join-Path $HOME ".agents/skills/$($skill.Name)/SKILL.md")) {
      Write-Host "  ok   codex skill $($skill.Name) available" -ForegroundColor Green
    }
    else { Write-Host "  FAIL codex skill $($skill.Name) missing; run sync-skills.ps1 -Link" -ForegroundColor Red; $fail++ }
  }
}

Write-Host "hooks:"
# NOT `Get-Command bash` - on Windows that resolves to WSL bash, which mounts the
# C: drive at /mnt/c and cannot see a C:/... fixture path. Claude Code runs hooks
# under Git Bash (MINGW, /c), so test under the same shell or the test lies.
$script:Bash = @(
  "$env:ProgramFiles\Git\bin\bash.exe"
  "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
  "${env:ProgramFiles(x86)}\Git\bin\bash.exe"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $script:Bash -and -not $IsWindows) { $script:Bash = (Get-Command bash -EA SilentlyContinue)?.Source }

# Every hook wired in settings.json must exist on disk.
$sj = "$HOME/.claude/settings.json"
if (Test-Path $sj) {
  foreach ($h in ([regex]::Matches((Get-Content -Raw $sj), '~/\.claude/hooks/([A-Za-z0-9._-]+)') |
      ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)) {
    if (Test-Path "$HOME/.claude/hooks/$h") { Write-Host "  ok   $h installed" -ForegroundColor Green }
    else { Write-Host "  FAIL $h wired in settings.json but missing on disk" -ForegroundColor Red; $fail++ }
  }
}

# Keep hook verification isolated from real repositories.
$fix = Join-Path ([System.IO.Path]::GetTempPath()) "agent-core-verify-$PID"
New-Item -ItemType Directory -Force -Path $fix | Out-Null
try {
  # The billing gate BLOCKS rather than advises, so both directions matter: a
  # false negative bills the account, a false positive stops legitimate work.
  if (Test-Path "$HOME/.claude/hooks/github-billing-gate") {
    # Build these with ConvertTo-Json, never by hand: a newline written as a
    # literal \n in source becomes a real newline, which is invalid inside a JSON
    # string. The hook then fails to parse and exits silently - so the "allows"
    # case passes for entirely the wrong reason.
    function New-Payload { param($Tool, $In) (@{ tool_name = $Tool; tool_input = $In } | ConvertTo-Json -Compress -Depth 5) }
    $autoWf = New-Payload 'Write' @{ file_path = 'r/.github/workflows/ci.yml'; content = "on: push`njobs: {}" }
    $manWf = New-Payload 'Write' @{ file_path = 'r/.github/workflows/m.yml'; content = "on:`n  workflow_dispatch:`njobs: {}" }
    $lfs = New-Payload 'Bash' @{ command = ('git' + ' lfs track x') }
    if (-not (Test-Hook 'billing gate blocks an auto workflow ' 'github-billing-gate' $autoWf 'speaks')) { $fail++ }
    if (-not (Test-Hook 'billing gate allows manual dispatch  ' 'github-billing-gate' $manWf 'silent')) { $fail++ }
    if (-not (Test-Hook 'billing gate blocks metered storage  ' 'github-billing-gate' $lfs 'speaks')) { $fail++ }
    if (-not (Test-Hook 'billing gate ignores ordinary work   ' 'github-billing-gate' '{"tool_name":"Bash","tool_input":{"command":"git status"}}' 'silent')) { $fail++ }
  }
  # Hermes reaches the same gate through the bridge, with its own tool names.
  if ('hermes' -in $targets) {
    $bridge = Join-Path $Root 'configs/hermes/hooks/claude-hooks-bridge.mjs'
    $hp = @{ hook_event_name = 'pre_tool_call'; tool_name = 'terminal'; tool_input = @{ command = ('git' + ' lfs track x') } } | ConvertTo-Json -Compress -Depth 5
    $out = ($hp | node $bridge 2>$null | Out-String)
    if ($out -match '"decision":"block"') { Write-Host "  ok   hermes bridge blocks metered storage" -ForegroundColor Green }
    else { Write-Host "  FAIL hermes bridge did not block git lfs" -ForegroundColor Red; $fail++ }
    # Hermes re-asks consent when the bridge changes (e.g. after a pull); until then it may not fire.
    $hermesCommand = Resolve-HarnessCommand hermes
    if ($hermesCommand) {
      if ((& $hermesCommand hooks doctor 2>&1 | Out-String) -match 'All shell hooks look healthy') { Write-Host "  ok   hermes hooks approved and unchanged" -ForegroundColor Green }
      else { Write-Host "  FAIL hermes hooks need re-approval: hermes hooks doctor" -ForegroundColor Red; $fail++ }
    }
  }
}
finally { Remove-Item $fix -Recurse -Force -EA SilentlyContinue }

if (-not $Static) {
  Write-Host "live load (calls each harness once):"
  if ('claude' -in $targets) { if (-not (Test-Live 'claude  ' { & (Resolve-HarnessCommand claude) -p --model haiku --tools '' --strict-mcp-config --mcp-config '{"mcpServers":{}}' --no-session-persistence $Probe })) { $fail++ } }
  if ('omp'    -in $targets) { if (-not (Test-Live 'omp     ' { omp -p $Probe })) { $fail++ } }
  if ('hermes' -in $targets) { if (-not (Test-Live 'hermes  ' { & (Resolve-HarnessCommand hermes) -z $Probe })) { $fail++ } }
  if ('codex' -in $targets) { if (-not (Test-Live 'codex   ' { & (Resolve-HarnessCommand codex) exec --ignore-user-config --ephemeral --sandbox read-only --skip-git-repo-check $Probe })) { $fail++ } }
}

if ($fail) { Write-Host "$fail check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host "all checks passed" -ForegroundColor Green
