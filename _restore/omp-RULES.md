# Sticky rules

- Commit messages: imperative subject under ~72 chars, no prefixes/tags/emoji, no
  attribution or `Co-Authored-By`; body = flat imperative bullets, only when a
  commit groups several changes.
- Structural code questions (callers, call chains, architecture, impact analysis):
  use codebase-memory-mcp graph tools first (`search_graph`, `trace_path`,
  `get_code_snippet`, `get_architecture`); grep is for text, configs, and pins.
- Ground facts in primary sources (official docs, real code) instead of
  training-data recall; when a docs tool is available (context7), use it rather
  than remembering an API.
