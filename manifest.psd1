# Which core files each harness loads, in order.
# Edit this, then run build.ps1. Composition is decided here and nowhere else.
@{
  claude   = @('00-identity','10-commit-style','20-principles','30-gatekeeper','50-rtk','60-github-billing','70-shared-memory')
  omp      = @('00-identity','10-commit-style','20-principles','30-gatekeeper','50-rtk','60-github-billing','70-shared-memory')
  hermes   = @('00-identity','10-commit-style','20-principles','30-gatekeeper','50-rtk','60-github-billing','70-shared-memory')
}
