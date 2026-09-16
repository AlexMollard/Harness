---
name: dispatch-agent-import-repair
description: "Repair the recurring agent damage pattern: dropped import blocks, clobbered declarations, deleted helper functions in Monarch (or any Kotlin repo) after parallel task-agent edits, plus the KSP MissingType diagnostic that masks it"
---

# Repairing agent-damaged Kotlin files after a parallel dispatch

Parallel `task` agents editing one repo repeatedly (a) rewrite import blocks and drop 20-40
existing imports, (b) overwrite unrelated declarations near their edit site, (c) delete helper
functions/flows, and (d) report success while the build is broken. In Monarch this happened on
three consecutive dispatches. Their self-reports are worthless; only the gate counts.

## Recognize it

- KSP failure: `e: [ksp] [MissingType]: Element '<DbClass>' references a type that is not present`
  — one opaque error that HIDES the real Kotlin resolution failure. It does NOT mean the database
  class is broken; it means any type in the module failed to resolve.
- Plain `e: Unresolved reference 'X'` on symbols that obviously exist.

## The proven probe sequence (in order, cheapest first)

1. **Brace balance** on every touched file:
   `python -c "t=open(f,encoding='utf-8').read(); print(t.count('{')-t.count('}'))"` — must be 0.
   Auto-repaired edits twice left unclosed blocks that nested unrelated private functions inside
   another function (symptom: `Unresolved reference` on a function whose definition EXISTS in the
   file, but nested at depth > 1).
2. **Import diff against HEAD**, per touched file — this found 34-44 dropped imports each time:
   ```
   git show HEAD:<file> | grep "^import" | sort > head.txt
   grep "^import" <file> | sort > now.txt
   comm -23 head.txt now.txt        # dropped imports = the damage
   ```
   Restore by UNION: keep current imports + all HEAD imports, sorted, replacing the block between
   first/last import lines. Do not hand-pick.
3. **Symbol diff against HEAD** for declarations:
   `git show HEAD:<file>` vs current, compare `fun (\w+)` / `data class (\w+)` / `val (\w+)` sets.
   Found: a ViewModel property (`healthDays`) deleted while its `by collectAsStateWithLifecycle()`
   usage survived; `abstract fun profileDao()` overwritten by a new dao; `Room.databaseBuilder`
   factory function deleted outright; a duplicate `abstract fun gachaDao()` in two places.
4. **Cross-agent contract mismatch**: two agents implement the same API from the brief and disagree
   (e.g. DAO returns `Flow<Int?>` while Repository maps `.rolls` on it; or a `Set<String>` where Room
   can't map). Grep both sides and align to the side the tests/most callers assume.
5. Room-specific mapping trap: `@Query("SELECT * FROM t")` with `fun x(): Flow<Int?>` cannot map a
   row to a scalar — Room fails the WHOLE `@Database` with the same opaque MissingType. Return the
   entity (or select the single column).

## Repair discipline

- Reconstruct damaged regions from `git show HEAD:<file>`, NEVER from memory — a from-memory repair
  of a modifier chain shipped `shapes.extraSmall/padding(10,8)` where HEAD said `shapes.small/
  padding(12)`. Diff after repair; the diff must contain ONLY intended changes.
- After repair, re-run the diff to confirm zero collateral (stray deletions are how the next bug
  gets in).
- Then run the single gate (`assembleDebug` + `testDebugUnitTest`) once, after all agents settle —
  never mid-flight, it measures siblings' half-finished work.

## Prevention for the briefs (cheaper than repair)

- Tell agents explicitly: "do not rewrite the import block; add only the imports you need, never
  remove existing ones."
- State shared-API signatures verbatim in the shared context and name the owning agent.
- Require: "final message must list any symbol you deleted and confirm no other file references it."
