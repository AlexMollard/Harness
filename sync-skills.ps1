#requires -Version 7
<#
  Unifies skills across harnesses without inflating the per-session skill index.

  The problem: the skill INDEX (name + description of every skill) is injected into
  every session. The 105 managed skills carry ~40 KB of descriptions - roughly
  10k tokens per session - so fanning them into every harness is not affordable.
  Skill BODIES cost nothing until invoked.

  So skills are tiered:
    global/      general-purpose meta skills. Linked into every harness, so they
                 are indexed everywhere. Small, hand-authored, git-tracked.
    catalogue    every other skill (project- and domain-specific, mostly written
                 by omp autolearn). Stays where omp writes it; reachable from every
                 harness through ONE index entry - skills/global/skill-catalogue -
                 which costs ~40 tokens instead of ~10,000.

  Net: all skills reachable from all harnesses; session cost goes DOWN, not up.

  Nothing is ever deleted. -Link renames an existing harness skill dir aside to
  <dir>.preunify before creating the junction; undo with -Unlink.
#>
[CmdletBinding()]
param(
  [switch]$WhatIf,
  [switch]$Link,
  [switch]$Unlink
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Pool = Join-Path $Root 'skills/global'
$Managed = "$HOME/.omp/agent/managed-skills"

# General-purpose skills: useful in any repo, cheap to index everywhere.
$GlobalSkills = @{
  'check-resolvable' = "$HOME/.claude/skills/check-resolvable"
  'codebase-memory'  = "$HOME/.claude/skills/codebase-memory"
  'graphify'         = "$HOME/.claude/skills/graphify"
  'handoff'          = "$HOME/.claude/skills/handoff"
  'handoffplan'      = "$HOME/.claude/skills/handoffplan"
  'skillify'         = "$HOME/.claude/skills/skillify"
  'mind-management'  = "$HOME/.config/opencode/skills/mind-management"
  'pressure-test'    = "$Root/skills/global/pressure-test"
  'sidenote'         = "$Root/skills/global/sidenote"
}

# Slash commands are pooled the same way: union of what each harness had today.
$CmdPool = Join-Path $Root 'commands'
$CmdSources = @("$HOME/.claude/commands", "$HOME/.config/opencode/commands")

# Every dir that becomes a junction, flattened so skills and commands can share
# one loop without colliding on harness name.
$Links = @(
  [pscustomobject]@{ Label = 'claude skills'; Path = "$HOME/.claude/skills"; Pool = $Pool }
  [pscustomobject]@{ Label = 'opencode skills'; Path = "$HOME/.config/opencode/skills"; Pool = $Pool }
  [pscustomobject]@{ Label = 'claude commands'; Path = "$HOME/.claude/commands"; Pool = $CmdPool }
  [pscustomobject]@{ Label = 'opencode commands'; Path = "$HOME/.config/opencode/commands"; Pool = $CmdPool }
)

Write-Host "agent-core skills sync" -ForegroundColor Cyan

if ($Unlink) {
  foreach ($l in $Links) {
    $d = $l.Path; $bak = "$d.preunify"
    $item = Get-Item $d -Force -EA SilentlyContinue
    if (-not ($item -and $item.LinkType)) { Write-Host "  = $($l.Label) not linked" -ForegroundColor DarkGray; continue }
    $how = if (Test-Path $bak) { "restore $bak" } else { 'copy the pool contents back' }
    if ($WhatIf) { Write-Host "  would unlink $($l.Label) and $how" -ForegroundColor Yellow; continue }
    # removes the junction only - the target pool is untouched
    [System.IO.Directory]::Delete($d, $false)
    if (Test-Path $bak) {
      Move-Item $bak $d
      Write-Host "  restored $($l.Label) from $(Split-Path -Leaf $bak)" -ForegroundColor Green
    }
    else {
      # no pre-unification snapshot kept: leave a real, populated directory rather
      # than nothing, by copying the pool out of the link
      Copy-Item -Recurse -Force $l.Pool $d
      Write-Host "  unlinked $($l.Label), copied pool contents into a real dir" -ForegroundColor Green
    }
  }
  return
}

# 1. populate the pool
if (-not $WhatIf) { New-Item -ItemType Directory -Force -Path $Pool | Out-Null }
foreach ($kv in $GlobalSkills.GetEnumerator()) {
  $dst = Join-Path $Pool $kv.Key
  if (Test-Path $dst) { Write-Host "  = $($kv.Key) already pooled" -ForegroundColor DarkGray; continue }
  if (-not (Test-Path $kv.Value)) { Write-Host "  ! source missing: $($kv.Value)" -ForegroundColor Red; continue }
  if ($WhatIf) { Write-Host "  would pool $($kv.Key)" -ForegroundColor Yellow; continue }
  Copy-Item -Recurse -Force $kv.Value $dst
  Write-Host "  pooled $($kv.Key)" -ForegroundColor Green
}

# 1b. pool slash commands: union of what each harness had. Commands are small and
#     few, so unlike skills they are all indexed everywhere - no tiering needed.
if (-not $WhatIf) { New-Item -ItemType Directory -Force -Path $CmdPool | Out-Null }
foreach ($src in $CmdSources) {
  if (-not (Test-Path $src)) { continue }
  foreach ($f in Get-ChildItem $src -Filter *.md -File) {
    $dst = Join-Path $CmdPool $f.Name
    if (Test-Path $dst) { continue }
    if ($WhatIf) { Write-Host "  would pool command $($f.Name)" -ForegroundColor Yellow; continue }
    Copy-Item $f.FullName $dst
    Write-Host "  pooled command $($f.BaseName)" -ForegroundColor Green
  }
}

# 2. regenerate the catalogue from every skill on disk
$rows = @()
foreach ($dir in @($Managed, $Pool)) {
  if (-not (Test-Path $dir)) { continue }
  $tier = if ($dir -eq $Pool) { 'global' } else { 'catalogue' }
  foreach ($d in Get-ChildItem $dir -Directory | Sort-Object Name) {
    $f = Join-Path $d.FullName 'SKILL.md'
    if (-not (Test-Path $f)) { continue }
    $raw = Get-Content -Raw $f
    # handles both `description: text` and YAML folded/literal scalars (`>` or `|`
    # followed by indented lines)
    if ($raw -match '(?m)^description:[ \t]*([>|][-+]?)[ \t]*\r?\n((?:[ \t]+\S.*\r?\n?)+)') {
      $desc = $Matches[2]
    }
    elseif ($raw -match '(?m)^description:[ \t]*(.+?)[ \t]*\r?$') {
      $desc = $Matches[1]
    }
    else { $desc = '' }
    $desc = ($desc -replace '\s+', ' ').Trim().Trim('"', "'")
    if ($desc.Length -gt 200) { $desc = $desc.Substring(0, 197) + '...' }
    $rows += [pscustomobject]@{ Name = $d.Name; Desc = $desc; Path = $f; Tier = $tier }
  }
}

$globals = @($rows | Where-Object Tier -EQ 'global')
$ondemand = @($rows | Where-Object Tier -EQ 'catalogue')

$cat = @(
  '# Skill catalogue'
  ''
  'Every skill on this machine, reachable from every harness. Generated by'
  '`~/agent-core/sync-skills.ps1` - do not edit by hand.'
  ''
  "## Always indexed (global tier, $($globals.Count))"
  ''
  'Already in your skill list - invoke them normally.'
  ''
)
foreach ($r in $globals) { $cat += "- **$($r.Name)** - $($r.Desc)" }
$cat += @(
  ''
  "## On demand (catalogue tier, $($ondemand.Count))"
  ''
  'Project- and domain-specific. Not in your skill list. When one matches the task,'
  'read its path below and follow it as you would any skill.'
  ''
)
foreach ($r in $ondemand) {
  $cat += "- **$($r.Name)** — $($r.Desc)"
  $cat += "  ``$($r.Path -replace '\\','/')``"
}
$catPath = Join-Path $Root 'skills/catalogue.md'
if ($WhatIf) { Write-Host "  would write catalogue ($($rows.Count) skills)" -ForegroundColor Yellow }
else {
  New-Item -ItemType Directory -Force -Path (Split-Path $catPath) | Out-Null
  [System.IO.File]::WriteAllText($catPath, (($cat -join "`n") -replace "`n", "`r`n"))
  Write-Host "  catalogue: $($rows.Count) skills, $($ondemand.Count) on demand" -ForegroundColor Green
}

# 3. the single index entry that unlocks the catalogue tier
$idxBody = @"
---
name: skill-catalogue
description: Use when a task looks project- or domain-specific and no listed skill covers it - Android/Compose/Kotlin/KSP/Room/Gradle, Monarch, AntHill/antfarm/lore, AetherCore, gamecore, handball, load testing, Postgres/Supabase, .NET/Aspire, WHEA, SN-DBS. Over 100 such skills exist but are not in the skill list; this catalogue finds them.
---

# Skill catalogue

Most skills on this machine are deliberately NOT in your skill index - listing all
of them would inject roughly 10k tokens into every session. They are one read away.

1. Read ``~/agent-core/skills/catalogue.md``.
2. Find an entry matching the task.
3. Read that entry's ``SKILL.md`` path and follow it as you would any skill.

If nothing matches, proceed without one. If you just did something non-trivial worth
repeating and no skill covered it, use ``skillify`` to capture it.
"@
if ($WhatIf) { Write-Host "  would write skill-catalogue index skill" -ForegroundColor Yellow }
else {
  New-Item -ItemType Directory -Force -Path (Join-Path $Pool 'skill-catalogue') | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $Pool 'skill-catalogue/SKILL.md'), ($idxBody -replace "`r`n", "`n" -replace "`n", "`r`n"))
  Write-Host "  wrote skill-catalogue index skill" -ForegroundColor Green
}

