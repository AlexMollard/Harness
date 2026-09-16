---
name: omp-provider-rerouting-diagnosis
description: "Prove which model definition actually serves an omp inference request and reroute built-in providers (registerProvider limits, same-id precedence, dead-port discriminator, headroom /v4 stats blind spot). Use when rerouting omp models through a proxy or debugging \"is my request going through the proxy\" questions."
---

# omp provider rerouting — what works, what doesn't, and how to prove it

Verified against omp v18.1.16 (2026-09-10, D:/NightSmith workstation user).

## Hard constraints (all URL/registry-level proven)

- `pi.registerProvider(name, config)` with `models:` **replaces** the provider's built-in catalog (registry-level) and **requires `apiKey` or `oauth`** when models are defined. `apiKey` accepts an **environment-variable NAME** (`S$` resolver: env lookup, else literal; `!` prefix = command). Use `apiKey: "SOME_ENV_VAR"` — never the secret.
- With custom models you MUST set `authHeader: true` or no `Authorization: Bearer` header is built (`Gx`/`_Ut`: Bearer added only when authHeader truthy + apiKeyConfig present).
- Per-model `baseUrl` in a registered model def **is honored** (`Hke`: `baseUrl: u.baseUrl ?? providerBaseUrl`) — but **only for ids the built-in catalog doesn't already have**. Same-id overrides lose to the built-in def on the inference path (models.yml same-id models and runtime registerProvider overlays alike).
- Copy `compat` **verbatim** from the bundle. The request layer reads non-schema compat keys directly off the model def (`zaiReasoningEffortDialect`, `clampOutputToModelMax`, `officialEndpoint`, `supportsSamplingParams`, `nativeKimiK3Reasoning`, …). Filtering to the models.yml `OpenAICompatFields` schema silently changes request behavior. `registerProvider` does no compat-key validation (manual checks in `b6e` only).
- Strip only true junk fields: `provider`, `int`, `tps`, `identity`, `requiresGlyphTokenization`, `supportsComputerUse`.
- `--no-extensions` disables extension-discovered extensions (explicit `-e` still loads). Verify which flag a run needs before believing any test result.

## The dead-port discriminator (proves which def serves a request)

`omp -p` output and `--mode json` events never reveal the request URL. headroom-style proxies' `/stats` may not count passthrough routes (headroom does NOT count `--openai-api-url` `/v4` catch-all traffic — see below), so stats deltas prove nothing. The reliable test:

1. Register the provider/model with `baseUrl: "http://127.0.0.1:9"` (dead port).
2. Run the real request WITHOUT `--no-extensions`.
3. **Reply succeeds** → built-in def won (same-id bypass proven). **Connection error** → extension def served (your rerouting is live).
4. Differential variant: register an extension-ONLY id (not in built-in catalog); if it resolves and reaches the dead port, extensions definitely load on the inference path (`-p` print mode DOES load user extensions from `~/.omp/agent/extensions/`).
5. On HTTP 400 responses omp dumps the full request (URL, headers, body) to `~/.omp/logs/http-400-requests/<ts>-*.json` — the only built-in URL-level evidence. Point baseUrl at the real proxy but send a bogus model id to force a 400 and read the URL.

## Case study: routing built-in `zai/glm-5.3-flash` through headroom (2026-09-10)

- Goal: keep the id `zai/glm-5.3-flash` but change its URL → **impossible on v18.1.16** (same-id precedence). Working alternative: a custom `zai-headroom` provider in models.yml + modelRoles.
- Model catalogs live in `~/.bun/install/global/node_modules/@oh-my-pi/pi-coding-agent/dist/cli.js` as minified `{zai:{"glm-…":{…}},zenmux:…}` — brace-match entries (watch for `m.end(0)-1` off-by-one) and parse with a string/bracket-aware splitter (`!0`→true, `1e6`→1000000).
- Keep only real model fields; keep compat verbatim (above).
- headroom `/stats` (`requests.by_model`, `request_logs`, `recent_requests`, `persistent_savings`) counts only pipeline-processed traffic (gemini/anthropic pipelines), never `/v4` passthrough — never use it to prove /v4 routing.
