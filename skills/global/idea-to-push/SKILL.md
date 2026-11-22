---
name: idea-to-push
description: Alex's flow for any code change in any repo, from a plain-words idea to the push they make themself - pick a weight (light, normal, heavy), agree acceptance checks, build, verify mechanically, their own run, audit and adjudicate (heavy only), fix, re-check the changed behaviour, one history cleanup, record and measure. Covers where they step in and what each interruption means. Use when starting a non-trivial change, when they say "do the usual flow", "get this ready to push" or "clean up the branch before I push", or ask to audit and fix a branch.
---

# Idea to push

Agents read, build, check and audit. Alex sets direction, judges how it looks and feels, approves the history rewrite, and pushes. The aim is confidence that comes from **what the system demonstrably does**, not from how many agents reviewed it. Use their attention only where an agent cannot get the answer itself.

## Inputs
- `repo`: the checkout, the branch, and its base (`origin/<default>` unless told otherwise).
- `conventions`: read these rather than assume them. That means the repo's `AGENTS.md` / `CLAUDE.md` and area files (commit format, encoding, build and test commands, banned patterns) plus the user's global rules.
- `run_target`: what they run themself (a game, an app, a dev server) and how it loads. Some code loads at launch with no build; some needs a data or asset build.
- `evidence`: what an agent can inspect without them, such as log files, traces, a debug overlay, a sandbox, or a way to inject disconnects or delays. Note what is missing; missing evidence is the first infrastructure to propose.
- `record`: where outcomes go. That is a shared plan artifact or project note, plus the metrics log `Agents/Memory/General/Idea-to-push metrics.md`.
- `guard`: processes a build must not run over, such as the game exe. Pass them to `verify-change`.

## 0. Pick the weight
Choose from the change itself, say which in one line, and let them overrule it.

| Weight | When | Track |
|---|---|---|
| **Light** | Cosmetic, copy, a one-file fix with an obvious check | brief scope → build → `verify-change` and a focused check → their look → record |
| **Normal** | A behaviour change in one area | acceptance checks → build → tests and `verify-change` → one focused review → their run → final checks → cleanup → record |
| **Heavy** | Lifecycle, concurrency, persistence, a wire contract between repos, a broad refactor | contract or design review → acceptance checks including fault scenarios → build → their run → audit → adjudicate → fix → final checks → cleanup → record |

Move up a weight when the change turns out to touch lifecycle, concurrency or a contract. Never move down silently.

## 1. Interview (Gate 1)
- Restate the goal, scope and done-condition in two or three lines.
- Read the code first and search shared memory.
- Ask only what changes the build. Batch the questions, each with a recommended default.
- **Acceptance checks (Normal and Heavy).** Turn the worked examples into a table of scenario → pass condition.
  - Include at least one edge case.
  - For Heavy, include the fault scenarios: drop, delay, a late reply after leaving the screen, repeated reconnects.
  - The checks are the spec: reviewers, testers and the final check all work from them.
  - Keep them with the task, in the plan artifact or the record.
- Wait for the go-ahead before any behaviour change.

When they interrupt here:
- *They redirect* with context only they have, such as other UI on screen or how it feels. Adopt it and update the checks. Don't argue it again.
- *"Would X be better?"*: give your honest recommendation and the reason.
- *They approve*: one yes covers exactly that action.

## 2. Build (Gate 2)
- Build the smallest change that passes the checks, and reuse what the repo has.
- Root-cause bugs from evidence (logs, traces, a diagnostic print). Don't guess.
- Commit as each task finishes, in the repo's format.
- **Coordination.** With more than one writer, the coordinator (you) keeps an ownership table:
  - which agent owns which change and its checks;
  - the files and interfaces each must not touch;
  - the dependencies between client, server and shared contracts;
  - whether the combined result has been tested.
- Independent writers each get their own worktree. Reviewers stay read-only.
- A shared doc or artifact has one writer at a time, who re-reads the live version and merges.

When they interrupt here:
- *"Also..."*: fold it in if it belongs to this change, and add its check. Otherwise propose it as its own task.
- *They stop machine control*: stop driving their PC, app or input at once.

## 3. Verify mechanically
From the repo, run:

```
pwsh ~/agent-core/tools/verify-change.ps1 -Process <guard> -Run '<check>'...
```

