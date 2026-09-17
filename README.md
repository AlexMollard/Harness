# Harness

One agent configuration, two harnesses: **Claude Code** and **omp**. Clone it on a
new machine, run one script, and you have the same rules, skills, commands, hooks
and settings you had on the old one.

Everything here is declarative and version-controlled. No secret is ever committed.

---

## What's in it

| | |
|---|---|
| **Instructions** | 6 core files, 362 lines, read by both harnesses |
| **Global skills** | 8, indexed in every session |
| **On-demand skills** | 108, reachable but not indexed (see *Skill tiering*) |
| **Slash commands** | 3, shared by both harnesses |
| **Hooks** | 5, including 2 discovery gates that enforce what instructions can't |
| **Machine config** | Claude Code settings + hooks, omp config/models/mcp |
| **Scripts** | build, verify, sync-skills, export-config, install |

```
core/          the actual rules - harness-neutral, edit these
adapters/      per-harness dialect only (how a skill is invoked, memory backend)
manifest.psd1  which core files each harness loads
commands/      pooled slash commands, junctioned into each harness
skills/
  global/      always-indexed skills, junctioned into each harness
  managed/     108 omp autolearn skills, carried between machines
  catalogue.md generated index of all of them
configs/       this machine's Claude Code and omp config, secrets redacted
_restore/      every file verbatim as it was before unification
```

---

## The instruction set

Loaded into every session on both harnesses. `20-principles` and `30-gatekeeper`
are the bulk of it.

| File | Lines | What it governs |
|---|---:|---|
| `00-identity.md` | 9 | Form of address, CRLF output convention |
| `10-commit-style.md` | 34 | Imperative subject, no prefixes/emoji/attribution, flat bullet bodies |
| `20-principles.md` | 172 | 8 sections: think before coding, simplicity, surgical changes, goal-driven execution, time recalibration, skillify, ground-in-reality, delegate-by-default |
| `30-gatekeeper.md` | 98 | Two gates - the Interview (no code on unverified assumptions) and the Ponytail (a 7-rung ladder against gold-plating), plus off switches |
| `40-code-discovery.md` | 20 | How to use `graphify` when a project has a graph |
| `50-rtk.md` | 29 | RTK token-optimising CLI proxy |

An audit of this instruction set - measured token cost, the contradictions found and
fixed, and 2026 research on whether files like this help at all - is in
[`AUDIT.md`](AUDIT.md).

---

## Skills

### Always indexed (8)

Junctioned into both harnesses, so they appear in every session's skill list.

| Skill | Use when |
|---|---|
| `skillify` | Turn something you just did into a reusable skill |
| `check-resolvable` | Audit the skill library for DRY/MECE violations |
| `skill-catalogue` | A task looks project-specific and nothing listed covers it |
| `graphify` | Any question about a codebase's architecture or relationships |
| `handoff` | Context is running low; capture what the next session needs |
| `handoffplan` | Handoff, then a phased implementation plan referencing it |
| `pressure-test` | Test an approach against scalability, long-term cost, efficiency |
| `sidenote` | Park a passing thought without derailing the current task |

### On demand (108)

Written by omp's autolearn, kept out of the session index on purpose - their
descriptions total ~40,000 characters, about 10k tokens per session if listed. The
`skill-catalogue` entry costs ~343 characters and reaches all of them.

| Domain | Count | Examples |
|---|---:|---|
| Android + Monarch | 49 | R8 release verification, Compose accessibility sweep, KSP dropped-import recovery, Room migration survival |
| AntHill | 16 | K8s deploy verify, release tagging, lore merge recovery, shared-CSS verify |
| Load testing | 7 | Harness truthfulness, paced arrivals, collapse triage, bottleneck triage |
| Git + agent ops | 7 | Rebase without checkout, scrub a path from local history, verify delegated edits, fixer-wave orchestration |
| .NET + Aspire | 6 | Revert-proof regression tests, stale SDK phantom errors, Docker restart recovery |
| Agent harness | 5 | omp provider rerouting, headroom output shaper, Antigravity routing |
| Platform + perf | 4 | gamecore trace latency, WHEA triage, SN-DBS distribution probe, WebView2 input |
| Data + backend | 4 | Postgres RLS hardening, Supabase erasure assertions, view-privacy proofs |
| Other | 10 | Shallow codebase audits, file-integrity proofs, remote repo surveys |

---

## Slash commands

Pooled once, junctioned into both harnesses.

| Command | What it does |
|---|---|
| `/pressure-test` | Test the current approach against the three pillars, then recommend |
| `/sidenote` | Log a passing thought as a later-task |
| `/squash` | Squash commits from a given commit to HEAD into clean thematic commits |

---

## MCP servers

**None.** Both harnesses run with zero configured MCP servers, and that is a
measured decision rather than an oversight.

Over 60 days, Claude Code's two servers drew **17 calls** between them against
**9,615** for the built-in browser; omp made **zero** MCP calls in 24,088 tool
calls. `aethercore` alone was injecting 106 tool schemas into every session. The
full numbers are in [`AUDIT.md`](AUDIT.md).

Re-check before adding one back - config is not evidence of use:

