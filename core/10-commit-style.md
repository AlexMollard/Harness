# Commit message style

Write commits concisely — plain subject, plain bullet body, no ceremony.

## Rules
- **Subject**: one line, imperative mood, capitalized, no trailing period. State the
  outcome, not the mechanics. Keep it under ~72 chars.
- **No prefixes**: never use `feat:`, `fix:`, `chore:`, scopes, tags, or emoji.
- **No attribution**: no `Co-Authored-By`, no tool/assistant mentions, no "Generated with".
- **Body only when it adds detail**: a single self-explanatory change needs no body.
  When several related changes are grouped/squashed together, add a body.
- **Body = flat bullet list**: each bullet is one imperative phrase describing one change
  ("- Move crash bundle uploads outside the WER callback"). No sub-bullets, no paragraphs,
  no restating the subject.
- **Group by theme, not by file**. One commit = one coherent unit of work.

## Good examples
    Simplify crash helpers and remove dead code

    - Simplify crash signature construction and text helpers
    - Remove unused crash text abstractions, debugger launcher, and utility exports
    - Remove the redundant signature builder

    Migrate crash subsystems to C++ modules

    - Migrate crash bundle, logs, text utilities, and diagnostics to modules
    - Split each subsystem into a dedicated module interface

## Avoid
- `fix: resolved the bug where the thing broke (#1234)`
- Walls of prose explaining rationale that belongs in a PR description or code comment.
- Bullets that just narrate the diff line by line.

<!-- greybeard:start -->
