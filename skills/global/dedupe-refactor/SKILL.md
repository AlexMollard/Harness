---
name: dedupe-refactor
description: Launches a refactoring agent that finds duplicated or ad hoc logic in a codebase using a clone detector and git churn, ranks clusters by impact, proposes a consolidation plan, and applies only the clusters the user approves, with tests pinned first. Use when the user says "dedupe this repo", "find duplicated code", "consolidate the ad hoc logic", or runs /dedupe-refactor.
argument-hint: "[target-path] [focus] [--apply]"
---

# Dedupe refactor

Hands the brief in [prompt.md](prompt.md) to a subagent in two legs, analysis then
edits, with the user's approval between them. Arguments: `$ARGUMENTS` (if that
shows literally, take the arguments from the user's message).

Works in any harness that can launch a subagent. Each leg is a fresh subagent; the
plan file carries leg 1's findings into leg 2, so no harness needs to resume a
finished agent.

## Inputs
- `target` — repo or folder to analyse. Default: the current working directory.
- `focus` — optional narrowing (a subfolder, module or priority tier). Default: whole target.
- `--apply` — auto-apply. Only when the user typed it or said so in words. Default: stop at the plan.

## Checklist
Copy this and tick it off as you go:
```
- [ ] 1. Target resolved, git state checked
- [ ] 2. Leg 1 (analysis) returned a plan with cluster IDs and a baseline; plan saved
- [ ] 3. Plan relayed, approved cluster IDs recorded
- [ ] 4. Branch agreed, leg 2 (edits) finished
- [ ] 5. Diff read and checks re-run here
```

## Subagent settings
Launch each leg with the harness's subagent tool, a general-purpose agent and the
strongest planning model it offers:
- **Claude Code**: `Agent` tool, `subagent_type: general-purpose`, `model: opus`, `effort: high`.
- **omp**: `task` tool, using the `plan` model role (not a model name).

## Procedure
1. **Resolve the target.** Work from `target` as the working directory (in the
   Claude desktop app, move the session there first). In a git repo, note any
   uncommitted changes and tell the user. The agent's edits must not mix into them.
2. **Launch leg 1 (Phases 1–2, read-only).** The prompt is the full text of
   `prompt.md` verbatim, followed by:
   ```
   # Run parameters
   - Target: <absolute target path>
   - Focus: <focus or "whole target">
   - Mode: <"Stop after Phase 2 and return the plan. Edit nothing." | "Auto-apply: run Phase 3 after Phase 2.">
   - Commits: <"Do not commit." | "Commit one cluster per commit on the current branch.">
   - Return the Phase 2 plan in full as your final report.
   ```
   The agent sees none of this conversation, so put every constraint into the parameters.
3. **Save and relay the plan.** If the plan has no cluster IDs or no baseline, launch
   leg 1 again with that gap named. Save the report verbatim yourself (subagents may
   not be able to write files) to `dedupe-plan.md` in the session's temp or scratch
   directory, not inside `target`. Show the user the clusters (ID, tier, locations,
   proposed abstraction, risk, coverage, recommendation), the baseline, and what was
   not examined. Ask which cluster IDs to apply.
4. **Launch leg 2 (Phase 3) on approval.** In a git repo, propose a branch first and
   ask whether the agent may commit. Launch a fresh subagent with the same settings.
   Its prompt is the full text of `prompt.md` verbatim, then the saved plan verbatim,
   then:
   ```
   # Run parameters
   - Target: <absolute target path>
   - Mode: Phase 2 is done; the approved plan is above. Run Phase 3 only, for clusters <C1, C3>, in priority order. Before editing a cluster, re-read its locations and stop on that cluster if the code no longer matches the plan.
   - Commits: <answer>
   - Report each cluster's test, lint, type-check and detector output, and any cluster you reverted.
   ```
5. **Verify before reporting done.** The agent's report is not proof. Read the diff
   and confirm each changed file maps to an approved cluster. Then re-run the tests,
   lint and type-check yourself and compare against the plan's baseline. If a check
   regressed, launch leg 2 again for that cluster with the failure output added, or
   revert that cluster. Report what changed, what was skipped or reverted, and each
   check's real output.

## Notes
- With `--apply`, step 2 runs all three phases. Steps 3–4 collapse into step 5,
  which still runs in full.
- To change what the agent does, edit `prompt.md`. Never paraphrase it into the
  launch prompt.
