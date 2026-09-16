---
name: anthill-release-tagging
description: "Tag and push AntHill commits following its strict one-annotated-tag-per-commit v1.0.0-beta.N convention. Use when asked to tag, release, or push AntHill work, especially after landing several commits at once."
---

AntHill (`D:/AntHill`, remote `git@git:alex.mollard/AntHill.git`) uses a convention that
is easy to break by tagging only the tip. Verify before naming anything.

## The convention

- **One annotated tag per commit.** Not one tag per batch. Tags run
  `v1.0.0-beta.N` with no gaps — `beta.63→343e04e`, `62→b736348`, `61→31dc2ae`
  were consecutive commits, each tagged.
- **Annotated, never lightweight** (`git tag -a`). `git cat-file -t <tag>` must print
  `tag`, not `commit`.
- **Tag message = that commit's subject line**, verbatim. Nothing else.
- So N commits to release ⇒ N tags, in commit order.

## Confirm before tagging

```bash
git remote -v
git status -sb                                  # ahead count = tags needed
git tag --sort=-creatordate | head -5           # highest N
git cat-file -t v1.0.0-beta.<N>                 # expect: tag
git tag -n20 -l v1.0.0-beta.<N>                 # expect: subject of its commit
git log --oneline -8 --decorate                 # confirm every prior commit tagged
```

Also check for a version source before assuming tags are cosmetic:

```bash
grep -rn "MinVer\|Nerdbank\|GitVersion" --include=*.csproj --include=*.props .
```

As of beta.67 there is **none** — version is not derived at build time, so tags are
consumed downstream (the client has `Updates/UpdateFeed.cs` + `ClientUpdates.cs`).
Pushing N tags may therefore trigger N releases. Say so before pushing a batch.

## Untagged ≠ unpushed (backfill trap)

`git status -sb` ahead count is **not** the number of commits needing tags. The
branch may have been pushed mid-session with no tags at all — 24 pushed commits
carried zero tags while `status` showed only 4 ahead. The real set needing tags is
**every commit after the highest tag's commit**:

```bash
git rev-parse v1.0.0-beta.<N>^{commit}          # where the tag chain currently ends
git log --oneline --decorate --reverse <that-sha>..HEAD   # every commit after it = tags to create
```

Do not stop at the unpushed tail — tagging only that would create the very gap the
convention forbids.

## Bulk-tagging (10+ commits)

Never transcribe subjects from rendered/compressed log output. Generate tags from
git itself in the eval kernel, subjects read straight from `%s`:

```js
const $ = Bun.$.cwd("D:/AntHill");
const list = await $`git log --reverse --format=%H%x09%s <lastTaggedSha>..HEAD`.quiet();
const rows = list.stdout.toString().trim().split("\n").map(l => {
  const i = l.indexOf("\t"); return [l.slice(0, i), l.slice(i + 1)];
});
let made = 0;
for (const [sha, subject] of rows) {
  const n = <startN> + made;
  const r = await $`git tag -a v1.0.0-beta.${n} ${sha} -m ${subject}`.nothrow().quiet();
  if (r.exitCode !== 0) { display(`FAILED beta.${n} ${sha}: ${r.stderr}`); break; }
  made++;
}
```

## Do it (small batches)

```bash
git tag -a v1.0.0-beta.64 <sha1> -m "<subject of sha1>"
git tag -a v1.0.0-beta.65 <sha2> -m "<subject of sha2>"
git log --oneline -6 --decorate            # each tag on its own commit
git push origin main
git push origin v1.0.0-beta.64 v1.0.0-beta.65
```

## Verify it landed

```bash
git status -sb                             # want "## main...origin/main", no ahead
git ls-remote --tags origin | grep -E "beta\.6[4-7]"
```

An annotated tag shows **two** remote lines — the tag object and a `^{}` deref to the
commit. Only the `^{}` line should match your commit SHA. A single line means the tag
went up lightweight and breaks convention.

Gap proof over a backfilled range:

```bash
git log --decorate=short --format=%h <lastTaggedSha>..HEAD
# lines total must equal lines containing "tag:" — equal means no gaps
```

## Push diagnostics

A push cell can throw even when the push landed (a later line in the cell fails, or
`.quiet()` hides stderr). "Everything up-to-date" on retry means the first push
succeeded — do not retry blind; verify with `git status -sb` and `ls-remote` counts
(expect 2 lines per tag: tag + `^{}`).

## Commit messages (same repo)

Imperative subject under ~72 chars, capitalized, no prefix/scope/emoji, no attribution.
Body only when the commit groups several changes: flat imperative bullets, one per
change, no sub-bullets. Write via `git commit -F <file>` — heredocs and inline `-m`
get mangled by `rtk`/bash `$` expansion.

## Traps

- `rtk` shadows git; keep using it, but write commit bodies to a temp file and delete it.
- Building while `AntHill.Web` or `AntHill.Client` is running fails with MSB3026/MSB3027
  or CS2012 — a **file lock, not a test failure**. Stop the process, rebuild.
- Untracked paths can dominate a commit. `git diff --stat` ignores them; always check
  `git status --short` for `??` and re-check the real size with `git diff --cached --stat`
  after staging. A `data/` dir here carried ~742 KB into history.
- Before committing work you did not write, run that project's test suite and attribute
  any failures. Errors naming `merge.rs:303` or "merge waiting to be committed in
  cricket26" are the stuck testbed merge, not the code under review.
