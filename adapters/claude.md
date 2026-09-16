# Harness dialect: Claude Code

- Skills live in `~/.claude/skills/`. Invoke one with the `Skill` tool:
  `Skill(skill: "<name>")`. Slash form: `/<name>`.
- `/graphify` → invoke the `Skill` tool with `skill: "graphify"` before anything else.
- Commands (`/pressure-test`, `/sidenote`, `/squash`) live in `~/.claude/commands/`.
- Memory: file-based, one fact per file, under the session's memory directory.
  Index each new memory with one line in `MEMORY.md`. The `mind` MCP protocol
  does not apply here.
- Subagents: use the `Agent` tool per section 8.
