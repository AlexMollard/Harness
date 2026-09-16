---
name: ksp-missingtype-import-recovery
description: "Diagnose the opaque Room/KSP \"MissingType: Element MonarchDatabase references a type that is not present\" — it's almost always silently dropped imports or a clobbered declaration in the db package, not a real schema problem. Proven recovery procedure for this codebase."
---

# KSP MissingType on MonarchDatabase — import-drop recovery

## Symptom
`:app:kspDebugKotlin` fails with exactly:
`e: [ksp] [MissingType]: Element 'com.monarch.app.data.MonarchDatabase' references a type that is not present`
— nothing else. KSP swallows the real Kotlin error, which is a resolution failure ANYWHERE in the module, not a schema problem in Room.

## Proven cause pattern
`task` subagents editing data-layer files repeatedly damage import blocks and neighbouring declarations:
- Whole import blocks silently dropped (once 34 imports wiped from Repository.kt, 44 in a later wave).
- A declaration overwritten by an adjacent one (e.g. `profileDao()` clobbered by a new `gachaDao()`).
- The `Room.databaseBuilder(...)` factory lines deleted, leaving the file dangling into `.addMigrations(`.
- A migration object defined but never registered (guaranteed launch crash, not a compile error).
- An entity/DAO type mismatch (e.g. `Flow<Int?>` declared against `SELECT *`).

## Recovery procedure
1. **Diff imports against HEAD for every file the agent touched** — this found all cases:
   ```bash
   git show HEAD:<file> | grep "^import" | sort > /tmp/h.txt
   grep "^import" <file> | sort > /tmp/n.txt
   comm -23 /tmp/h.txt /tmp/n.txt        # dropped
   ```
   Restore the union: merge HEAD imports with current imports, replace the whole import block.
2. **Structural audit of MonarchDatabase.kt** with python re:
   - duplicate `abstract fun x()` declarations (`collections.Counter`)
   - every `X::class` in `entities` and every `abstract fun(): X` has an import
   - every entity in `@Database` is declared in Entities.kt
   - migration objects: defined set == registered set (a defined-but-unregistered one is a runtime crash)
   - `fun create(...)` + `Room.databaseBuilder(...)` actually exist
3. **Room mapping mismatches**: `Flow<Int?>` cannot map `SELECT *` — declare the row type (or select the column). Mirror the row-style of sibling DAOs (`IdleDao` returns the row; Repository maps).
4. Only after 1-3, if still failing: temporarily comment the `@Database` annotation and run `:app:compileDebugKotlin` — the first plain-Kotlin `e:` line names the genuinely unresolved symbol. Restore immediately.

## After fixing
- Diff the touched file against HEAD (`git diff --stat` + read the hunks) to confirm ONLY intended changes remain — one repair spliced a new function inside `ArmyStat`'s modifier chain and had to be reverted from `git show HEAD`.
- Mark cross-agent contract mismatches: two agents coding against the same interface from opposite sides (DAO returns row, Repository expects scalar) compile-fail at the gate; align one side.

## Why not prevent
Agent briefs already say "don't break imports" and they break them anyway — the gate plus this recovery is the reliable control.
