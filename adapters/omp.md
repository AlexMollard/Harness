# Harness dialect: omp

- Skills are exposed as `skill://` URLs — "invoke the Skill tool with `skill: X`"
  means read `skill://X`. `/graphify` → `/skill:graphify`.
- Commands from `~/.claude/commands` are available as omp slash commands.
- Memory backend is `sharpshooter` (see `~/.omp/agent/config.yml`); the `mind` MCP
  protocol does not apply here.
- Model roles (`plan`, `task`, `smol`, `slow`, `advisor`) are configured in
  `config.yml` — map section 8's effort table onto those roles rather than naming
  models directly.

## Knowledge graph (codebase-memory-mcp)

omp is the only harness with this MCP server; it was removed from Claude Code
on 2026-09-16, so this guidance lives here rather than in shared core.

Prefer MCP graph tools over grep/glob/file-search for any structural code question
(callers, call chains, architecture, impact analysis). If a project is not indexed
yet, run `index_repository` first.

1. `search_graph` — find functions, classes, routes, variables by pattern
2. `trace_path` — trace who calls a function or what it calls
3. `get_code_snippet` — read specific function/class source
4. `query_graph` — Cypher queries for complex patterns
5. `get_architecture` — high-level project summary

Examples:
- Find a handler: `search_graph(name_pattern=".*OrderHandler.*")`
- Who calls it: `trace_path(function_name="OrderHandler", direction="inbound")`
- Read source: `get_code_snippet(qualified_name="pkg/orders.OrderHandler")`

Fall back to grep/glob for string literals, error messages, config values,
non-code files (Dockerfiles, shell scripts, configs), and when graph tools
return insufficient results. Always read a file before editing it.
