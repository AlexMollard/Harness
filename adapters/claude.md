# Harness dialect: Claude Code

- Skills live in `~/.claude/skills/`. Invoke one with the `Skill` tool:
  `Skill(skill: "<name>")`. Slash form: `/<name>`.
- `/graphify` → invoke the `Skill` tool with `skill: "graphify"` before anything else.
- Commands (`/pressure-test`, `/sidenote`, `/squash`) live in `~/.claude/commands/`.
- When Axiom is installed, follow its shared memory contract for durable memory.
- Subagents: use the `Agent` tool per section 8.
