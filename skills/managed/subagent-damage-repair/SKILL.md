---
name: subagent-damage-repair
description: "Repair the recurring subagent damage pattern: silently dropped imports/parameters/functions after parallel task-agent edits in a Kotlin/Compose repo, with KSP MissingType masking the real error. Use when an agent batch lands green-in-report but the build fails, or when an opaque KSP MissingType appears on the @Database class."
---

# Subagent damage repair (Kotlin/Compose/Room)

Recurring pattern: parallel task agents edit a module, report success, and the build fails — or worse, compiles with silent visual/behavioural loss. The agents' self-reports are never sufficient; the gate plus HEAD-diff is the enforcement.

## Failure modes seen (all real, all more than once)
1. **Dropped imports** — an agent rewrites a file's import block and loses 30+ lines. KSP reports one opaque `e: [ksp] [MissingType]: Element '…MonarchDatabase' references a type that is not present` instead of the true error.
2. **Dropped parameters** — appending a new parameter to a function and silently deleting an existing one (`trailing` from `IdentityRow`, `name` from `Achievement`, `gold = true` from a button). Compiles clean when the new param has a default; the UI just loses a feature.
3. **Overwritten declarations** — an inserted `abstract fun gachaDao()` replacing the neighbouring `profileDao()` line.
4. **Deleted scaffolding** — `fun create()` / `Room.databaseBuilder(...)` vanishing, leaving `.addMigrations(` dangling; defined-but-never-registered migrations.
5. **Unclosed blocks** — auto-repaired edits leaving try/while loops unclosed, nesting later top-level functions inside them (callers then report "Unresolved reference" on the nested names).
6. **Contract mismatches between sibling agents** — one declares `Flow<Int?>`, the consumer calls `.rolls` on it; or a shared helper is referenced but never created.

## Diagnosis procedure
1. **Gate everything at once, after all agents settle.** Never trust per-agent "compiles" claims — agents are told not to build, and mid-flight builds measure half-done siblings.
2. **KSP MissingType on the @Database class = a resolution failure somewhere in the module**, not necessarily in that file. KSP swallows the real Kotlin error.
3. **Import-diff probe (fastest, finds mode 1):**
   ```
   git show HEAD:<file> | grep "^import" | sort > head.txt
   grep "^import" <file> | sort > now.txt
   comm -23 head.txt now.txt
   ```
   Restore the union (keep the agent's new imports too). Then add any import the new code needs that HEAD lacked.
4. **Function-diff probe (finds modes 2/4/5):**
   ```
   git show HEAD:<file> | python -c "import sys,re; print(sorted(set(re.findall(r'fun (\w+)', sys.stdin.read()))))"
   ```
   vs the same for the current file. Missing helpers = restore from HEAD.
5. **Brace-balance probe (finds mode 5):** `python -c "t=open(f).read(); print(t.count('{')-t.count('}'))"` per touched file. Non-zero = an unclosed block; trace with a depth-walk printing depth at each `fun` line.
6. **Grep for the silent-parameter drop:** after any signature change, grep all call sites for the old parameter names and for now-unused locals (a dead `val accent` left behind is a tell).
7. Verify visual constants against `git show HEAD:…` when you repaired by hand — reconstructing a modifier chain from memory produced `shapes.extraSmall`/`padding(10,8)` where HEAD had `shapes.small`/`padding(12)`.

## Repair rules
- Restore imports as the sorted union of HEAD + current (never cherry-pick; you will miss one).
- If a file is badly mangled, **reconstruct from `git show HEAD:` and re-apply only the intended changes** — incremental repair of a scrambled region takes longer and risks leftovers.
- After repair, verify the final diff contains ONLY intended changes (`git diff --stat` + read the hunks).
- Then run the single full gate (`assembleDebug` + unit tests) and report the agent defects honestly — they are findings, not shame.

## Prevention (in dispatch briefs)
- Forbid builds/tests during the batch; run ONE gate yourself afterwards.
- Require exclusive file ownership; state cross-file contracts explicitly (signatures, who owns what).
- Tell agents: "if a change needs a signature/test/other-file edit, REPORT it — do not apply."
- After the gate, diff every touched file against HEAD and read the hunks; the rendered diff can hide dropped lines, so raw-read collision regions.