- It refuses when a guarded process is running.
- It catches an added BOM, line-ending churn and mixed endings.
- It runs the given checks (lint, syntax, the narrowest tests, the build).
- It appends a record of what ran to `<git dir>/verify-change.jsonl`.

Fix what it reports. Don't re-run it with checks removed.

Exercise each acceptance check that can run without them: a unit test, a script, a sandbox scenario. State plainly which checks still need their run.

Keep a regression check for every real bug fixed, as the repo allows. In the handball client those tests stay local-only in `build/scripts/tests/` and are never committed.

## 4. Their run (the main loop)
They run `run_target` and judge what only a person can: layout, motion, feel.

When they report back:
- *A bug report with evidence*: back to step 2. First get what you can from `evidence` yourself, and ask them to reproduce only what you can't inspect. When you must ask, say exactly which scenario to try and what to send back.
- *A regression caused by your fix*: same loop. Find out why the fix broke it before patching again.
- *"Perfect"*: the loop is closed.

Every manual repro you needed is a sign of missing `evidence`. Note it for the metrics log, and propose the tooling if it keeps happening.

## 5. Audit and adjudicate (Heavy, or when they ask)
**Audit.** Run read-only auditors in parallel, one per area of the diff. Specialised areas beat generic "check everything" sweeps. A finding counts only if it gives all four of:
- the acceptance check or invariant it violates;
- a reachable trigger and the code path it takes;
- evidence: a reproduction, a failing test, a trace, or a tight static argument;
- the smallest fix.

Findings about hypothetical risks with no reachable trigger are dropped, not fixed.

**Adjudicate.** A fresh agent, given no conclusions, assesses each finding independently. It attempts a reproduction and looks for counterexamples, then classifies the finding as **confirmed**, **refuted** or **unresolved**, with evidence and any correction to the fix.
- Failing to disprove a finding does not prove it.
- Failing to reproduce a timing bug does not refute it.
- Unresolved findings go to them with the evidence for a decision. They are not fixed by default.

Save the findings and the verdicts yourself, because subagents may not be able to write files.

## 6. Fix
- A new agent fixes the confirmed findings, plus any unresolved ones they chose.
- It follows the verdicts' corrections, with the smallest fix each and no extra hardening.
- For several fixers on one repo, use `fixer-wave-orchestration` from the skill catalogue.
- Check its claims yourself: a clean tree, nothing local-only committed, and `verify-change` passing.

## 7. Final checks
- Re-run `verify-change`.
- Re-exercise the acceptance checks for every behaviour that changed after their run.
- If a fix changed behaviour they had judged, they check those scenarios again.
- A content-identical history rewrite needs no new run.

## 8. One history cleanup
Do this once, after all fixes, with the `/squash` command.
1. Propose contiguous themed groups and their messages, and get their yes.
2. Tag a backup.
3. Rebuild with `commit-tree`.
4. Prove the content is identical: `git diff --stat <backup> <new>` must be empty.
5. Move the branch, then give them the undo command and the tag-delete command.

Never push. A later follow-up is folded in the same way, with its own yes.

## 9. Record and measure
- Log the outcome to `record`. Re-read the live version first, merge, and never overwrite others' entries.
- Save durable facts to the shared brain under `Agents/`.
- Add one row to `Agents/Memory/General/Idea-to-push metrics.md`:
  - date, repo, task and weight;
  - their active supervision, as rough minutes or "not known" (never guess);
  - manual repro cycles;
  - bugs found after "done";
  - audit findings raised, then confirmed and fixed.
- Report the commits, the `verify-change` result, which acceptance checks passed, and what they still need to check in `run_target`.

## 10. Push
- The push is theirs alone.
- Force-pushing a shared branch needs their explicit say-so.
- If CI is wanted, run it locally or with a manual dispatch, never with automatic triggers.

## How to read their interruptions
| They say | Step | Means |
| --- | --- | --- |
| "X would be better because Y" | 1 | Redirect: adopt it and update the checks |
| "yes, build it" / "yes, squash" / "yes, fold it" | 1, 8 | One-time approval for exactly that action |
| "also ..." | 2 | Scope: the same change with a new check, or a separate task |
| a log line, timing or screenshot | 4 | Bug loop: inspect `evidence` first, then root-cause |
| "perfect" | 4 | Loop closed |
| "send off an agent to ..." | any | A side task with its own owner; don't block the main track |
| "stop control of pc" | any | Stop driving their machine immediately |
