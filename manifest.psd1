# Which core files each harness loads, in order.
# Edit this, then run build.ps1. Composition is decided here and nowhere else.
@{
  claude   = @('00-identity','10-commit-style','20-principles','30-gatekeeper','40-code-discovery','50-rtk')
  omp      = @('00-identity','10-commit-style','20-principles','30-gatekeeper','40-code-discovery','50-rtk')
  # codex omits 45-memory-mind on purpose: the mind MCP server writes its own
  # <!-- mind managed protocol --> block into ~/.codex/AGENTS.md, which build.ps1
  # preserves. Including it here too would duplicate the protocol.
  codex    = @('00-identity','10-commit-style','20-principles','30-gatekeeper','40-code-discovery','50-rtk')
  opencode = @('00-identity','10-commit-style','20-principles','30-gatekeeper','40-code-discovery','45-memory-mind','50-rtk')
}
