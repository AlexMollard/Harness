# Harness dialect: omp

- Skills are exposed as `skill://` URLs — "invoke the Skill tool with `skill: X`"
  means read `skill://X`. `/graphify` → `/skill:graphify`.
- Commands from `~/.claude/commands` are available as omp slash commands.
- Memory backend is `sharpshooter` (see `~/.omp/agent/config.yml`).
- Model roles (`plan`, `task`, `smol`, `slow`, `advisor`) are configured in
  `config.yml` — map section 8's effort table onto those roles rather than naming
  models directly.
