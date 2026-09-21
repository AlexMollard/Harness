#requires -Version 7
<#
  Apply the model-role policy in configs/omp/roles.psd1 to an omp config.yml.

    -Mode auto   base, plus every overlay whose env var is set   (install.ps1)
    -Mode base   base only                                       (export-config.ps1)

  Only the role lines the policy names are rewritten; every other byte of the
  file, including its line endings, is left as it was. Safe to re-run.

  Returns the names of the overlays it applied.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Path,
  [ValidateSet('auto', 'base')][string]$Mode = 'auto',
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$policy = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'configs/omp/roles.psd1')

# Effective map: base, then each overlay whose key is present.
$roles = @{}
foreach ($k in $policy.base.Keys) { $roles[$k] = $policy.base[$k] }
$applied = @()
if ($Mode -eq 'auto') {
  foreach ($o in $policy.overlays) {
    if (-not [Environment]::GetEnvironmentVariable($o.key)) { continue }
    foreach ($k in $o.roles.Keys) { $roles[$k] = $o.roles[$k] }
    $applied += $o.name
  }
}

if (-not (Test-Path $Path)) { throw "no config.yml at $Path" }
$raw = Get-Content -Raw -LiteralPath $Path
$crlf = $raw.Contains("`r`n")
$lines = ($raw -replace "`r`n", "`n").TrimEnd("`n") -split "`n"

# Scope the rewrite to the modelRoles block - a bare `plan:` could legitimately
# exist under another top-level key.
$start = [array]::FindIndex($lines, [Predicate[string]] { $args[0] -match '^modelRoles:\s*$' })
if ($start -lt 0) { throw "no modelRoles: block in $Path" }
$end = $lines.Count
for ($i = $start + 1; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '^[A-Za-z]') { $end = $i; break }
}

$changed = @()
for ($i = $start + 1; $i -lt $end; $i++) {
  if ($lines[$i] -notmatch '^(\s+)([A-Za-z][A-Za-z0-9_-]*):\s*(\S.*)$') { continue }
  $indent, $role, $was = $Matches[1], $Matches[2], $Matches[3]
  if (-not $roles.ContainsKey($role)) { continue }
  $now = $roles[$role]
  if ($was -eq $now) { continue }
  $lines[$i] = "$indent${role}: $now"
  $changed += "$role`: $was -> $now"
}

if ($changed) {
  $out = ($lines -join "`n") + "`n"
  if ($crlf) { $out = $out -replace "`n", "`r`n" }
  [System.IO.File]::WriteAllText($Path, $out)
}

if (-not $Quiet) {
  $tag = if ($applied) { "base + $($applied -join ', ')" } else { 'base only' }
  Write-Host "  roles: $tag" -ForegroundColor Green
  foreach ($c in $changed) { Write-Host "    $c" -ForegroundColor DarkGray }
  if (-not $changed) { Write-Host "    already correct" -ForegroundColor DarkGray }
  if ($Mode -eq 'auto' -and -not $applied) {
    foreach ($o in $policy.overlays) {
      Write-Host "    set $($o.key) to use $($o.name) - $($o.why)" -ForegroundColor DarkGray
    }
  }
}

return $applied
