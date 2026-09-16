---
name: rebase-branch-without-checkout
description: "Rebase a git branch onto another branch WITHOUT switching the current checkout, using a temporary sparse worktree — plus the traps in the handball1/Windows environment (git replay fails silently, sort's TMPDIR, 30-min cold checkouts, reverse-apply false positives). Use when asked to update/rebase a branch you are not on, or when a full checkout would be too slow to build."
---

# Rebase a branch you are not on

Goal: branch ref ends up replayed on top of the target, while the caller's working
tree stays exactly where it was. Complements `rebase-onto-shared-branch`
(which covers conflict *intent*); this one covers *mechanics* and environment traps.

## 1. Do not reach for `git replay`

`git replay --onto <base> <base>..<branch>` looks perfect (no worktree, prints
`update-ref` lines) but on any conflict it exits **1 with no output at all** —
silent, in under a second, indistinguishable from "nothing to do". Try it once at
most; on exit 1 go straight to the worktree path. Never pipe it through `tee`/`tail`
and read "ok" as success — that `ok` is a wrapper's (rtk's) own output.

## 2. Sparse temporary worktree

```bash
git branch backup/<name>-preRebase <branch>          # safety net first
git worktree add --no-checkout /path/wt <branch>
cd /path/wt
git sparse-checkout set <dirs containing the overlap files>
git checkout
git rebase <target>
```

Sparse is what makes this cheap: on a 95k-file / 1.4 GiB repo the sparse checkout is
~1 second, a **full checkout took >30 minutes and timed out**. Rebase still replays
commits touching files outside the sparse set — git updates those index entries
without materialising them. Conflicted files are materialised automatically.

Afterwards: `git worktree remove --force /path/wt` (seconds when sparse), then
`git worktree prune`. The branch ref keeps the rebase; only the checkout is discarded.

## 3. Predict the overlap first

Only files changed on *both* sides can conflict:

```bash
comm -12 <(git diff --name-only <target>...<branch> | sort) \
         <(git diff --name-only <branch>...<target> | sort)
```

Windows trap: `sort` pins its temp dir to `G:/tmp` (nonexistent) regardless of
`$TEMP`; prefix with `TMPDIR=<existing dir>` or intersect in python instead.
`/tmp` does not resolve — write scratch files into a repo-local dir you delete after.

## 4. Non-interactive amend of a mid-rebase commit

```bash
GIT_SEQUENCE_EDITOR="sed -i 's/^pick <sha>/edit <sha>/'" GIT_EDITOR=true git rebase -i <base>
# edit files
git add -A && GIT_EDITOR=true git commit --amend --no-edit
GIT_EDITOR=true git rebase --continue
```

Only worth it for real defects — replaying 30 commits to restore a blank line is not.

## 5. Prove the replay, per hunk

1. `git range-diff <oldbase>..<backup> <newbase>..<branch>` — expect `=` on every
   commit except the ones you resolved. A missing or `!`-marked commit you did not
   touch is a dropped/altered commit.
2. `git merge-base <target> <branch>` == `git rev-parse <target>`, and
   `git rev-list --count <branch>..<target>` == 0.
3. Removals audit — for each overlap file, list only `-` lines of
   `git diff <target> <branch> -- <file>`. Every removed upstream line must trace to
   a *deliberate* branch edit: prove it with `git log -S<symbol> <target> ^<mergebase>`
   (empty ⇒ upstream never touched it since the base, so the branch owns the removal)
   and `git merge-base --is-ancestor <adding-commit> <mergebase>`.
4. Upstream-hunk survival — for each target commit landed after the base that touched
   an overlap file: `git diff C^ C -- <files> | git apply --reverse --check`.
   **A failure here is usually a false positive**: the branch edited nearby lines, so
   context drifted. Confirm by grepping the rebased file for the commit's added lines
   before claiming anything was lost.
5. Stranded references — if the branch deleted a subsystem, grep the *rebased tree*
   for its symbols (`git grep -n <symbol> <branch> -- src`) to prove no upstream
   caller now dangles, and that any upstream consumer still has its producer.
6. `git grep -c -e '^<<<<<<< ' --or -e '^>>>>>>> ' <branch> -- src` ⇒ no markers.
7. Generated project files (`.vcxproj`): parse the XML and assert no duplicate
   `Include=` values — auto-merge duplicates entries silently.

## 6. Know when to stop short of a build

A compile is the only proof of a C++ merge, but if the cold checkout alone exceeds
the timeout, the build path is disproven, not merely slow. Report
"textually verified, not compile-verified" with the evidence above rather than
fixing someone else's build environment for a rebase request.

## 7. Report

Base commit, new tip vs backup tip, commits replayed, each conflict and why the
resolution keeps both intents, the per-hunk survival results, what was *not* verified,
and the remote divergence (a rebased branch needs `--force-with-lease`; never push
unasked).
