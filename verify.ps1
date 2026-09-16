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
  [ValidateSet('claude', 'omp', 'opencode')]
  [string[]]$Only
)

$ErrorActionPreference = 'Continue'
$Root = $PSScriptRoot
$fail = 0

# Three facts, one per core file, that exist nowhere else on this machine.
$Probe = @'
Answer from your system instructions ONLY. Do not use any tools. Print exactly
three lines and nothing else:
1) the name of Gate 2
2) the title of section 8
3) what RTK stands for
Print MISSING on any line whose answer is not in your instructions.
'@

$Expect = @('Ponytail', 'Delegate by Default', 'Rust Token Killer')

function Test-Static {
  param([string]$Name, [string]$Path, [string]$Needle)
  if (-not (Test-Path $Path)) { Write-Host "  FAIL $Name - $Path missing" -ForegroundColor Red; return $false }
  $raw = Get-Content -Raw -LiteralPath $Path
  if ($raw -notmatch [regex]::Escape($Needle)) {
    Write-Host "  FAIL $Name - not wired to agent-core" -ForegroundColor Red; return $false
  }
  Write-Host "  ok   $Name wiring" -ForegroundColor Green; return $true
}

function Test-Live {
  param([string]$Name, [scriptblock]$Run)
  Write-Host "  .... $Name probing" -NoNewline
  try { $out = (& $Run) 2>&1 | Out-String } catch { $out = "$_" }
  $missed = $Expect | Where-Object { $out -notmatch [regex]::Escape($_) }
  if ($missed) {
    Write-Host "`r  FAIL $Name - did not load: $($missed -join ', ')   " -ForegroundColor Red
    Write-Host ($out.Trim() -split "`n" | Select-Object -Last 6 | ForEach-Object { "         $_" }) -ForegroundColor DarkGray
    return $false
  }
  Write-Host "`r  ok   $Name loads core          " -ForegroundColor Green
  return $true
}

$targets = if ($Only) { $Only } else { @('claude', 'omp', 'opencode') }
Write-Host "agent-core verify" -ForegroundColor Cyan

Write-Host "static wiring:"
if ('claude'   -in $targets) { if (-not (Test-Static 'claude  ' "$HOME/.claude/CLAUDE.md"                  'agent-core/core')) { $fail++ } }
if ('omp'      -in $targets) { if (-not (Test-Static 'omp     ' "$HOME/.omp/agent/AGENTS.md"               'agent-core/core')) { $fail++ } }
if ('opencode' -in $targets) { if (-not (Test-Static 'opencode' "$HOME/.config/opencode/opencode.jsonc"    'agent-core'))      { $fail++ } }

if (-not $Static) {
  Write-Host "live load (calls each harness once):"
  if ('claude' -in $targets) { if (-not (Test-Live 'claude  ' { claude -p --model haiku $Probe })) { $fail++ } }
  if ('omp'    -in $targets) { if (-not (Test-Live 'omp     ' { omp -p $Probe })) { $fail++ } }
  if ('opencode' -in $targets) { if (-not (Test-Live 'opencode' { opencode run $Probe })) { $fail++ } }
}

if ($fail) { Write-Host "$fail check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host "all checks passed" -ForegroundColor Green
