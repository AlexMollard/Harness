---
name: dedupe-refactor
description: Launches a refactoring agent that finds duplicated or ad hoc logic in a codebase using a clone detector and git churn, ranks clusters by impact, proposes a consolidation plan, and applies only the clusters the user approves, with tests pinned first. Use when the user says "dedupe this repo", "find duplicated code", "consolidate the ad hoc logic", or runs /dedupe-refactor.
argument-hint: "[target-path] [focus] [--apply]"
---

# Dedupe refactor

Hands the brief in [prompt.md](prompt.md) to a subagent in two legs, analysis then
edits, with the user's approval between them. Arguments: `$ARGUMENTS`

## Inputs
- `target` — repo or folder to analyse. Default: the session's working directory.
- `focus` — optional narrowing (a subfolder, module or priority tier). Default: whole target.
- `--apply` — auto-apply. Only when the user typed it or said so in words. Default: stop at the plan.

## Checklist
Copy this and tick it off as you go:
```
- [ ] 1. Target resolved, git state checked
- [ ] 2. Leg 1 (analysis) returned a plan with cluster IDs and a baseline
- [ ] 3. Plan relayed, approved cluster IDs recorded
- [ ] 4. Branch agreed, leg 2 (edits) finished
- [ ] 5. Diff read and checks re-run here
```

## Procedure
1. **Resolve the target.** If the session is not already in `target`, move there
   first (`change_directory`). In a git repo, note uncommitted changes and tell the
   user. The agent's edits must not mix into them.
2. **Launch leg 1 (Phases 1–2, read-only).** Use one `Agent` call with
   `subagent_type: general-purpose`, `model: opus` and `effort: high`. The prompt is
   the full text of `prompt.md` verbatim, followed by:
   ```
   # Run parameters
   - Target: <absolute target path>
   - Focus: <focus or "whole target">
   - Mode: <"Stop after Phase 2 and return the plan. Edit nothing." | "Auto-apply: run Phase 3 after Phase 2.">
   - Commits: <"Do not commit." | "Commit one cluster per commit on the current branch.">
   - Return the Phase 2 plan in full as your final report.
   ```
   The agent sees none of this conversation, so put every constraint into the parameters.
3. **Relay the plan.** Show the user the clusters (ID, tier, locations, proposed
   abstraction, risk, coverage, recommendation), the baseline, and what was not
   examined. Ask which cluster IDs to apply. If the plan has no cluster IDs or no
   baseline, send it back to the same agent to complete before relaying.
4. **Launch leg 2 (Phase 3) on approval.** In a git repo, propose a branch first
   and ask whether the agent may commit. Continue the *same* agent with `SendMessage`
   so it keeps its analysis: "Approved: C1, C3. Run Phase 3 for these only, in
   priority order. Commits: <answer>. Report each cluster's test, lint, type-check
   and detector output, and any cluster you reverted."
5. **Verify before reporting done.** The agent's report is not proof. Read the diff
   and confirm each changed file maps to an approved cluster. Then re-run the tests,
   lint and type-check yourself and compare against the leg-1 baseline. If a check
   regressed, send it back to the agent (step 4) and loop until it is clean, or
   revert that cluster. Report what changed, what was skipped or reverted, and each
   check's real output.

## Notes
- With `--apply`, step 2 runs all three phases. Steps 3–4 collapse into step 5,
  which still runs in full.
- To change what the agent does, edit `prompt.md`. Never paraphrase it into the
  launch prompt.
