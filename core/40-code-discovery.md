# Code discovery

## Knowledge graph first (codebase-memory-mcp)

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

## graphify

`graphify` turns any input into a persistent knowledge graph. Trigger: `/graphify`.

- For codebase questions, run `graphify query "<question>"` first when
  `graphify-out/graph.json` exists. Use `graphify path "<A>" "<B>"` for
  relationships and `graphify explain "<concept>"` for focused concepts. These
  return a scoped subgraph, usually much smaller than `GRAPH_REPORT.md` or raw grep.
- Dirty `graphify-out/` files after hooks or incremental updates are expected and
  are not a reason to skip graphify. Only skip it if the task is about stale or
  incorrect graph output, or the user says not to use it.
- If `graphify-out/wiki/index.md` exists, use it for broad navigation instead of
  raw source browsing.
- Read `graphify-out/GRAPH_REPORT.md` only for broad architecture review, or when
  query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current
  (AST-only, no API cost).
