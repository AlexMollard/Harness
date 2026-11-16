# Commit message style

- **Subject**: one line, imperative mood, capitalized, no trailing period, under
  ~72 chars. State the outcome, not the mechanics.
- **No prefixes** (`feat:`, `fix:`, scopes, tags, emoji) and **no attribution**
  (`Co-Authored-By`, tool or assistant mentions, "Generated with").
- **Body only when it adds detail**, e.g. when several related changes are grouped.
  It is a flat list of imperative bullets, one change each: no sub-bullets,
  paragraphs, or narrating the diff line by line.
- **Group by theme, not by file.** One commit is one coherent unit of work.

Example:

    Simplify crash helpers and remove dead code

    - Simplify crash signature construction and text helpers
    - Remove unused crash text abstractions, debugger launcher, and utility exports
