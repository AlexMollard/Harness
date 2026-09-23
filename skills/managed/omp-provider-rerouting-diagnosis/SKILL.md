---
name: omp-provider-rerouting-diagnosis
description: "Use when rerouting omp models through a proxy, proving which definition and URL serve a request, or when omp models hit connection errors after a proxy or env change. Covers the ANTHROPIC_BASE_URL override, same-id precedence, registerProvider limits, models.yml schema traps, and the dead-port discriminator."
---

# omp provider rerouting — what works, what doesn't, and how to prove it

Verified against omp v18.1.16 (2026-09-10, D:/NightSmith workstation user); the
`ANTHROPIC_BASE_URL` and debug-log facts against v18.2.9 (2026-09-23).

## Hard constraints (all URL/registry-level proven)

- **`ANTHROPIC_BASE_URL` reroutes every built-in `anthropic/*` model.** `resolveDirectAnthropicBaseUrl` (pi-ai `providers/anthropic-state.ts`) returns it whenever the model's own baseUrl is the official endpoint; only Foundry mode or a non-official per-model baseUrl beats it. A value pointing at a dead proxy port fails every Anthropic turn with `Connection error.` Shells opened before the variable changed keep the old value (a new Windows Terminal tab picks up the new one).
- `pi.registerProvider(name, config)` with `models:` **replaces** the provider's built-in catalog (registry-level) and **requires `apiKey` or `oauth`** when models are defined. `apiKey` accepts an **environment-variable NAME** (`S$` resolver: env lookup, else literal; `!` prefix = command). Use `apiKey: "SOME_ENV_VAR"` — never the secret.
- With custom models you MUST set `authHeader: true` or no `Authorization: Bearer` header is built (`Gx`/`_Ut`: Bearer added only when authHeader truthy + apiKeyConfig present).
- Per-model `baseUrl` in a registered model def **is honored** (`Hke`: `baseUrl: u.baseUrl ?? providerBaseUrl`) — but **only for ids the built-in catalog doesn't already have**. Same-id overrides lose to the built-in def on the inference path (models.yml same-id models and runtime registerProvider overlays alike).
- Copy `compat` **verbatim** from the bundle. The request layer reads non-schema compat keys directly off the model def (`zaiReasoningEffortDialect`, `clampOutputToModelMax`, `officialEndpoint`, `supportsSamplingParams`, `nativeKimiK3Reasoning`, …). Filtering to the models.yml `OpenAICompatFields` schema silently changes request behavior. `registerProvider` does no compat-key validation (manual checks in `b6e` only).
- Strip only true junk fields: `provider`, `int`, `tps`, `identity`, `requiresGlyphTokenization`, `supportsComputerUse`.
- models.yml schema: model entries accept `baseUrl` and `headers`; `modelOverrides` accepts `headers` but NOT `baseUrl`. Unknown keys silently drop the WHOLE provider, so run `omp models find <id>` after every edit. A provider with a `models:` array needs provider-level `baseUrl` AND `apiKey`, and a models.yml `apiKey:` is a literal (env-var names resolve in `registerProvider`, not here).
- `--config` overlays are settings-style and silently do nothing for provider blocks. models.yml/config.yml edits need a NEW omp process; a running session keeps its startup snapshot.
- `--no-extensions` disables extension-discovered extensions (explicit `-e` still loads). Verify which flag a run needs before believing any test result.

## The dead-port discriminator (proves which def serves a request)

`omp -p` output and `--mode json` events never reveal the request URL, and proxy dashboards may not count passthrough routes (headroom's `/stats` never counted its `/v4` catch-all), so stats deltas prove nothing. One exception: for Anthropic requests to a plain-http URL, the debug log `~/.omp/logs/omp.<date>.<pid>.log` records `cowork transport bypassed` with the `url` (reason `not-https`). The reliable test:

1. Register the provider/model with `baseUrl: "http://127.0.0.1:9"` (dead port).
2. Run the real request WITHOUT `--no-extensions`.
3. **Reply succeeds** → built-in def won (same-id bypass proven). **Connection error** → extension def served (your rerouting is live).
4. Differential variant: register an extension-ONLY id (not in built-in catalog); if it resolves and reaches the dead port, extensions definitely load on the inference path (`-p` print mode DOES load user extensions from `~/.omp/agent/extensions/`).
5. On HTTP 400 responses omp dumps the full request (URL, headers, body) to `~/.omp/logs/http-400-requests/<ts>-*.json` — URL-level evidence that also works for https targets. Point baseUrl at the real proxy but send a bogus model id to force a 400 and read the URL.

## Case study (historical): routing built-in `zai/glm-5.3-flash` through headroom (2026-09-10)

Headroom was removed from this machine on 2026-09-23 and nothing starts it. This
is kept for the rerouting lessons, not as a setup to restore.

- Goal: keep the id `zai/glm-5.3-flash` but change its URL → **impossible on v18.1.16** (same-id precedence). Working alternative: a custom `zai-headroom` provider in models.yml + modelRoles.
- Model catalogs live in `~/.bun/install/global/node_modules/@oh-my-pi/pi-coding-agent/dist/cli.js` as minified `{zai:{"glm-…":{…}},zenmux:…}` — brace-match entries (watch for `m.end(0)-1` off-by-one) and parse with a string/bracket-aware splitter (`!0`→true, `1e6`→1000000).
- Keep only real model fields; keep compat verbatim (above).
- headroom `/stats` (`requests.by_model`, `request_logs`, `recent_requests`, `persistent_savings`) counts only pipeline-processed traffic (gemini/anthropic pipelines), never `/v4` passthrough — never use it to prove /v4 routing.
