# Harness dialect: Codex

- This section is inlined by `~/agent-core/build.ps1` into the effective global
  `AGENTS.md` (or `AGENTS.override.md`) under `CODEX_HOME`, default `~/.codex`.
  Rerun the build after changing shared rules. Preserve instructions outside its markers.
- Shared skills are linked individually under `~/.agents/skills/`; read a matching
  `SKILL.md` when needed. The catalogue exposes the on-demand skills without indexing
  every skill. Existing user skills and Codex's system skills stay in place.
- Use the available shell and patch tools. Claude's `Skill`, `Agent`, slash commands
  and tool names are not Codex APIs. Use Codex subagent tools only when available;
  choose from this session's model list and map effort to its supported levels.
- Follow the active Codex sandbox, approval policy and higher-priority instructions.
  The Claude/Hermes shell hooks are not installed as Codex hooks by this adapter:
  the billing and line-ending rules below are instructions here, not hook enforcement.
- Keep existing MCP servers, memory protocols, credentials and `config.toml` settings.
  When Axiom is installed, use its existing scoped memory integration.
