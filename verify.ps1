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
  [ValidateSet('claude', 'omp')]
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

$targets = if ($Only) { $Only } else { @('claude', 'omp') }
Write-Host "agent-core verify" -ForegroundColor Cyan

Write-Host "static wiring:"
if ('claude'   -in $targets) { if (-not (Test-Static 'claude  ' "$HOME/.claude/CLAUDE.md"                  'agent-core/core')) { $fail++ } }
if ('omp'      -in $targets) { if (-not (Test-Static 'omp     ' "$HOME/.omp/agent/AGENTS.md"               'agent-core/core')) { $fail++ } }

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

# Fixture, not a real repo: these must pass on any machine, not just where a
# graphed project happens to live.
$fix = Join-Path ([System.IO.Path]::GetTempPath()) "agent-core-verify-$PID"
New-Item -ItemType Directory -Force -Path "$fix/withgraph/graphify-out" | Out-Null
New-Item -ItemType Directory -Force -Path "$fix/nograph" | Out-Null
'{}' | Set-Content "$fix/withgraph/graphify-out/graph.json"
$jf = ($fix -replace '\\', '/')
try {
  if (Test-Path "$HOME/.claude/hooks/graphify-discovery-gate") {
    if (-not (Test-Hook 'graphify gate speaks where a graph exists' 'graphify-discovery-gate' "{`"cwd`":`"$jf/withgraph`"}" 'speaks')) { $fail++ }
    if (-not (Test-Hook 'graphify gate silent without one      ' 'graphify-discovery-gate' "{`"cwd`":`"$jf/nograph`"}" 'silent')) { $fail++ }
  }
  if (Test-Path "$HOME/.claude/hooks/context7-docs-gate") {
    # the hook deliberately says nothing unless the plugin is enabled
    $on = (Get-Content -Raw $sj -EA SilentlyContinue) -match '"context7@claude-plugins-official"\s*:\s*true'
    if ($on) {
      if (-not (Test-Hook 'context7 gate speaks on a docs host  ' 'context7-docs-gate' '{"tool_input":{"url":"https://kotlinlang.org/docs/x"}}' 'speaks')) { $fail++ }
    }
    else { Write-Host "  skip context7 gate - plugin not enabled" -ForegroundColor DarkGray }
    if (-not (Test-Hook 'context7 gate silent elsewhere        ' 'context7-docs-gate' '{"tool_input":{"url":"https://news.ycombinator.com/"}}' 'silent')) { $fail++ }
  }
}
finally { Remove-Item $fix -Recurse -Force -EA SilentlyContinue }

# omp model roles. Two failure modes, both silent until a request actually runs:
# the installed roles drifting from the policy, and a role pointing at a provider
# that no longer exists (which is what zai-headroom became when headroom went).
Write-Host "omp roles:"
$rp = Join-Path $Root 'configs/omp/roles.psd1'
$cy = "$HOME/.omp/agent/config.yml"
if ((Test-Path $rp) -and (Test-Path $cy)) {
  $policy = Import-PowerShellDataFile $rp
  $want = @{}
  foreach ($k in $policy.base.Keys) { $want[$k] = $policy.base[$k] }
  $ov = @()
  foreach ($o in $policy.overlays) {
    if (-not [Environment]::GetEnvironmentVariable($o.key)) { continue }
    foreach ($k in $o.roles.Keys) { $want[$k] = $o.roles[$k] }
    $ov += $o.name
  }
  # Scope to the modelRoles block - config.yml is full of other indented keys
  # (memory.backend, statusLine.preset) that would read as bogus providers.
  $have = @{}
  $cl = (Get-Content -Raw $cy) -replace "`r`n", "`n" -split "`n"
  $i = [array]::FindIndex($cl, [Predicate[string]] { $args[0] -match '^modelRoles:\s*$' })
  for ($i++; $i -ge 1 -and $i -lt $cl.Count; $i++) {
    if ($cl[$i] -match '^[A-Za-z]') { break }
    if ($cl[$i] -match '^\s+([A-Za-z][A-Za-z0-9_-]*):\s*(\S+)$') { $have[$Matches[1]] = $Matches[2] }
  }
  $drift = $want.Keys | Where-Object { $have[$_] -ne $want[$_] }
  $tag = if ($ov) { "base + $($ov -join ', ')" } else { 'base only' }
  if ($drift) {
    foreach ($d in $drift) { Write-Host "  FAIL $d is $($have[$d]) - policy says $($want[$d])" -ForegroundColor Red }
    $fail++
  }
  else { Write-Host "  ok   roles match policy ($tag)" -ForegroundColor Green }

  # Every provider a role names must exist, or the request 401s at runtime.
  $defined = @('anthropic')   # built into omp; the rest must be declared
  foreach ($m in (Select-String -Path "$HOME/.omp/agent/models.yml" -Pattern '^\s{2}([A-Za-z0-9_-]+):\s*$' -EA SilentlyContinue)) {
    $defined += $m.Matches[0].Groups[1].Value
  }
  $orphan = $have.Values | ForEach-Object { ($_ -split '/')[0] } |
  Sort-Object -Unique | Where-Object { $_ -and $_ -notin $defined }
  if ($orphan) { Write-Host "  FAIL role points at undefined provider: $($orphan -join ', ')" -ForegroundColor Red; $fail++ }
  else { Write-Host "  ok   every role resolves to a defined provider" -ForegroundColor Green }
}

if (-not $Static) {
  Write-Host "live load (calls each harness once):"
  if ('claude' -in $targets) { if (-not (Test-Live 'claude  ' { claude -p --model haiku $Probe })) { $fail++ } }
  if ('omp'    -in $targets) { if (-not (Test-Live 'omp     ' { omp -p $Probe })) { $fail++ } }
}

if ($fail) { Write-Host "$fail check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host "all checks passed" -ForegroundColor Green
