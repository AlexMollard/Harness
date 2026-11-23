#requires -Version 7
# Integration checks run against a disposable home and a minimal repo copy.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('harness-codex-' + [guid]::NewGuid().ToString('N'))
$fixtureHome = Join-Path $fixture 'home'
$fixtureRepo = Join-Path $fixtureHome 'agent-core'
New-Item -ItemType Directory -Force -Path $fixtureRepo | Out-Null
foreach ($file in @('build.ps1','sync-skills.ps1','manifest.psd1')) { Copy-Item (Join-Path $repo $file) $fixtureRepo }
foreach ($dir in @('adapters','core','tools')) { Copy-Item (Join-Path $repo $dir) $fixtureRepo -Recurse }
New-Item -ItemType Directory -Force -Path "$fixtureRepo/skills/global/example","$fixtureHome/.agents/skills/custom","$fixtureHome/.codex" | Out-Null
Set-Content "$fixtureRepo/skills/global/example/SKILL.md" "---`nname: example`ndescription: Test shared skill`n---`nExample"
Set-Content "$fixtureHome/.agents/skills/custom/SKILL.md" 'Owner skill'
$originalHome = $HOME
$originalCodexHome = $env:CODEX_HOME
function Assert($condition, $message) { if (-not $condition) { throw $message }; Write-Host "ok $message" }
try {
  Set-Variable HOME -Value $fixtureHome -Force -Scope Global
  $env:CODEX_HOME = "$fixtureHome/.codex"
  $path = "$env:CODEX_HOME/AGENTS.md"
  Set-Content $path 'Owner instructions and memory protocols'
  & "$fixtureRepo/build.ps1" -Only codex
  $first = Get-Content -Raw $path
  Assert ($first.Contains('Owner instructions and memory protocols')) 'preserves owner instructions'
  Assert ($first.Contains('Harness dialect: Codex')) 'inlines Codex adapter'
  Assert ($first.Contains('Rust Token Killer')) 'inlines core rules'
  Assert ($first -notmatch '(?m)^@~/agent-core/') 'does not depend on unresolved imports'
  Assert (Test-Path "$path.pre-install") 'backs up initial user instructions'
  & "$fixtureRepo/build.ps1" -Only codex
  Assert ((Get-Content -Raw $path) -ceq $first) 'repeat build is idempotent'
  Assert (((& "$fixtureRepo/build.ps1" -WhatIf -Only codex 6>&1 | Out-String)) -match '\(unchanged\)') 'dry run verifies generated content'
  Set-Content -LiteralPath $path -Value ($first.Replace('Rust Token Killer', 'broken rule')) -NoNewline
  Assert (((& "$fixtureRepo/build.ps1" -WhatIf -Only codex 6>&1 | Out-String)) -match '\(would change:') 'detects stale generated rules'
  Set-Content -LiteralPath $path -Value $first -NoNewline
  Set-Content "$env:CODEX_HOME/AGENTS.override.md" 'Owner override'
  & "$fixtureRepo/build.ps1" -Only codex
  Assert ((Get-Content -Raw "$env:CODEX_HOME/AGENTS.override.md").Contains('Harness dialect: Codex')) 'uses effective override file'
  Assert ((Get-Content -Raw $path) -ceq $first) 'leaves shadowed AGENTS.md intact'
  $env:CODEX_HOME = "$fixtureHome/custom-codex"
  & "$fixtureRepo/build.ps1" -Only codex
  Assert ((Get-Content -Raw "$env:CODEX_HOME/AGENTS.md").Contains('Harness dialect: Codex')) 'respects custom CODEX_HOME'
  $broken = "Owner`n<!-- agent-core:codex:start -->`nunfinished"
  Set-Content "$env:CODEX_HOME/AGENTS.md" $broken
  $refused = $false
  try { & "$fixtureRepo/build.ps1" -Only codex } catch { $refused = $true }
  Assert $refused 'refuses malformed managed markers'
  Assert ((Get-Content -Raw "$env:CODEX_HOME/AGENTS.md").TrimEnd() -ceq $broken) 'does not overwrite malformed instructions'
  & "$fixtureRepo/sync-skills.ps1" -Link
  Assert ((Get-Item "$fixtureHome/.agents/skills/example").LinkType -eq 'Junction') 'links shared skills individually for Codex'
  Assert ((Get-Content -Raw "$fixtureHome/.agents/skills/custom/SKILL.md").Trim() -eq 'Owner skill') 'preserves unrelated Codex skills'
  & "$fixtureRepo/sync-skills.ps1" -Link
  Assert ((Get-Item "$fixtureHome/.agents/skills/example").LinkType -eq 'Junction') 'skill sync is repeatable'
  & "$fixtureRepo/sync-skills.ps1" -Unlink
  Assert (-not (Test-Path "$fixtureHome/.agents/skills/example")) 'unlink removes only managed Codex junctions'
  Assert (Test-Path "$fixtureRepo/skills/global/example/SKILL.md") 'unlink preserves source pool'
  Assert ((Get-Content -Raw "$fixtureHome/.agents/skills/custom/SKILL.md").Trim() -eq 'Owner skill') 'unlink preserves unrelated owner skills'
  $oldPath = $env:PATH
  try {
    $env:PATH = ''
    foreach ($version in @('2.1.99','2.1.330')) {
      $native = "$fixtureHome/.vscode-insiders/extensions/anthropic.claude-code-$version-win32-x64/resources/native-binary"
      New-Item -ItemType Directory -Force -Path $native | Out-Null
      New-Item -ItemType File -Path "$native/claude.exe" | Out-Null
    }
    . "$fixtureRepo/tools/harness-commands.ps1"
    Assert ((Resolve-HarnessCommand claude) -match '2\.1\.330') 'finds newest packaged Claude without PATH'
  }
  finally { $env:PATH = $oldPath }
  Write-Host 'all Codex support checks passed'
}
finally {
  Set-Variable HOME -Value $originalHome -Force -Scope Global
  $env:CODEX_HOME = $originalCodexHome
  # Keep the tiny fixture for diagnosis; no recursive deletion of junction targets.
  Write-Host "fixture: $fixture"
}
