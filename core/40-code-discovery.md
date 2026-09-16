# Code discovery

## graphify

How to use `graphify` when a project already has a graph. Invoking it is handled
by the `graphify` skill's own trigger - not repeated here, so the two do not collide.

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
