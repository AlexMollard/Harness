---
name: idea-to-push
description: Pog Champ's end-to-end flow for any code change in any repo, from a plain-words idea to the push they make themself - interview, minimal build, agent checks, their own run of the app, squash, audit/disprove/fix, fold and record - including where they step in and what each interruption means. Use when starting a non-trivial change, when they say "do the usual flow", "get this ready to push", "clean up the branch before I push", or ask to squash, audit and fix a branch.
---

# Idea to push

The track every change follows. Agents read, build, check and audit; Pog Champ sets direction, runs the real thing, approves every history rewrite and pushes. Each step names the interruptions that normally come at it, so you can tell what an interruption is asking for.

## Inputs
- `repo` - the checkout and branch the change lands on; its base (`origin/<default>` unless told otherwise).
- `conventions` - read them, don't assume: the repo's `AGENTS.md` / `CLAUDE.md` / area files (commit format, encoding, build and test commands, banned patterns), plus the user's global rules.
- `run_target` - how Pog Champ exercises the change for real: a game build, an app, a dev server, a sandbox. Find out how it loads (some code loads at launch with no build; some needs a data or asset build).
- `record` - where outcomes are logged: a shared plan artifact, a shared-brain project note, or nothing.

## Procedure

1. **Idea** - Pog Champ sends a plain-words idea or complaint, often with a screenshot or log line. Treat it as the symptom or goal, not the design.

2. **Interview (Gate 1).** Restate goal, scope and done-condition in 2-3 lines. Read the code first (graphify when `graphify-out/` exists) and search shared memory. List the assumptions you would otherwise code on; ask only what changes the build, batched, each with a recommended default. For anything non-obvious give three concrete examples including an edge case.
   - *They redirect:* they overrule a recommendation with context only they have (what else is on screen, how it feels). Rebuild the plan on their answer; don't relitigate.
   - *They question:* "would X be better?" wants your honest recommendation and the reason, not agreement.
   - *They approve:* "yes, build it". Nothing that changes behaviour starts before this.

3. **Build (Gate 2).** Smallest change that satisfies the agreement; reuse what the repo has; mark any shortcut with its ceiling. Follow `conventions` (line endings, encoding, keep existing BOMs, style of the file). Root-cause any bug with evidence (diagnostic logging over guessing). Commit as each task finishes in the repo's format. Never build or replace a binary they may be running - check the process first.
   - *They add scope ("also..."):* fold it into the plan if it belongs to this change; propose it as its own task if not.
   - *They stop machine control:* drop anything driving their PC, app or input at once; ask before ever doing it again.

4. **Agent checks.** Syntax/lint, the narrowest tests first, then the suites; a real build with its exit code and error count read, not filtered away. Say plainly what is unverified ("built, not run"). They rarely interrupt here.

5. **Their run - the main loop.** They run `run_target` and report what they see.
   - *Bug report with evidence:* back to step 3, root-cause first. If the evidence is thin, add a targeted diagnostic print and ask them for the line.
   - *Regression from your own fix:* same loop; find why the fix broke it before patching again.
   - *"perfect" / "works":* the loop is closed; move on.

6. **Squash** (the `/squash` command). Propose contiguous themed groups and messages; get their yes before rewriting. Tag a backup, rebuild with `commit-tree`, prove the content identical (`git diff --stat <backup> <new>` empty), then move the branch. Give the undo and tag-delete commands. Never push.

7. **Audit, disprove, fix** - when they ask for a code pass (they usually do after a squash).
   - **Audit:** parallel read-only auditors, one per area of the branch diff (e.g. transport/state, screens/UI, native/wire contract against the other side). Each finding: id, kind, severity, confidence, file:line evidence, a concrete failure scenario, suggested fix. Save the findings yourself (subagents may not be able to write files).
   - **Disprove:** one fresh agent, not given your conclusions, tries to refute every finding against the real code and returns STANDS / PARTLY / DISPROVED per id with evidence and fix corrections. Save its verdicts; they override the findings.
   - **Fix:** a new agent fixes only the survivors, following the verdicts' corrections, in a few themed commits; checks and builds as in step 4. For several parallel fixers on one repo, use `fixer-wave-orchestration` from the skill catalogue. Verify its claims yourself (clean tree, nothing local-only committed, syntax checks) before reporting.
   - *They run side quests in parallel* (tidy a doc, clean an artifact) and may widen the scope mid-run: send each to its own agent; forward scope changes with SendMessage.

8. **Fold and record.** Offer to fold small follow-ups into the commit they belong to; on their yes, backup tag, cherry-pick/amend, prove identical, move the branch. Log the outcome to `record` (re-read live first, merge, never overwrite others' entries). Save durable facts to the shared brain under `Agents/`. Report: commits, build/test results, and what they still need to check in `run_target`.
   - *They approve each rewrite separately* - an earlier yes never covers the next one.

9. **Push - theirs alone.** Never push for them. A force-push of a shared branch happens only on an explicit say-so. If CI is wanted, it runs locally or by manual dispatch (no automatic triggers).

## Interruption cheat-sheet
| They say | Step | Means |
| --- | --- | --- |
| "X would be better because Y" | 2 | Redirect: adopt it, rebuild the plan |
| "yes, build it" / "yes, squash" / "yes, fold it" | 2, 6, 8 | One-time approval for exactly that action |
| "also ..." | 3 | Scope addition: same change, or a separate task |
| a log line, timing or screenshot | 5 | Bug loop: root-cause from the evidence |
| "perfect" | 5 | Loop closed: go to clean-up |
| "send off an agent to ..." | any | Side quest in parallel; don't block the main track |
| "stop control of pc" | any | Stop driving their machine immediately |
