<div align="center">

# Harness

**One agent configuration. Two harnesses. Any machine.**

Shared rules, skills, commands, hooks and settings for
[Claude Code](https://claude.com/claude-code), omp and Hermes — version-controlled,
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
> No key is required — skip them all and you get a working Claude-only setup.

Axiom is optional and lives in its [standalone private repository](https://github.com/AlexMollard/Axiom).
Its configuration and vault are private and outside both repositories; follow the
Axiom setup and recovery instructions if you want shared memory on this machine.
Harness installation does not require Axiom or its vault.

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
| 3 | Hand over to `install.ps1` — config, skills, wiring, verify | Stops at the first failed gate |

Nothing installs silently — every command is printed and needs a `y`. Where a tool is
installed *by* another (omp by bun), that one is offered first.

| Tool | | Installed with |
|---|---|---|
| `git` | required | `winget install Git.Git` |
| `claude` | required | `winget install Anthropic.ClaudeCode` |
| `node` (22+) | required | `winget install --id OpenJS.NodeJS.LTS -e` |
| `omp` | optional | `bun install -g @oh-my-pi/pi-coding-agent` |
| `rtk` | optional | `winget install rtk-ai.rtk` |
| `jscpd` | optional | `npm install -g jscpd` |

> [!NOTE]
> winget builds of Claude Code don't auto-update; set
> `CLAUDE_CODE_PACKAGE_MANAGER_AUTO_UPDATE=1` if you want that.

Anything replaced is kept beside the original as `<file>.pre-install`. Re-running is
safe; every step is idempotent.

</details>

---

## What's in it

| | |
|---|---|
| 📜 **Instructions** | 7 core entries, read by both harnesses |
| 🧠 **Skills** | 8 always indexed, 108 on demand |
| ⌨️ **Commands** | 3 slash commands, shared |
| 🪝 **Hooks** | Billing and line-ending guards; optional Axiom hooks are installed separately |
| ⚙️ **Machine config** | Claude Code settings + hooks, omp config/models (roles belong to omp-maestro) |
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
_restore/        every file verbatim as it was before unification
```

---

## The instruction set

Loaded into every session on both harnesses, except the optional Axiom import.

| File | Lines | Governs |
|---|--:|---|
| `00-identity.md` | 13 | Form of address, CRLF output |
| `10-commit-style.md` | 17 | Imperative subject, no prefixes/emoji/attribution |
| `20-principles.md` | 75 | Don't downgrade on time, done means it ran, ground in reality, leave the neighbourhood alone, skillify, delegate by default |
| `30-gatekeeper.md` | 49 | The Interview gate and having a view before building; Ponytail governs the build |
| `50-rtk.md` | 6 | RTK token-optimising CLI proxy |
| `60-github-billing.md` | 19 | Zero GitHub spend — manual-dispatch workflows only, no metered storage |
| `70-shared-memory.md` | 1 | Imports Axiom's contract when its standalone instructions exist |

How small to build is not here: the [Ponytail](https://github.com/DietrichGebert/ponytail)
plugin, installed in both harnesses, owns that.

**How each harness reads it** — Claude Code via `@~/agent-core/...` in
`~/.claude/CLAUDE.md`, omp via the same stub in `~/.omp/agent/AGENTS.md`. Both resolve
`@` imports natively, so **nothing is generated** and no copy can drift. Edit a file in
`core/` and it takes effect at the next session start.

Hermes is the exception: it has no import syntax and reads `SOUL.md` only from
`%LOCALAPPDATA%\hermes`, so `build.ps1` writes that one file with every `@~/` line
inlined, and `verify.ps1` fails when it drifts. Rerun `build.ps1` after editing `core/`.
Its settings live in `configs/hermes/settings.yaml` (applied with `hermes config set`;
Hermes keeps its own generated `config.yaml`). They flow repo → machine only:
`export-config.ps1` does not capture Hermes, so add a key there to keep it. Its hooks reuse the Claude hooks through
`configs/hermes/hooks/claude-hooks-bridge.mjs`. Hermes re-asks for consent when that
script changes: run `hermes hooks doctor`, and if it reports drift, `hermes hooks revoke`
and `hermes --accept-hooks` once.

### Optional Axiom integration

[Axiom](https://github.com/AlexMollard/Axiom) supplies shared memory, native harness
adapters and a local dashboard. Clone it to `~/Axiom` and configure its private
vault separately; neither vault contents nor live configuration belong in Harness.
When `~/Axiom/integrations/instructions.md` exists, `build.ps1` includes its
contract through `core/70-shared-memory.md`; otherwise it skips that import.

`install.ps1` invokes Axiom's installer only when `~/Axiom/scripts/install.mjs` and its
private configuration exist and Node is available. The configuration defaults to
`%LOCALAPPDATA%/Axiom/config.json` on Windows (or `~/.config/Axiom/config.json`
without `LOCALAPPDATA`), and `SHARED_BRAIN_CONFIG` overrides it. Axiom owns its
native hooks; see its repository for setup, linking its CLI, and recovery.
Harness preserves existing Claude auto-memory and omp memory settings when installing
its portable config. Only after Axiom's installer succeeds does it disable those
competing stores; if Axiom is skipped or fails, their existing settings remain.
Owner notes are protected by instructions and ordinary agent write guards, not
isolated from unrestricted shell or code execution.


---

## Model roles

omp's model roles belong to the omp-maestro plugin, not this repo. Pick an ensemble
with `/maestro <ensemble>` inside omp; `install.ps1` leaves roles alone.

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
| `PreToolUse` Write/Edit/Bash | `github-billing-gate` | **blocks** anything that would bill GitHub |
| `PostToolUse` | telemetry | always |

The discovery gate has the property that makes a hook survive daily use: **a binary
trigger, never a guess at intent.** It stays silent everywhere else, never blocks, and
exits 0 on malformed input.

### The billing gate is different — it blocks

> [!CAUTION]
> This account runs at **zero GitHub spend**, and `github-billing-gate` is what makes
> that a guarantee rather than an intention. It denies the tool call outright.

It stops exactly two things, both objectively checkable:

1. A `.github/workflows` file whose `on:` block names any trigger other than
   `workflow_dispatch` — or that uploads artifacts or caches, which bill for storage
   even from a manual run. **A manual-dispatch-only workflow passes**, which is the
   "explicit or manually run" carve-out.
2. A command touching a metered surface: Actions minutes, Packages (GHCR), Git LFS,
   or Codespaces.

> [!NOTE]
> This is about **billing, not caution**. Commit, push, pull, fetch, clone, branch,
> tag, open and merge PRs, cut releases — all free, all allowed, none of it needs
> asking. The rule says so explicitly, because over-applying it is its own failure
> mode and no hook can fix an agent being needlessly timid.

Its command patterns are anchored at a *command position*, so writing **about** one of
them — a doc, a test fixture, a commit message quoting `git lfs` — doesn't trip it.
A blocking hook that cries wolf is one you learn to disable.

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
| `handoff` | Context is running low; capture what the next session needs |
| `handoffplan` | Handoff, then a phased plan referencing it |
| `pressure-test` | Test an approach against scalability, cost, efficiency |
| `sidenote` | Park a thought without derailing the current task |
| `dedupe-refactor` | Find duplicated logic, plan a consolidation, apply approved clusters |

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
| `GPUSTACK_API_KEY` | optional | local Qwen for `commit`, `tiny`, `smol` |
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
| **Live** | Asks each harness three questions whose answers appear **only** inside `core/` — a harness that failed to resolve its import answers `MISSING` |

> [!TIP]
> Discovery hooks exit 0 silently; billing and optional Axiom guards can deliberately
> block an action. Exercise both allowed and denied paths instead of trusting file presence.

---

## Scripts

| Script | Does |
|---|---|
| `setup.bat` / `setup.ps1` | Guided install — the one to run on a new machine |
| `install.ps1` | Repo → machine, seven gates |
| `export-config.ps1` | Machine → repo, secrets redacted |
| `build.ps1` | Write the instruction import stubs |
| `sync-skills.ps1` | Pool and junction skills + commands |
| `verify.ps1` | Prove it all still works |

<details>
<summary><b>Undo</b></summary>

<br>

```powershell
.\sync-skills.ps1 -Unlink   # harness dirs become real, populated dirs again
git show d2940d9            # every original file, verbatim
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

Codex, opencode and Hermes were supported and removed (2026-09-16). Hermes came back
on 2026-11-20 as a fresh setup on the OpenAI plan: an always-on gateway and cron
harness that shares this repo's rules, skills and Axiom memory. A local headroom
proxy fronted all traffic until 2026-09-21, when it was removed after measuring ~2% token
savings — which did not justify pinning `ANTHROPIC_BASE_URL` at a port a fresh machine
would have nothing listening on. Adapters and configs for all of them remain in git
history.

</details>
