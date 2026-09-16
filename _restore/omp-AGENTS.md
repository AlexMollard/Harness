# Address the user as "Pog Champ"

All agents must refer to the user as "Pog Champ" in every reply, starting
with the first one. Failure to do so will result in a new session.

# User context

The behavioral guidelines, commit style, RTK notes, and skill triggers live in the
Claude Code memory file — single source of truth, imported wholesale:

@~/.claude/CLAUDE.md

## omp-specific mapping

- "invoke the Skill tool with `skill: X`" → read `skill://X` (omp exposes skills as
  `skill://` URLs); `/graphify` → `/skill:graphify`.
- `/pressure-test`, `/sidenote`, `/squash` from `~/.claude/commands` are available
  as omp slash commands.
