@{
  # omp model-role policy.
  #
  # Role assignment is install-time policy, not machine state: which model serves
  # a role depends on which credentials the machine actually has. install.ps1
  # applies this with -Mode auto; export-config.ps1 normalises back to `base`, so
  # a PC that happens to hold a Z.AI key does not commit GLM roles as the baseline
  # every other machine would then install.
  #
  # Why here and not in models.yml: omp has no conditional provider. Its
  # resolve-config-value.ts does `return envValue || valueConfig` - an unset env
  # var resolves to the LITERAL string, which is then sent as the bearer token and
  # 401s. There is no graceful runtime degradation, so the branch has to happen
  # when the config is written.
  #
  # Roles absent from every map below (commit, tiny, default, slow, vision,
  # SeriousBuisness) are left exactly as config.yml has them.

  # Always applied. Works with no credentials beyond an Anthropic login.
  base     = @{
    plan    = 'anthropic/claude-opus-5-5:high'
    task    = 'anthropic/claude-sonnet-5:low'
    advisor = 'anthropic/claude-opus-5-5:low'
    smol    = 'gpustack/qwen3.8-27b-nvfp4:off'
  }

  # Applied over `base`, in order, when the named env var is set.
  overlays = @(
    @{
      name  = 'zai'
      key   = 'ZAI_API_KEY'
      why   = 'GLM-5.3-Flash is far cheaper than Opus for planning and bulk work'
      roles = @{
        plan    = 'zai/glm-5.3-flash:high'
        task    = 'zai/glm-5.3-flash:low'
        advisor = 'zai/glm-5.3-flash:low'
        smol    = 'zai/glm-5.3-flash:low'
      }
    }
  )
}
