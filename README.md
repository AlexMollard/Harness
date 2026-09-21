<div align="center">

# Harness

**One agent configuration. Two harnesses. Any machine.**

Shared rules, skills, commands, hooks and settings for
[Claude Code](https://claude.com/claude-code) and omp — version-controlled,
verifiable, and installable in one step.

![PowerShell 7+](https://img.shields.io/badge/PowerShell-7%2B-5391FE?logo=powershell&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-10%2F11-0078D4?logo=windows&logoColor=white)
![Secrets](https://img.shields.io/badge/secrets-never%20committed-2ea44f)
![MCP servers](https://img.shields.io/badge/MCP%20servers-0-lightgrey)

</div>

---

## Quick start

```powershell
git clone https://github.com/AlexMollard/Harness.git "$HOME\agent-core"
cd "$HOME\agent-core"
.\setup.bat
```

Or just **double-click `setup.bat`**.

It checks your tools and **offers to install anything missing**, asks for any API keys
you don't have, saves them to your user environment, installs everything and verifies
the result — stopping at the first problem rather than leaving you half-configured.

> [!NOTE]
> Keys are typed into a masked prompt and written via .NET straight to the user
> environment. They are never echoed, logged, passed on a command line, or committed.
> Only `GPUSTACK_API_KEY` is required — skip the rest and you get a working
> Claude-only setup.

<details>
<summary><b>What setup.bat actually does</b></summary>

<br>

`setup.bat` is a thin launcher: it makes sure PowerShell 7 is present (offering a
`winget` install if not) and hands over to `setup.ps1`, so there is one implementation
rather than a batch copy that drifts.

| Step | What happens | On failure |
|:--:|---|---|
| 1 | Check each tool below, show the exact command, install on `y` | Stops only if a **required** tool is still missing |
| 2 | Work out which API keys the config needs, prompt for missing ones | Stops only if a **required** key is skipped |
| 3 | Hand over to `install.ps1` — config, roles, skills, wiring, verify | Stops at the first failed gate |

Nothing installs silently — every command is printed and needs a `y`. Where a tool is
installed *by* another (omp by bun, graphify by uv), that one is offered first.

| Tool | | Installed with |
|---|---|---|
| `git` | required | `winget install Git.Git` |
| `claude` | required | `winget install Anthropic.ClaudeCode` |
| `omp` | optional | `bun install -g @oh-my-pi/pi-coding-agent` |
| `rtk` | optional | `winget install rtk-ai.rtk` |
| `graphify` | optional | `uv tool install graphifyy` |

> [!NOTE]
> The PyPI package really is `graphifyy` — the plain name is being reclaimed upstream.
> Run `graphify install` afterwards to finish its setup. winget builds of Claude Code
> don't auto-update; set `CLAUDE_CODE_PACKAGE_MANAGER_AUTO_UPDATE=1` if you want that.

Anything replaced is kept beside the original as `<file>.pre-install`. Re-running is
safe; every step is idempotent.

</details>

---

## What's in it

| | |
|---|---|
| 📜 **Instructions** | 6 core files, 362 lines, read by both harnesses |
| 🧠 **Skills** | 8 always indexed, 108 on demand |
| ⌨️ **Commands** | 3 slash commands, shared |
| 🪝 **Hooks** | 4, including 2 discovery gates that enforce what instructions can't |
| ⚙️ **Machine config** | Claude Code settings + hooks, omp config/models/roles |
| 🔌 **MCP servers** | none, by measurement |

```
core/            the rules — harness-neutral, edit these
adapters/        per-harness dialect only
manifest.psd1    which core files each harness loads
commands/        pooled slash commands, junctioned into each harness
skills/
  global/        always-indexed skills
  managed/       108 omp autolearn skills
configs/         this machine's config, secrets redacted
  omp/roles.psd1 which model serves each omp role
_restore/        every file verbatim as it was before unification
```

---

## The instruction set

Loaded into every session on both harnesses.

| File | Lines | Governs |
|---|--:|---|
| `00-identity.md` | 9 | Form of address, CRLF output |
| `10-commit-style.md` | 34 | Imperative subject, no prefixes/emoji/attribution |
| `20-principles.md` | 172 | 8 sections: think first, simplicity, surgical changes, goal-driven execution, time recalibration, skillify, ground-in-reality, delegate-by-default |
| `30-gatekeeper.md` | 98 | Two gates — the Interview and the Ponytail ladder |
| `40-code-discovery.md` | 20 | Using `graphify` when a project has a graph |
| `50-rtk.md` | 29 | RTK token-optimising CLI proxy |

> [!TIP]
> [`AUDIT.md`](AUDIT.md) measures what this costs per session, the contradictions found
> and fixed, and 2026 research on whether files like this help at all.

**How each harness reads it** — Claude Code via `@~/agent-core/...` in
`~/.claude/CLAUDE.md`, omp via the same stub in `~/.omp/agent/AGENTS.md`. Both resolve
`@` imports natively, so **nothing is generated** and no copy can drift. Edit a file in
`core/` and it takes effect at the next session start.

---

## Model roles

omp's roles are assigned from what the machine can actually reach, per
[`configs/omp/roles.psd1`](configs/omp/roles.psd1).

| Role | Default | With `ZAI_API_KEY` |
|---|---|---|
| `plan` | `claude-opus-5:high` | `glm-5.3-flash:high` |
| `task` | `claude-sonnet-5:low` | `glm-5.3-flash:low` |
| `advisor` | `claude-opus-5:low` | `glm-5.3-flash:low` |
| `smol` | `qwen3.8-27b-nvfp4:off` | `glm-5.3-flash:low` |

`commit`, `tiny`, `default`, `slow`, `vision` and `SeriousBuisness` are untouched.

> [!IMPORTANT]
> This can't be conditional YAML. omp's `resolve-config-value.ts` does
> `return envValue || valueConfig` — an unset env var resolves to the **literal
> string**, which is then sent as the bearer token and 401s. There is no graceful
> runtime degradation, so the branch has to happen when config is written.

Role assignment is install-time policy, not machine state, so `export-config.ps1`
normalises it back to the default before committing. A PC holding a Z.AI key runs GLM
without pushing that onto everyone who clones the repo.

---

## Hooks — the enforcement layer

> [!WARNING]
> Instructions in `core/` are **context, not enforcement**. Anthropic's docs are
> explicit: *"Claude treats them as context, not enforced configuration. To block an
> action regardless of what Claude decides, use a PreToolUse hook instead."* A rule
> buried 85 directives into 362 lines loses to habit. A hook fires at the moment the
> habit shows up.

| Event | Hook | Fires when |
|---|---|---|
| `PreToolUse` Bash | `rtk hook claude` | always — routes commands through the RTK proxy |
| `PreToolUse` Grep/Glob | `graphify-discovery-gate` | `graphify-out/graph.json` exists |
| `PreToolUse` WebFetch | `context7-docs-gate` | the URL host is a known docs host |
| `PostToolUse` | telemetry | always |

Both discovery gates share the property that makes a hook survive daily use: **a binary
trigger, never a guess at intent.** They stay silent everywhere else, never block, and
exit 0 on malformed input. Add a docs host via `DOCS_HOSTS` in
[`configs/claude/hooks/context7-docs-gate`](configs/claude/hooks/context7-docs-gate).

---

## Skills

<details>
<summary><b>Always indexed (8)</b> — junctioned into both harnesses</summary>

<br>

| Skill | Use when |
|---|---|
| `skillify` | Turn something you just did into a reusable skill |
| `check-resolvable` | Audit the skill library for DRY/MECE violations |
| `skill-catalogue` | A task looks project-specific and nothing listed covers it |
| `graphify` | Any question about a codebase's architecture |
| `handoff` | Context is running low; capture what the next session needs |
| `handoffplan` | Handoff, then a phased plan referencing it |
| `pressure-test` | Test an approach against scalability, cost, efficiency |
| `sidenote` | Park a thought without derailing the current task |

</details>

<details>
<summary><b>On demand (108)</b> — reachable but deliberately not indexed</summary>

<br>

Written by omp's autolearn. Their descriptions total ~40,000 characters — about 10k
tokens **per session** if listed. The `skill-catalogue` entry costs ~343 characters and
reaches all of them.

| Domain | Count | Examples |
|---|--:|---|
| Android + Monarch | 49 | R8 release verification, Compose accessibility sweep, Room migration |
| AntHill | 16 | K8s deploy verify, release tagging, lore merge recovery |
| Load testing | 7 | Harness truthfulness, paced arrivals, collapse triage |
| Git + agent ops | 7 | Rebase without checkout, scrub a path from history |
| .NET + Aspire | 6 | Revert-proof regression tests, stale SDK phantom errors |
| Agent harness | 5 | omp provider rerouting, Antigravity routing |
| Platform + perf | 4 | gamecore trace latency, WHEA triage, WebView2 input |
| Data + backend | 4 | Postgres RLS hardening, Supabase erasure assertions |
| Other | 10 | Shallow codebase audits, file-integrity proofs |

</details>

**Slash commands** — `/pressure-test` (test an approach against the three pillars),
`/sidenote` (log a passing thought), `/squash` (squash commits into clean themes).

---

## MCP servers

**None** — a measured decision, not an oversight.

Over 60 days, Claude Code's two servers drew **17 calls** between them against **9,615**
for the built-in browser; omp made **zero** MCP calls in 24,088 tool calls. `aethercore`
alone injected 106 tool schemas into every session.

> [!CAUTION]
> Config is not evidence of use. Re-check before adding one back:
>
> ```bash
> grep -rhoE '"name":"mcp__[^"]+"' ~/.claude/projects --include='*.jsonl'
> grep -rhoE '"type":"toolCall".*"name":"[^"]+"' ~/.omp/agent/sessions
> ```

---

## Settings that matter

`configs/claude/settings.json` carries enabled plugins, effort level and
`autoCompactWindow: 500000`.

That last one earns its place. With a 1M window, auto-compaction defaults to ~970k, so
context never resets and every turn re-sends more. Measured across 443 sessions, **6% of
sessions carried 83% of all input tokens.** Capping at 500k models out at roughly **46%
fewer input tokens**. omp gets the same via `compaction.thresholdTokens`.

---

## Secrets

No key is ever committed. `export-config.ps1` rewrites a literal API key to an ALL_CAPS
env var name and **fails the export** if anything secret-shaped survives. A key is only
*required* when the baseline config actually routes a role at that provider — anything
else warns and installs anyway.

| Variable | Status | Unlocks |
|---|---|---|
| `GPUSTACK_API_KEY` | required | `commit` and `tiny` roles |
| `ZAI_API_KEY` | optional | GLM-5.3-Flash for `plan`, `task`, `advisor`, `smol` |

Absolute home paths are stored as `__HOME__` and expanded on install, so a different
username on the next machine doesn't break anything.

---

## Verification

```powershell
.\verify.ps1            # everything, including a live call to each harness
.\verify.ps1 -Static    # disk only — fast and free
```

| Layer | What it proves |
|---|---|
| **Wiring** | Each harness file actually imports `agent-core` |
| **Hooks** | Every hook wired in `settings.json` exists, and each gate speaks *and stays silent* in the right conditions |
| **Roles** | Installed roles match the policy for this machine's credentials, and every provider a role names is defined |
| **Live** | Asks each harness three questions whose answers appear **only** inside `core/` — a harness that failed to resolve its import answers `MISSING` |

> [!TIP]
> Hooks exit 0 silently by design so they can never block work — which also means a
> broken one is invisible. These checks are what make it visible.

---

## Scripts

| Script | Does |
|---|---|
| `setup.bat` / `setup.ps1` | Guided install — the one to run on a new machine |
| `install.ps1` | Repo → machine, seven gates |
| `export-config.ps1` | Machine → repo, secrets redacted |
| `build.ps1` | Write the instruction import stubs |
| `sync-skills.ps1` | Pool and junction skills + commands |
| `set-omp-roles.ps1` | Apply the model-role policy |
| `verify.ps1` | Prove it all still works |

<details>
<summary><b>Undo</b></summary>

<br>

```powershell
.\sync-skills.ps1 -Unlink   # harness dirs become real, populated dirs again
git show 038dda0            # every original file, verbatim
```

`-Unlink` removes only the junction; the pool is untouched. Nothing here deletes a file
— superseded directories are renamed to `<dir>.preunify`.

</details>

<details>
<summary><b>History</b></summary>

<br>

Before this, the same guidelines existed in three hand-maintained copies and had already
drifted: Codex was missing section 8 and the entire Gatekeeper, its file had collapsed
markdown and a dead `@RTK.md` import, and nothing was under version control. omp was the
only harness doing it right — a thin dialect file that *imported* the shared body. This
repo generalises that pattern.

Codex, opencode and Hermes were supported and removed (2026-09-16). A local headroom
proxy fronted all traffic until 2026-09-21, when it was removed after measuring ~2% token
savings — which did not justify pinning `ANTHROPIC_BASE_URL` at a port a fresh machine
would have nothing listening on. Adapters and configs for all of them remain in git
history.

</details>
