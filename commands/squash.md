---
description: Squash commits from a given commit to HEAD into clean thematic commits
argument-hint: <START_COMMIT>
---

# Task: Squash history from `$ARGUMENTS` to HEAD

Squash all commits from `$ARGUMENTS` (exclusive) to HEAD into a small number of clean,
thematic commits. `$ARGUMENTS` itself is the base and must stay untouched.

If `$ARGUMENTS` is empty, ask me for the start commit before doing anything.

## Method — use `commit-tree`, not interactive rebase
This must be conflict-free and content-preserving. Do NOT reorder commits or run
`rebase -i`. Rebuild new commits whose trees exactly match existing group boundaries.

## Steps
1. **Verify state**: confirm current branch, that the tree is clean
   (`git status --porcelain` empty), and that `$ARGUMENTS` is the parent of the oldest
   commit in range (`git rev-parse $ARGUMENTS` == `git rev-parse <oldest>^`). If the
   tree is dirty, stop and tell me.
2. **Inspect**: `git log --format='%h|%ad|%s' --date=short $ARGUMENTS..HEAD` to read
   every commit. Understand the changes well enough to group them.
3. **Group by theme**, in chronological order, using **contiguous runs only** (never
   reorder). One group = one coherent unit of work. Aim for the smallest number of
   groups that still reads clearly. Show me the proposed grouping + messages and get a
   yes before rewriting history.
4. **Backup**: `git tag pre-squash-backup HEAD`.
5. **Rebuild** with `git commit-tree <group_tip>^{tree} -p <prev> -m "subject" -m "body"`,
   chaining each new commit onto the previous. Each group's tree = the tree of that
   group's last (newest) commit.
6. **Verify identical content**: `git diff --stat pre-squash-backup <new_tip>` MUST be
   empty. If it isn't, stop — do not move the branch.
7. **Move the branch**: `git reset --hard <new_tip>`, then show the new
   `git log --format='%h %s' $ARGUMENTS..HEAD`.

## Commit messages
Follow my global commit style: imperative subject, no prefixes/tags/emoji, no
attribution or `Co-Authored-By`, flat bullet body only when a group bundles several
changes. Group by theme, not by file.

## Rules
- **Do not push.** History was rewritten; leave the force-push decision to me.
- Author/committer must stay as the repo's configured git identity — add nothing about
  yourself.
- Leave the `pre-squash-backup` tag in place and tell me the undo command
  (`git reset --hard pre-squash-backup`) and how to delete the tag when I'm happy.
