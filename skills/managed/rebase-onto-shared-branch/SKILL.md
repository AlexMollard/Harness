---
name: rebase-onto-shared-branch
description: "Safely rebase local commits onto a shared/team branch after someone else pushed overlapping work - predict conflicts, resolve keeping both sides, and prove the merged code at runtime rather than by build alone."
---

# Rebase onto a shared branch that moved underneath you

Use when a teammate pushed to the integration branch and your local commits touch nearby code. The goal is not a clean rebase - it is a *correct* one, proven by running the merged code.

## 1. See what actually landed, before touching anything

```bash
git fetch --all --prune
git log --oneline origin/<integration> ^HEAD | head -30   # what they added
git log --oneline HEAD ^origin/<integration>              # what you owe
```

For any commit that sounds like it overlaps your project, read the **diffstat and the diff**, not the subject line. A subject like "containerise X so a cluster can scale it" can turn out to be 49 additive lines that touch none of your files - or a genuine parallel implementation. Decide which from the diff.

## 2. Predict conflicts with set intersection, never with a log-count loop

Wrapped git (rtk, aliases, anything that decorates output) breaks `| wc -l` counting: every file appears to have >=1 commit, including files that only exist locally. Compute the overlap directly:

```python
ours   = set(sh('git diff --name-only origin/<integration>...HEAD').split())
theirs = set(sh('git diff --name-only HEAD...origin/<integration>').split())
print(sorted(ours & theirs))   # the only files that can conflict
```

Sanity check the result: a file you created this session appearing in the overlap means the detection is wrong, not that they invented the same file.

## 3. Safety net, then rebase

```bash
git branch backup/<name>-preRebase HEAD
git rebase origin/<integration>
```

Unstaged noise blocks the rebase. Before discarding it, check what it is: a file showing as modified with an *empty* diff is line-ending churn (`git stash push` on it reports `Empty stash`), not your edit.

## 4. Resolve by intent, keeping both sides where they are additive

During a rebase, `HEAD`/"ours" is **upstream** and "theirs" is **your commit** - the reverse of what people expect. Read both sides' comments to learn what each protects. A guard upstream added (`InTransaction ? null : ...`) plus a change you made (log level, message) are usually *both* wanted; taking either side wholesale silently reverts the other's fix.

After resolving, re-read the merged region in the file to confirm both intents survived.

## 5. Prove it, don't just build it

A clean rebase proves textual merge only. Build every project that touches the conflicted files, then exercise the merged path for real:

- Rebuild the running service (Aspire `rebuild` resource command, or restart the host).
- Drive traffic that hits the specific merged branch - for a DAL conflict-handling path, a load run that produces conflicts; assert zero failures rather than "it started".
- If the teammate's work has its own build path (a Dockerfile, another RID), verify **your** change still satisfies it: e.g. `dotnet publish -r linux-x64` when they containerised a project you added a Windows-only package to.

## 6. Report before pushing

State: base commit, commits replayed, conflicts and how each was resolved, every build result, the runtime evidence, and the backup branch name. Flag documentation drift where two docs now describe the same capability differently - that is how one of them gets deleted later by someone who only read the other.
