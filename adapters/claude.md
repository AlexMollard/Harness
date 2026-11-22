# Harness dialect: Claude Code

- Skills live in `~/.claude/skills/`. Invoke one with the `Skill` tool:
  `Skill(skill: "<name>")`. Slash form: `/<name>`.
- Commands (`/pressure-test`, `/sidenote`, `/squash`) live in `~/.claude/commands/`.
- When Axiom is installed, follow its shared memory contract for durable memory.
- Subagents: the `Agent` tool, per the delegation section — `Explore` for sweeps,
  `general-purpose` for research or self-contained implementation, `Plan` for
  structure questions.
