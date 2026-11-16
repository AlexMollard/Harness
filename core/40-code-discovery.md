# Code discovery: graphify

When `graphify-out/graph.json` exists, answer codebase questions with
`graphify query "<question>"` first; use `graphify path "<A>" "<B>"` for
relationships and `graphify explain "<concept>"` for one concept. They return a
scoped subgraph, far smaller than grep or `GRAPH_REPORT.md`.

- Dirty `graphify-out/` files after hooks are expected, not a reason to skip it.
  Skip it only when the task is about the graph being wrong, or Alex says so.
- `graphify-out/wiki/index.md`, when present, is the map for broad navigation.
  Read `GRAPH_REPORT.md` only for architecture review.
- After modifying code, run `graphify update .` (AST-only, free).
