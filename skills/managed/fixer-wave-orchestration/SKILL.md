---
name: fixer-wave-orchestration
description: "Run parallel fixer subagents over a verified findings list with exclusive file ownership, then acceptance-verify and commit thematically. Use after an audit produces a verified findings list, or whenever several edit agents will touch one repo concurrently."
---

# Fixer wave: findings → ownership-split fixers → acceptance

The complement of `shallow-codebase-audit` (scouts find) and `verify-delegated-edits` (acceptance): this covers the fix dispatch itself. Run it once per verified findings list; repeatable per audit round.

## Dispatch
1. Split findings into agent briefs by **exclusive file ownership** — no file appears in two rosters. Consolidate same-file findings into one agent even when themes differ; that agent owns the whole file.
2. Each brief carries, per finding: file:line, the verified mechanism (not just the symptom), and the intended fix approach. Plus hard rules: house comment style (say WHY, name the concrete failure), build gate `dotnet build <sln> --nologo -v minimal` → 0 errors, no commits, targeted suites only, central package management (no inline Version=).
3. Test files are owned by nobody: required test edits (constructor arity, signature callers, fixture shapes) are REPORTED by the agent and applied by the parent or assigned explicitly — otherwise an agent's "all green" hides a broken sibling test project.
4. Shared-file hot regions: hub-message the owning agent mid-flight ("keep clear of line N — parent applies that fix there") and apply those yourself after the agent lands.
5. List not-worth-acting findings explicitly as out-of-scope so nobody wanders into them.

## Acceptance (verify-delegated-edits applies in full)
1. `git status --porcelain=v1 --untracked-files=all` + `git diff --stat`: touched set == union of rosters; zero deletions; zero scratch files.
2. Read every hunk. **Compact diff renderers drop words and can hide a deleted argument line** — after multi-agent edits, read the RAW file at collision regions and concurrency-sensitive changes. A real regression was caught exactly this way: a build stayed green while an optional record parameter was silently omitted, nulling data.
3. Full gate: build 0 errors + every targeted suite. Flaky/environmental suites: compare failure signatures to the documented baseline and stash-attribute new ones (stash agent files → rerun → pop).
4. Commit thematically (one commit per fix cluster); straggler test-file updates get a small follow-up commit.

## Traps learned (each cost real time)
- bash expands `$` inside double-quoted `powershell -Command "..."`. Pass code via an env var and invoke with single-quoted bash: `powershell -NoProfile -Command '$env:CHECK | Invoke-Expression'`.
- PowerShell: `'-p:x=' + $var` inside a comma-list is **array + string concat** (commas bind tighter) — the value becomes a stray positional arg (MSB1008). Use expandable strings `"-p:x=$var"`.
- Agents editing concurrently break sibling builds transiently. Attribute via stash+rerun; run the final gate only after all agents settle, and read raw files — an agent's "0 errors" was measured mid-flight of others.
- A build passing with a dropped argument to an optional record parameter is a real regression: optional defaults convert compile-time failures into silent null data that tests on fakes cannot see.
- When an agent changes shared helper signatures (e.g. `Note(msg)` → `Note(msg, problem)`), grep ALL call sites afterwards — a real failure rendered as neutral/informational is the failure mode of missing one.
