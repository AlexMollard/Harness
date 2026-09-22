# Which core files each harness loads, in order.
# Edit this, then run build.ps1. Composition is decided here and nowhere else.
@{
  claude   = @('00-identity','10-commit-style','20-principles','30-gatekeeper','40-code-discovery','50-rtk','60-github-billing')
  omp      = @('00-identity','10-commit-style','20-principles','30-gatekeeper','40-code-discovery','50-rtk','60-github-billing')
}
