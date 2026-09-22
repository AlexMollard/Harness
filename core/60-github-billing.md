# GitHub costs nothing, ever

This account runs at zero GitHub spend. Every metered surface stays unused.

## Never create anything that runs by itself

No workflow may trigger automatically — no `push`, `pull_request`, `schedule`,
`release`, `repository_dispatch`, or any other event. The only permitted trigger is
`workflow_dispatch`, run deliberately by a human.

Never enable a disabled workflow, and never add a trigger to an existing one.

## Never use a metered surface

| Surface | Instead |
|---|---|
| Actions minutes | Run it locally, or a `workflow_dispatch` job you start yourself |
| Artifacts / logs storage | Keep build output local; don't upload |
| Packages (GHCR) | A local registry, or a non-billing host |
| Git LFS | Keep large files out of git, or store them elsewhere |
| Codespaces | Local checkout |

## When CI is asked for

Say plainly that automatic CI is off by policy and what it would have cost, then offer
the manual equivalent: a local script, a pre-commit hook, or a `workflow_dispatch`
workflow. Build that instead — don't stall waiting for permission to do the obvious.

A `PreToolUse` hook enforces this independently, because an instruction is context and
this needs to be a guarantee. If the hook blocks you, it is working: do not try to
route around it, and do not disable it to complete a task.
