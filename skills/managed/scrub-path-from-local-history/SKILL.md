---
name: scrub-path-from-local-history
description: "Remove a file or directory from unpushed local commits so it never appears in history, by rebuilding the branch with cherry-picks and verifying with patch/message/tree scans"
---

# Scrub a path from local history

Use when work committed locally (not pushed, or pushed only to a personal branch) added something that should never have existed - a spike, an orphaned tool, a leaked file - and the ask is "make it look like it never existed" rather than "delete it going forward".

Safe only for **unpushed or personally-owned** branches. A shared branch needs the team's agreement first, because everyone building on it must reset.

## 1. Map the footprint before touching anything

```bash
git branch backup/with-<thing> HEAD          # always, first
git log --reverse --format="%h %s" <base>..HEAD
```

For each commit, find three kinds of trace - files, message text, and prose in docs/comments:

```bash
for c in $(git rev-list --reverse <base>..HEAD); do
  files=$(git show --stat --format="" $c -- <PATH> | grep -c . )
  msg=$(git show --format="%s%n%b" --no-patch $c | grep -ci "<name>")
  docs=$(git show --format="" $c -- docs .docs | grep -ci "<name>")
  echo "$c files=$files msg=$msg docs=$docs"
done
```

Docs and commit messages are the traces people forget; a scrub that only removes files still reads as a cover-up in `git log`.

## 2. Rebuild by cherry-pick

Prefer this over `filter-branch`/`filter-repo` for a short branch: every commit is inspected, and message rewording comes free.

```bash
git reset --hard <base>
git cherry-pick <clean commits>              # ones with no trace, in original order
```

For each commit that touches the artifact:

```bash
git cherry-pick -n <sha>                     # stage without committing
git rm -r -q --cached <PATH>                 # drop the files from the index
rm -rf <PATH>                                # and from the working tree
# edit docs/comments that name it, then:
git commit -F - <<'MSG'
<original subject>

<original bullets minus the ones about the artifact>
MSG
```

Two cases worth expecting:

- **A commit that only modified the artifact** (e.g. a comment fix): its cherry-pick conflicts as `DU`. Resolve with `git rm --cached <file>` and keep the commit for its other changes, or skip it if nothing else remains.
- **The commit that deleted the artifact**: its deletions are now moot, but it usually carries unrelated edits worth keeping. Cherry-pick `-n`, drop the deletions, reword the subject to describe only what survives.

## 3. Verify - three zeros and a parity diff

```bash
git log -p <base>..HEAD | grep -ic "<name>"        # patches
git log --format="%s%n%b" <base>..HEAD | grep -ic "<name>"   # messages
git ls-tree -r --name-only HEAD | grep -ci "<name>"          # final tree
git diff --stat backup/with-<thing> HEAD                     # content parity
```

All three counts must be 0. The parity diff should show **only** the lines you intended to remove - anything else means a cherry-pick dropped a hunk.

Grep patterns lie: search for a distinctive substring, not a full sentence, because markdown emphasis (`**word**`) and reflowed lines break literal matches. A "0 matches" that surprises you is usually a bad pattern, not lost content - confirm before acting on it.

## 4. Build, then push

Rewriting can leave a tree that differs subtly from what was last tested. Build every affected project again, then:

```bash
git push --force-with-lease
```

`--force-with-lease`, never `--force`: it refuses if someone else pushed to the branch meanwhile.

## Keep the backups

Leave `backup/*` branches until the push is confirmed and the user is happy. They cost nothing and are the only way back.
