---
name: antigravity-headroom-routing
description: "Route oh-my-pi provider traffic through the local headroom proxy and verify end-to-end — Z.ai GLM via headroom's OpenAI pipeline (client /chat/completions + x-headroom-base-url/x-headroom-original-path headers; streams and shows on dashboard), Antigravity/Gemini (models.yml baseUrl), the traps (catch-all /v4 buffers SSE and is invisible in /stats; same-id overlays lose on inference; modelOverrides has headers but no baseUrl; env vars do nothing; models.yml strict schema; ~15-40s cold-start on first heavy request after a headroom restart — headroom-startup.ts auto-warms), port discovery, and smoke tests. Use when asked to route any omp provider via headroom, when models don't appear in the headroom dashboard, when proxied models stream as one big dump, or when the first prompt after a headroom restart hangs ~40s."
---

# Route providers through headroom (oh-my-pi → headroom → upstream)

Standing setup on this machine: all omp provider traffic must flow through the local headroom proxy. **Env vars do nothing for omp** (`ZAI_BASE_URL`, `OPENAI_BASE_URL`, `HEADROOM_BASE_URL` are never read — verified 0 occurrences in the omp bundle). `ANTHROPIC_BASE_URL=http://127.0.0.1:8787` IS set user-wide and routes Claude Code through headroom — **never repoint headroom's anthropic pipeline away from api.anthropic.com**, or Claude Code breaks.

## Verified facts (headroom 0.37.0, omp 18.1.16; re-check if the environment changes)

- headroom 0.37.0 (pipx `headroom-ai`, venv `~/pipx/venvs/headroom-ai`) launched by `~/.omp/agent/extensions/headroom-startup.ts` on omp session_start (checks `/livez` first, spawns detached with env `HEADROOM_ROLLOUT_CHANNEL=beta`, `HEADROOM_OUTPUT_SHAPER=1`). Current target: `headroom.exe proxy --port 8787 --memory --code-aware --openai-api-url https://api.z.ai/api/coding/paas/v4 --provider-name "Z.AI"`. **Port 8080 is a static file server** — never point config at it.
- **Cold start**: on a fresh headroom process the FIRST heavy request pays ~15-40s (lazy embedding-model load for cache/memory lookups); warm TTFB ≈ direct + ≤1s. `headroom-startup.ts` therefore auto-warms right after spawn: polls `/livez`, then fires one throwaway `max_tokens:1` completion through the zai route (real `ZAI_API_KEY` + the two x-headroom headers). Verified: cold warmup 15.3s → heavy TTFB right after 5.46s. Recurs only per headroom process, not per omp session.
- Headroom has five upstream pipelines: anthropic/openai/gemini/cloudcode/vertex. The OpenAI chat handler joins `<target> + /v1/chat/completions` for plain `/v1/...` requests — z.ai has **no `/v1` alias** (404 verified). That kills the naive "target=…/paas/v4 + client /v1" recipe.
- **Z.ai GLM pattern that works (pipeline route — streams, counts on dashboard)**: client baseUrl `http://127.0.0.1:8787` (ROOT — omp appends `/chat/completions`) + provider-level `headers:`:
  ```yaml
  headers:
    x-headroom-base-url: https://api.z.ai/api/coding/paas/v4
    x-headroom-original-path: /chat/completions
  ```
  Headroom's route table (`route_specs.py`) maps unprefixed `POST /chat/completions` to the real `handle_openai_chat` pipeline (not the catch-all); `_resolve_openai_upstream_base` honors `x-headroom-base-url` (origin+path, SSRF-gated to public hosts) and `_resolve_openai_handler_path` honors `x-headroom-original-path` (must end with `/chat/completions`). Upstream join = `target + /chat/completions` = z.ai's real endpoint. Requests appear in `/stats` `requests.by_model` (glm-5.3-flash), `by_provider` (shows `--provider-name`, e.g. "Z.AI"), `recent_requests`, and `persistent_savings.by_model`.
