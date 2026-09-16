---
name: headroom-output-shaper
description: Enable the beta output shaper in Headroom and seed/apply verbosity learning to start measuring output-token savings.
---

# Headroom Output Shaper & Verbosity Learning

Use this procedure when enabling the beta output shaper or re-measuring output savings in Headroom.

## Procedure

1. **Seed verbosity baseline and learn preferences**:
   ```bash
   headroom learn --verbosity --apply
   ```
   - Analyzes past sessions across detected agents.
   - Saves learned level to `~/.headroom/verbosity.json`.
   - Seeds baseline strata into `~/.headroom/output_savings.json`.

2. **Configure environment variables**:
   Set user environment variables so they persist across shell restarts:
   ```powershell
   [System.Environment]::SetEnvironmentVariable('HEADROOM_ROLLOUT_CHANNEL', 'beta', 'User')
   [System.Environment]::SetEnvironmentVariable('HEADROOM_OUTPUT_SHAPER', '1', 'User')
   ```
   Ensure startup scripts or extension guardians (e.g. `~/.omp/agent/extensions/headroom-startup.ts`) also pass these variables when launching the proxy.

3. **Restart the Headroom proxy**:
   - Stop any existing instances:
     ```powershell
     Get-Process *headroom* -ErrorAction SilentlyContinue | Stop-Process -Force
     ```
   - Start the proxy with the desired flags:
     ```bash
     headroom proxy --port 8787 --memory --code-aware --openai-api-url <URL>
     ```

4. **Verify rollout & measurement status**:
   - Check feature enablement:
     ```bash
     headroom rollout status
     ```
     Ensure `proxy_output_shaper` shows `enabled=true`.
   - Check savings baseline:
     ```bash
     headroom output-savings
     ```
   - Check health:
     ```bash
     headroom doctor
     ```
