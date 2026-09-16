---
name: antigravity-ide-headroom-routing
description: Route the standalone Antigravity IDE application through the local Headroom proxy via the jetski.cloudCodeUrl configuration setting. Use when asked to configure Antigravity IDE with Headroom or redirect its language server requests.
---

# Route Antigravity IDE through Headroom Proxy

Standing setup on this machine: route Google Antigravity IDE (standalone VS Code fork) traffic through the local Headroom proxy.

## Mechanism

Antigravity IDE determines its backend Cloud Code endpoint via the internal configuration property `jetski.cloudCodeUrl`.
In `out/main.js`:
```javascript
cloudCodeUrlOverride: this._configurationService.getValue("jetski.cloudCodeUrl")
```
When `jetski.cloudCodeUrl` is set:
1. `getBaseUrl()` returns this value verbatim without falling back to `https://cloudcode-pa.googleapis.com`.
2. Antigravity IDE launches its Go language server (`language_server_windows_x64.exe`) with:
   `--cloud_code_endpoint http://127.0.0.1:<port>`
3. Background services and chat streaming forward all requests (`/v1internal:...` and `/v1internal:streamGenerateContent`) through Headroom.

## Procedure

1. **Find the running Headroom port:**
   ```powershell
   powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"name='headroom.exe'\" | Select-Object CommandLine"
   ```
   Default is port `8787`. Never use port 8080 (static directory index).

2. **Configure `settings.json` in Antigravity IDE:**
   Add `"jetski.cloudCodeUrl": "http://127.0.0.1:<port>"` (no trailing slash).
   Set in both the active profile and the default profile:
   - Active profile (e.g. "Mine"):
     `%APPDATA%\Antigravity IDE\User\profiles\<profile-id>\settings.json`
   - Default profile:
     `%APPDATA%\Antigravity IDE\User\settings.json`

3. **Restart the Language Server:**
   The language server reads `--cloud_code_endpoint` at spawn time.
   In Antigravity IDE:
   - Press `Ctrl+Shift+P` -> run `Developer: Reload Window`
   - Or completely restart the Antigravity IDE executable.

4. **Verify:**
   Confirm running process arguments for `language_server_windows_x64.exe`:
   ```powershell
   powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'language_server' } | Select-Object CommandLine"
   ```
   Check that `--cloud_code_endpoint http://127.0.0.1:<port>` is present.
