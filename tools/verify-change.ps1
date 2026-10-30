#requires -Version 7.0
<#
.SYNOPSIS
  Mechanical checks for a change before it is called done, with a record of what ran.

.DESCRIPTION
  Checks every file changed since -Base (committed, staged, unstaged and untracked):
    - no UTF-8 byte order mark added to a file that did not have one
    - no line-ending churn: lines whose only change is CR/LF, which turn a small edit into a whole-file diff
    - no mixed line endings inside one file
  Refuses outright when one of -Process is running (a build would replace its binary under it).
  Runs each -Run command and records its exit code.
  Appends one JSON line per run to <git dir>/verify-change.jsonl: time, branch, revision, base, every check and its result.

.EXAMPLE
  verify-change.ps1 -Process handball1 -Run 'luac -p src/x.lua'
.EXAMPLE
  verify-change.ps1 -Base origin/develop -Run 'dotnet test GameCore2.UnitTests --filter FullyQualifiedName~Foo'
#>
param(
	[string]$Repo = (Get-Location).Path,
	[string]$Base,
	[string[]]$Process = @(),
	[string[]]$Run = @()
)
$ErrorActionPreference = 'Stop'
Set-Location $Repo
$checks = [System.Collections.Generic.List[object]]::new()
function Add-Check([string]$name, [bool]$ok, [string]$detail) {
	$checks.Add([pscustomobject]@{ name = $name; ok = $ok; detail = $detail })
	$mark = if ($ok) { 'ok  ' } else { 'FAIL' }
	$colour = if ($ok) { 'Green' } else { 'Red' }
	Write-Host "  $mark $name$(if ($detail) { " - $detail" })" -ForegroundColor $colour
}

if (-not $Base) {
	$remoteHead = git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>$null
	$Base = if ($remoteHead) { git merge-base HEAD $remoteHead } else { 'HEAD' }
}
$gitDir = git rev-parse --absolute-git-dir
Write-Host "verify-change: $(git rev-parse --abbrev-ref HEAD) @ $(git rev-parse --short HEAD), base $(git rev-parse --short $Base)"

# A running process blocks everything else: building over it is the failure this exists to stop.
foreach ($p in $Process) {
	$running = Get-Process -Name $p -ErrorAction SilentlyContinue
	Add-Check "not running: $p" (-not $running) $(if ($running) { "pid $($running.Id -join ','); close it before building" })
}

$changed = @(git diff --name-only --diff-filter=AMR $Base) + @(git ls-files --others --exclude-standard) |
	Sort-Object -Unique | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
$binary = @{}
git diff --numstat $Base | ForEach-Object { $f = $_ -split "`t"; if ($f[0] -eq '-') { $binary[$f[2]] = $true } }

$bomAdded = @(); $churn = @(); $mixed = @()
foreach ($file in $changed) {
	if ($binary[$file]) { continue }
	$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $file))
	if ($bytes -contains 0) { continue }
	$hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
	if ($hasBom) {
		$baseHead = git cat-file -p "${Base}:$file" 2>$null | Select-Object -First 1
		$baseHadBom = $baseHead -and $baseHead.StartsWith([char]0xFEFF)
		if (-not $baseHadBom) { $bomAdded += $file }
	}
	$text = [System.Text.Encoding]::UTF8.GetString($bytes)
	$crlf = ([regex]::Matches($text, "`r`n")).Count
	$lf = ([regex]::Matches($text, "(?<!`r)`n")).Count
	if ($crlf -gt 0 -and $lf -gt 0) { $mixed += "$file ($crlf CRLF, $lf LF)" }
	# Lines counted as changed only because of CR/LF: the plain diff counts more than the eol-blind one.
	$plain = git diff --numstat $Base -- $file | Select-Object -First 1
	$blind = git diff --numstat --ignore-cr-at-eol $Base -- $file | Select-Object -First 1
	if ($plain -and $blind) {
		$p = [int]($plain -split "`t")[0]; $b = [int]($blind -split "`t")[0]
		if ($p -gt $b) { $churn += "$file ($($p - $b) lines)" }
	}
}
Add-Check 'no BOM added' ($bomAdded.Count -eq 0) ($bomAdded -join ', ')
Add-Check 'no line-ending churn' ($churn.Count -eq 0) $(if ($churn) { ($churn -join ', ') + '; rewrite with the endings the file had' })
Add-Check 'no mixed line endings' ($mixed.Count -eq 0) ($mixed -join ', ')

$blocked = $checks | Where-Object { $_.name -like 'not running:*' -and -not $_.ok }
foreach ($cmd in $Run) {
	if ($blocked) { Add-Check "run: $cmd" $false 'skipped: a guarded process is running'; continue }
	$out = pwsh -NoProfile -Command $cmd 2>&1
	$code = $LASTEXITCODE
	$tail = if ($code -ne 0) { ($out | Select-Object -Last 5) -join ' | ' }
	Add-Check "run: $cmd" ($code -eq 0) $(if ($code -ne 0) { "exit ${code}: $tail" })
}

$ok = -not ($checks | Where-Object { -not $_.ok })
$record = [ordered]@{
	time     = (Get-Date).ToString('o')
	branch   = git rev-parse --abbrev-ref HEAD
	revision = git rev-parse HEAD
	base     = git rev-parse $Base
	dirty    = [bool](git status --porcelain)
	files    = $changed.Count
	ok       = $ok
	checks   = $checks
}
Add-Content -LiteralPath (Join-Path $gitDir 'verify-change.jsonl') -Value ($record | ConvertTo-Json -Compress -Depth 4)
Write-Host $(if ($ok) { 'verify-change: passed' } else { 'verify-change: FAILED' }) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
exit $(if ($ok) { 0 } else { 1 })
