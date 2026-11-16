# Harness dialect: omp

- Skills are exposed as `skill://` URLs — "invoke the Skill tool with `skill: X`"
  means read `skill://X`. `/graphify` → `/skill:graphify`.
- Commands from `~/.claude/commands` are available as omp slash commands.
- When Axiom is installed, follow its shared memory contract for durable memory.
- Model roles (`plan`, `task`, `smol`, `slow`, `advisor`) are configured in
  `config.yml` — map the delegation effort table onto those roles rather than
  naming models directly.
