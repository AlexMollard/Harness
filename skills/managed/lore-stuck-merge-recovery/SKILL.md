---
name: lore-stuck-merge-recovery
description: "Clear a stuck or unrecoverable Lore merge in an AntHill workspace when resolve/abort/restart all fail with \"Invalid merge type\" at merge.rs:303, or when the client's conflict panel offers buttons that do nothing. Use when a workspace shows \"Changes in conflict\", \"merge waiting to be committed\", or when Lore integration tests fail on leftover fixture state."
---

# Recovering a stuck Lore merge

A workspace stuck in conflict has **two distinct causes** that look identical in the UI.
Diagnose first: the fixes are different and one is destructive.

## Diagnose

```bash
lore --repository <workspace> -P status
```

Read the header lines:

- `Pending merge, incoming revision <hash>` → **a real merge**. `branch merge abort`
  works. Go to "Real merge".
- No `Pending merge` line, but `Changes in conflict:` entries marked `!` →
  **corrupt merge state**. Go to "Corrupt merge state".

Confirm corruption cheaply — every merge-path command fails identically:

```bash
lore --repository <ws> -P branch merge resolve theirs --dry-run <path>
lore --repository <ws> -P branch merge abort
lore --repository <ws> -P branch merge restart <path>
```

All three returning this means the state blob is unreadable, not that you used
the wrong command:

```
[Error] Invalid merge type
  at lore-revision\src\branch\merge.rs:303:1
```

Note `status`, `history` and `revision info --metadata` still succeed — only the
merge record is unreadable. Do not conclude the repository is broken.

## Corrupt merge state

No merge command can clear it. `unstage` bypasses the merge state entirely and is
the way out. It is non-destructive: it unstages the entry and leaves working-tree
content alone.

**Back up first**, then unstage every conflicted path:

```bash
# 1. copy each conflicted + staged file somewhere outside the workspace
# 2. then, per conflicted path:
lore --repository <ws> -P unstage <path>
```

Rules:

- Use `unstage`, never `reset`. `reset` overwrites the working file with the
  repository version and **destroys local edits**.
- Unstage the remaining *staged* changes too. `WorkspaceOperations.StatusAsync`
  computes `merging` from `FlagMerged || FlagConflict || FlagStaged`, so any
  staged file keeps the client reporting "a merge waiting to be committed" and
  blocks fetches even after the conflicts are gone.
- The corrupt blob still exists afterwards; merge commands keep failing. That is
  fine — with nothing conflicted or staged, nothing calls them.

Verify: `status` shows only `Changes not staged for commit` / `Untracked files`,
with no `Changes in conflict` and no staged section.

## Real merge

```bash
lore --repository <ws> -P branch merge abort
```

Expect `Merge abort reverted changes` and exit 0.

## Test fixtures are separate workspaces

`AntHill.Lore.Tests` integration tests do **not** use the client's registered
workspace. Leftover state in a fixture directory (e.g. `branch-cricket26`,
`branch-main` beside `artist`) fails tests with:

```
There is a merge waiting to be committed in <branch>. Send it back first
```

Clear the *fixture* workspace, not the artist one. Some fixtures are built by the
tests themselves, so a residual failure after cleaning the on-disk fixtures is
likely pre-existing and not caused by your change — attribute before chasing.

## Gotchas

- The Lore server must be running or ~47 tests silently **skip**; a suite that
  reports "50 passed" may be testing half of what you think. Check the port
  before trusting any Lore test result.
- A running client or dashboard locks its own DLLs; builds then fail with
  MSB3026/MSB3027/CS2012. That is a lock, not a compile error — check for
  `error CS` before believing a non-zero exit.