# 4. link each harness skill dir at the pool (opt-in; nothing is deleted)
if (-not $Link) {
  Write-Host "  (skipping harness links - re-run with -Link to point harnesses at the pool)" -ForegroundColor DarkGray
  Write-Host "done." -ForegroundColor Cyan
  return
}

foreach ($l in $Links) {
  $d = $l.Path; $bak = "$d.preunify"
  $item = Get-Item $d -Force -EA SilentlyContinue
  if ($item -and $item.LinkType) { Write-Host "  = $($l.Label) already linked" -ForegroundColor DarkGray; continue }
  if (Test-Path $bak) { Write-Host "  ! $bak already exists - resolve by hand" -ForegroundColor Red; continue }

  # If the dir is already byte-identical to the pool there is nothing to preserve,
  # so skip the backup rather than leaving a redundant .preunify behind. Content is
  # compared by hash; anything unique means we fall back to renaming aside.
  $redundant = $false
  if (Test-Path $d) {
    $hash = { param($p) (Get-ChildItem $p -Recurse -File | Sort-Object { $_.FullName.Substring($p.Length) } |
        ForEach-Object { (Get-FileHash $_ -Algorithm MD5).Hash }) -join ',' }
    $redundant = (& $hash $d) -eq (& $hash $l.Pool)
  }
  if ($WhatIf) {
    $what = if ($redundant) { 'replace (identical to pool, no backup needed)' } else { "move -> $bak, then" }
    Write-Host "  would $what junction $d at $($l.Pool)" -ForegroundColor Yellow; continue
  }
  if (Test-Path $d) {
    if ($redundant) { [System.IO.Directory]::Delete($d, $true) }   # proven identical to the pool
    else { Move-Item $d $bak }                                     # unique content: renamed aside, never deleted
  }
  # junction, not symlink: works without admin or Developer Mode on Windows
  New-Item -ItemType Junction -Path $d -Target $l.Pool | Out-Null
  $note = if ($redundant) { 'was identical, nothing to keep' } else { "previous set kept at $(Split-Path -Leaf $bak)" }
  Write-Host "  + $($l.Label) -> pool ($note)" -ForegroundColor Green
}

Write-Host "done." -ForegroundColor Cyan
