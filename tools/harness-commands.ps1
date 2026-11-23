# Resolve installed CLIs without depending on a stale desktop process PATH.
function Resolve-HarnessCommand {
  param([ValidateSet('claude','omp','hermes','codex')][string]$Name)
  $command = Get-Command $Name -CommandType Application,ExternalScript -EA SilentlyContinue | Select-Object -First 1
  if ($command) { return $command.Source }
  if ($Name -eq 'codex') {
    if (Get-Command Get-AppxPackage -EA SilentlyContinue) {
      $package = Get-AppxPackage -Name OpenAI.Codex -EA SilentlyContinue |
        Sort-Object { [version]$_.Version } -Descending | Select-Object -First 1
      if ($package) {
        $bundled = Join-Path $package.InstallLocation 'app/resources/codex.exe'
        if (Test-Path -LiteralPath $bundled -PathType Leaf) { return $bundled }
      }
    }
  }
  if ($Name -eq 'claude') {
    $paths = @(
      "$HOME/.local/bin/claude.exe"
      "$HOME/.vscode/extensions/anthropic.claude-code-*/resources/native-binary/claude.exe"
      "$HOME/.vscode-insiders/extensions/anthropic.claude-code-*/resources/native-binary/claude.exe"
      "$env:LOCALAPPDATA/Packages/Claude_*/LocalCache/Roaming/Claude/claude-code/*/claude.exe"
    )
    $candidates = foreach ($pattern in $paths) { Get-Item -Path $pattern -EA SilentlyContinue }
    return ($candidates | Sort-Object @{ Expression = {
        if ($_.FullName -match '(?:claude-code[-/\\])(\d+\.\d+\.\d+)') { [version]$Matches[1] }
        else { [version]'0.0.0' }
      }; Descending = $true } | Select-Object -First 1 -ExpandProperty FullName)
  }
  if ($Name -eq 'hermes') {
    $hermesDir = if ($env:HERMES_HOME) { $env:HERMES_HOME } else { Join-Path $env:LOCALAPPDATA 'hermes' }
    foreach ($candidate in @((Join-Path $hermesDir 'bin/hermes.exe'), (Join-Path $hermesDir 'bin/hermes.cmd'))) {
      if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
  }
}