- **The `/v4` catch-all is a trap**: client baseUrl `http://127.0.0.1:8787/v4` → `handle_passthrough` → works (HTTP 200) BUT buffers the entire SSE response and flushes at once (measured: 101 chunks at one instant vs direct z.ai spread over 1s) → clients "idle 50s then dump". Catch-all traffic is ALSO invisible in `/stats` (probe-proven: a forwarded request appears in no stats array). Never use it for interactive clients.
- **Semantic-cache replays look like instant answers**: identical prompts return the whole response in one instant (cache hit). Use a unique nonce prompt when testing streaming, or you will misread cache hits as buffering (or vice versa).
- **Pipeline-path hazards** (default-on with `--memory`): (1) semantic response cache can false-match and replay a WRONG response (observed once: one-line prompt answered with another session's cached refusal); (2) memory-context injection adds stored memories into the system prompt and can steer the model (observed: refusal driven by an injected stale memory). No per-request bypass header exists. `--no-cache` disables the response cache globally (compression/Kompress unaffected) — recommend when correctness beats savings.
- **The built-in `zai` provider cannot be rerouted** (proven): (1) models.yml same-id custom `models:` under `zai:` — built-in catalog wins on the inference path (dead-port discriminator: extension def with `baseUrl: 127.0.0.1:9` registered, request still succeeded direct); (2) extension `registerProvider("zai", …)` — registry shows the override (`omp models find` count changes) but same-id inference still uses the built-in def; (3) `modelOverrides` — `ModelOverrideSchema` has `headers?` but **NO `baseUrl`** (v18.1.16); (4) provider-level `baseUrl` loses to every built-in zai model's own per-model baseUrl (`Hke`: `u.baseUrl ?? t`); (5) env vars. The ONLY working mechanism is a **custom provider id** (`zai-headroom`), then `config.yml` `modelRoles` point at it.
- `registerProvider` details (if the extension route is ever revisited): with `models:` it REPLACES the provider catalog (find shows the new count) and REQUIRES `apiKey` or `oauth`; `apiKey: "ZAI_API_KEY"` (env-var NAME) resolves via `S$` — no secret in file. `authHeader: true` is required or no `Authorization: Bearer` is sent. omp `-p` print mode DOES load user extensions; `--no-extensions` disables discovery (never use it when testing an extension). Keep model `compat` VERBATIM from the bundle — the request layer reads non-schema keys (`officialEndpoint`, `zaiReasoningEffortDialect`, `clampOutputToModelMax`, `supportsSamplingParams`, …) directly.
- models.yml schema (v18.1.16): model entries (`ModelDefinitionSchema`) support `baseUrl` AND `headers`; `ModelOverrideSchema` supports `headers` but NOT `baseUrl`. Unknown keys silently drop the WHOLE provider — check `omp models find <id>` after any edit. A provider with a `models:` array REQUIRES provider-level `baseUrl` AND `apiKey`. `apiKey:` in models.yml takes a LITERAL key (env-name references do not resolve there).
- Antigravity: models.yml `google-antigravity: baseUrl: http://127.0.0.1:8787` works (cloudcode pipeline; streams + counts). Unaffected by the openai target.
- **Dashboard traps**: `agent_usage.agents` only buckets KNOWN agents — custom providers never appear there. `requests.by_provider` shows the `--provider-name` label for the openai leg (e.g. "Z.AI"), coarse client buckets otherwise (e.g. "gemini"). The per-model savings table shows `glm-5.3-flash` — but ONLY pipeline-routed requests tally; catch-all traffic never appears.

## config.yml (the piece that makes it "just work")

`~/.omp/agent/config.yml` `modelRoles`: `default/plan/task/slow: zai-headroom/glm-5.3-flash:*` (effort suffixes preserved). `commit/smol/tiny/vision` on gpustack (direct, accepted), `advisor` on google-antigravity (already via headroom). If glm traffic "isn't going through headroom", check modelRoles FIRST. Config edits need an omp process restart — a running session keeps its startup snapshot (users report "dashboard shows nothing" simply because their session predates the edit).

## models.yml (current, working)

```yaml
providers:
  google-antigravity:
    baseUrl: http://127.0.0.1:8787
  zai-headroom:
    baseUrl: http://127.0.0.1:8787
    apiKey: <ZAI_API_KEY literal>
    api: openai-completions
    authHeader: true
    headers:
      x-headroom-base-url: https://api.z.ai/api/coding/paas/v4
      x-headroom-original-path: /chat/completions
    models:
      - id: glm-5.3-flash
        name: GLM-5.3-Flash (Headroom)
        api: openai-completions
        baseUrl: http://127.0.0.1:8787
        # …cost/contextWindow/maxTokens/tokenizer/thinking/compat as before
        #   (compat = the full OpenAICompatFields-safe set, see models.yml)
```

The built-in `zai/*` ids remain listed but route DIRECT to z.ai (their anthropic-messages GLMs can never transit this headroom: the anthropic pipeline is pinned to real Anthropic for Claude Code).

## Procedure

1. **Find the headroom port/args**: `Get-Process headroom | Select-Object Id,StartTime,Path` (WQL filters with embedded quotes get mangled through bash). Single instance expected; multiple = kill all and start one.
2. Edit `~/.omp/agent/models.yml` per above; keep `headroom-startup.ts` launch args in sync; point `config.yml` modelRoles at `zai-headroom/…`.
3. Restart headroom: kill ALL instances (running omp sessions' guardians respawn with THEIR snapshotted args when `/livez` fails — kill again until one clean instance with the new args remains), then relaunch with matching args; verify `/livez` 200. The guardian auto-warms on its next session_start; for immediate testing fire the warmup manually (tiny `max_tokens:1` completion through the route) before trusting TTFB numbers.
4. **Smoke test (zai leg, streaming proof)**: unique-nonce prompt, `stream: true`, POST `http://127.0.0.1:8787/chat/completions` with the two x-headroom headers → pass = 200 `text/event-stream` with content chunks SPREAD over seconds (single-instant = cache hit or buffering). Non-unique prompts may hit the semantic cache and return instantly — that is by design.
5. **Smoke test (antigravity leg)**: POST `/v1internal:streamGenerateContent?alt=sse` with fake bearer + `User-Agent: antigravity/2.8.0` → pass = HTTP 401 with Google headers (`server: ESF`).
6. **End-to-end (user parity)**: new omp process only: `omp -p --no-tools --no-session --model zai-headroom/glm-5.3-flash "Reply with exactly: ROUTED"`, then check `/stats` `by_model` gained a glm-5.3-flash count. Give `--max-time` generous headroom — glm reasoning at max effort can exceed 60s.
7. Blackhole discriminator (does a def actually serve?): point that def's baseUrl at `http://127.0.0.1:9/...` — success despite a dead port proves the def was IGNORED (built-in fallback); connection-refused proves it was used.

## Traps

- `--config` overlays are SETTINGS-style, not models.yml-style — they silently do nothing for provider blocks.
- models.yml/config.yml edits need a NEW omp process; a running session keeps its startup snapshot. Running sessions' headroom guardians keep their OLD spawn args until the session reloads the extension.
- `ZAI_BASE_URL=8787` sits in HKCU\Environment as an inert leftover (omp ignores it); harmless for other tools.
- bash → powershell: double-quoted bash strips `$env:`/`$var` — wrap the whole powershell command in single quotes; avoid `os.system` for PowerShell (cmd.exe mangles quoting) and WQL filters with embedded quotes (use `Get-Process` instead).
- Don't trust secondhand "stats" field names (`model_counts`, `totalRequests` do not exist in `/stats`); the real keys are `summary.api_requests`, `requests.by_model/by_provider`, `recent_requests`, `persistent_savings.by_model`.