```bash
grep -rhoE '"name":"mcp__[^"]+"' ~/.claude/projects --include='*.jsonl'
grep -rhoE '\{"type":"toolCall","id":"[^"]*","name":"[^"]+"' ~/.omp/agent/sessions
```

---

## Hooks - the enforcement layer

Instructions in `core/` are **context, not enforcement**. Anthropic's own docs say
so: *"Claude treats them as context, not enforced configuration. To block an action
regardless of what Claude decides, use a PreToolUse hook instead."* A rule sitting
85 directives into 362 lines loses to habit. A hook fires at the moment the habit
shows up.

| Event | Hook | Fires when |
|---|---|---|
| `PreToolUse` Bash | `rtk hook claude` | always - rewrites commands through the RTK proxy |
| `PreToolUse` Grep/Glob | `graphify-discovery-gate` | `graphify-out/graph.json` exists in the project |
| `PreToolUse` WebFetch | `context7-docs-gate` | the URL host is a known library-docs host |
| `SessionStart` | `headroom-startup` | startup and resume |
| `PostToolUse` | telemetry | always |

The two discovery gates share the property that makes a hook survive contact with
daily use: **a binary trigger, never a guess at intent.** `graphify-discovery-gate`
checks one thing - does a graph file exist - and walks up six levels so it works
from a subdirectory. `context7-docs-gate` matches the fetch URL against a host list
in the script, and says nothing unless the context7 plugin is actually enabled. Both
are silent everywhere else, neither ever blocks, and both exit 0 on malformed input.

A hook that fires on everything is a hook you learn to ignore.

Add a docs host by editing `DOCS_HOSTS` inside `configs/claude/hooks/context7-docs-gate`.

### Settings

`configs/claude/settings.json` also carries enabled plugins, the effort level, and
`autoCompactWindow: 500000`.

That last one matters. With a 1M context window auto-compaction defaults to ~970k,
so context never resets and every turn re-sends more. Measured across 443 sessions,
**6% of sessions carried 83% of all input tokens**. Capping at 500k models out at
roughly **46% fewer input tokens**. omp gets the same cap via
`compaction.thresholdTokens`.

Only hooks actually wired in `settings.json` are exported, so unwired scripts can't
come back on a fresh machine.

---

## How each harness reads it

Deliberately different - each host's own primitive beats a generator we maintain:

| Harness | Mechanism |
|---|---|
| Claude Code | `@~/agent-core/...` import stub in `~/.claude/CLAUDE.md` |
| omp | the same import stub in `~/.omp/agent/AGENTS.md` |

Both resolve `@` imports natively, so **nothing is generated** - there is no second
copy that can drift. Editing a file in `core/` takes effect at the next session
start, with no build step.

Codex, opencode and Hermes were supported and then removed (2026-09-16); their
adapters remain in git history.

---

## Usage

```powershell
./build.ps1 -WhatIf      # preview instruction wiring
./build.ps1              # wire both harnesses
./sync-skills.ps1 -Link  # pool and link skills + commands
./verify.ps1 -Static     # check wiring on disk (fast, free)
./verify.ps1             # probe each live harness for core-only facts
./export-config.ps1      # capture this machine's config into the repo
```

### Setting up a new machine

```powershell
git clone https://github.com/AlexMollard/Harness.git ~/agent-core
cd ~/agent-core
./install.ps1 -WhatIf
./install.ps1
```

Six gates in order, stopping at the first failure rather than leaving a
half-configured machine: prerequisites on PATH -> required env vars -> config files
-> managed skills -> wiring -> verify. Anything replaced is kept as
`<file>.pre-install`.

### Undo

```powershell
./sync-skills.ps1 -Unlink        # harness dirs become real, populated dirs again
git show 038dda0                 # every original file, verbatim
```

`-Unlink` removes only the junction; the pool is untouched. Nothing here deletes a
file - superseded dirs are renamed to `<dir>.preunify`.

---

## Secrets

No key is ever committed. `export-config.ps1` rewrites a literal API key to an
ALL_CAPS env var name - the convention `models.yml` already used for GPUStack - and
the export **fails** if anything secret-shaped survives the rewrite. `install.ps1`
refuses to run until every named var is set, so a missing key surfaces up front
rather than at runtime.

Currently required: `GPUSTACK_API_KEY`, `ZAI_HEADROOM_API_KEY`.

Absolute home paths are stored as `__HOME__` and expanded on install, so a different
username on the next machine doesn't break the hooks.

---

## Verification

`verify.ps1` asks each live harness three questions whose answers appear only inside
`core/`: the name of Gate 2, the title of section 8, and what RTK stands for. A
harness that failed to resolve its import answers MISSING.

That is the check that catches drift coming back - run it after every build. Both
harnesses pass live at last run.

---

## History

Before this, the same guidelines body existed in three hand-maintained copies and
had already drifted: Codex was missing section 8 and the entire Gatekeeper, its file
had collapsed markdown and a dead `@RTK.md` import, and nothing was under version
control. omp was the only harness doing it right - a thin file of dialect that
*imported* the shared body. This repo generalises that pattern.
