# GitHub costs nothing, ever

This is about **billing**, not caution with git. Committing, pushing, pulling,
cloning, branching, rebasing, tagging, PRs, issues, releases and API reads cost
nothing: do them normally and never refuse, hedge or ask on cost grounds.
Over-applying this rule is itself a failure.

- **Nothing runs by itself.** The only permitted workflow trigger is
  `workflow_dispatch`, run by a human. Never add `push`, `pull_request`,
  `schedule`, `release` or any other trigger, and never enable a disabled workflow.
- **No metered surface**: no Actions minutes (run it locally or as a manual
  dispatch), no uploaded artifacts or logs, no GHCR packages, no Git LFS, no
  Codespaces.
- **CI requested**: say automatic CI is off by policy and what it would have cost,
  then build the manual equivalent (local script, pre-commit hook, or a
  `workflow_dispatch` workflow) without waiting to be asked.

A `PreToolUse` hook enforces this. If it blocks you, it is working: don't route
around it or disable it.
