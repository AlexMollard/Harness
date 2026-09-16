# agent-core

One instruction set, two harnesses: **Claude Code** and **omp**.

Before this, the same "Coding-Agent Guidelines" body existed in three hand-maintained
copies and had already drifted — Codex was missing section 8 and the entire Gatekeeper,
and its file had collapsed markdown and a dead `@RTK.md` import. Nothing was under
version control. omp was the only harness doing it right: a thin file of harness
dialect that *imported* the shared body. This repo generalises omp's pattern.

## Layout

```
core/        harness-neutral. The actual rules. Edit these.
adapters/    per-harness dialect only (how skills are invoked, which memory backend).
manifest.psd1  which core files each harness loads. Composition lives here, nowhere else.
commands/    pooled slash commands, junctioned into each harness.
skills/
  global/    general skills, junctioned into each harness - indexed everywhere.
  catalogue.md  generated index of all 116 skills (see "Skill tiering").
build.ps1      wires the harnesses. verify.ps1 proves they actually load it.
_restore/      verbatim copies of every file as it was before unification.
```

## How each harness consumes it

Deliberately different, because using each host's own primitive beats a generator
we maintain:

| Harness | Mechanism | Why |
|---|---|---|
| Claude Code | `@~/agent-core/...` import stub | native imports, verified transitive |
| omp | `@~/agent-core/...` import stub | native imports, verified 2 hops deep |

Both harnesses read `core/` directly through native `@` imports, so **nothing is generated** - there is no second copy that can drift.
is generated** - there is no second copy that can drift.

Codex and opencode were both supported and then removed (2026-09-16) - along with
Hermes, they are no longer installed on this machine. Their adapters and the
mind-memory protocol they used are in git history if ever needed.

## Skill tiering

The skill *index* (every skill's name + description) is injected into every session;
skill *bodies* cost nothing until invoked. The 106 project-specific skills carry
**40,066 characters of description** — roughly 10k tokens per session — so fanning
them into every harness was not affordable.

So: the 10 general skills are junctioned everywhere and indexed normally. The other
106 stay where omp's autolearn writes them and are reachable from every harness
through a single index entry, `skill-catalogue`, costing **343 characters**.

All 116 reachable from all three harnesses; per-session index cost went *down*.

## Usage

```powershell
./build.ps1 -WhatIf      # preview instruction changes
./build.ps1              # wire the harnesses
./sync-skills.ps1 -Link  # pool + link skills and commands
./verify.ps1 -Static     # check wiring on disk (fast, free)
./verify.ps1             # probe each live harness for core-only facts
```

Re-run `sync-skills.ps1` after omp autolearn writes new skills, to refresh the catalogue.

### Adding a rule

Edit the file in `core/`. All three harnesses pick it up at their next session start -
there is no build step for a rule change.

### Undo

```powershell
./sync-skills.ps1 -Unlink        # restores each harness's own skills/commands dir
git -C ~/agent-core show 038dda0 # every original file, verbatim
```

`-Unlink` removes only the junction; the pool is untouched. Nothing in this repo
ever deletes a file — superseded dirs are renamed to `<dir>.preunify`.

## Verification

`verify.ps1` asks each live harness three questions whose answers appear only inside
`core/` (the name of Gate 2, the title of section 8, what RTK stands for). A harness
that failed to resolve its import answers MISSING. That is the check that catches
drift returning — run it after every build.

Both harnesses **pass live** at last run.
