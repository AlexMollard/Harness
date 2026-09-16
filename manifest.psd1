# Which core files each harness loads, in order.
# Edit this, then run build.ps1. Composition is decided here and nowhere else.
@{
  claude   = @('00-identity','10-commit-style','20-principles','30-gatekeeper','40-code-discovery','50-rtk')
  omp      = @('00-identity','10-commit-style','20-principles','30-gatekeeper','40-code-discovery','50-rtk')
  # opencode is the only harness on the mind MCP server, so it is the only one
  # that loads 45-memory-mind.
  opencode = @('00-identity','10-commit-style','20-principles','30-gatekeeper','40-code-discovery','45-memory-mind','50-rtk')
}
