---
name: monarch-agent-wave-repair
description: "Run subagent edit waves on the Monarch Android repo (D:\\Monarch) and repair their known damage patterns: dropped imports/parameters, opaque KSP MissingType, Room migration discipline, and the live-Supabase apply gate."
---

# Monarch subagent waves: dispatch, gate, repair

Proven procedure from repeated edit-agent waves on D:\Monarch (Kotlin + Compose + Room + Supabase).
Agents there fail in consistent, detectable ways; this is the loop that keeps them shippable.

## Dispatch
- Split by **exclusive file ownership** — no file in two rosters. When two changes need one file,
  give the file to one agent and state the other's contract ("X owns it, you pass-through").
- Every brief carries: READ-ONLY data-layer rules if applicable, explicit greps, budget rule
  (grep first, read ±30 lines — files run 20-40KB), the finding with verified mechanism + intended
  fix, the output contract (findings/changes one per line, `path:line`, no preamble).
- **Contract block at the top of the shared context** for any shared component: exact signature,
  who owns it, "no signature change" clauses, who passes what. This prevented drift once and must
  always be stated.
- Tell agents explicitly: **no build/test/lint/formatter/commit** — concurrent agents break sibling
  builds transiently and an agent's "green" is measured mid-flight. The parent runs ONE gate after
  all settle.
- Cross-task side effects (e.g. an agent adding a parameter) must be REPORTED, not applied.

## The two known agent failure modes (both shipped real bugs)
1. **Dropped imports / dropped parameters.** Rewrite-happy agents have wiped 34-44 imports from a
   file, deleted a function parameter (`Achievement.name`, `IdentityRow.trailing`,
   `MonarchDatabase.fun create()`), and overwritten a sibling DAO declaration. Their self-reports
   claimed success each time.
2. **Wrong mechanism, right area** — e.g. a duplicate-cleanup SQL whose sort deleted the OLDEST row
   while the comment said oldest wins.

## Gate + repair procedure
1. `git status --porcelain=v1 --untracked-files=all` — touched set MUST equal the union of rosters.
   Extra files = stray edits; missing = undeclared work.
2. `:app:assembleDebug :app:testDebugUnitTest` (via `java -cp gradle/wrapper/gradle-wrapper.jar
   org.gradle.wrapper.GradleWrapperMain`, console=plain; filter `^e:|FAILED|BUILD`).
3. On `kspDebugKotlin FAILED: [MissingType]: Element 'com.monarch.app.data.MonarchDatabase'
   references a type that is not present` — this is OPAQUE; the real error is dropped imports or a
   clobbered declaration. Probe, do not guess:
   - Per touched file: `git show HEAD:<file> | grep ^import | sort` vs current imports; restore the
     UNION of both sets (new imports the agent added are kept, dropped ones return).
   - Brace-balance check (`count('{') - count('}')`) on the files agents edited; auto-repaired edits
     have left unclosed retry loops nesting private helpers (loads resolve as "unresolved" because
     they became members of another function).
   - Diff function/parameter lists vs HEAD (`fun (\w+)` sets) — this catches deleted parameters
     that compile-clean via defaults and deleted helper functions.
   - Room-specific: `SELECT *` cannot map to `Flow<Int?>` (select the column or return the entity
     row); a `@Database` entity/DAO line overwritten by a duplicate sibling declaration.
   KSP swallows the first Kotlin error; fixing the cascade source makes it vanish.
4. Re-gate until green, then read raw diffs of collision regions — compact renders drop words and
   have twice hidden real damage (a `background(...)` reconstructed wrong; a duplicated migration
   registration next to a deleted `Room.databaseBuilder`).

## Live-Supabase gate (user-mandated, no exceptions)
- Migrations are written to `supabase/migrations/` and STAGED. Applying via dockerized `psql` to the
  pooler needs an explicit per-run yes — "fix everything" is not consent, and a batch approval does
  NOT cover a later, new DDL. Name destructive steps explicitly when asking (row deletes/updates,
  ALTER on live tables), and verify row effects after (`DELETE 0`, `UPDATE 0` counts).
- Policy exploits (RLS) get proven dead by replaying the attack as `set local role authenticated`
  with JWT claims inside `begin ... rollback`, alongside the legitimate path.

## Device verification (S25 Ultra via adb)
- `run-as` + `sqlite3` does NOT work (no sqlite3 binary) — prove Room migrations BEHAVIORALLY:
  open the screen that reads the new tables, `FATAL: 0` from `logcat -d -b crash`, zero
  "migration didn't properly handle" lines, and real data rendering.
- Drive UI via uiautomator dump + tap by `text=`/`content-desc=` bounds. Coordinate taps drift onto
  identity rows and navigate instead — always locate nodes by text/desc, and read the `clickable`
  flag (icons are often `clickable=false` with a clickable parent).
- `rtk grep` silently returns EMPTY on some multi-alternation/paren patterns — never treat its
  emptiness as evidence; re-run with the built-in Grep tool.

## Post-wave
- Commit thematically, push, and report local == remote hashes plus what was verified on hardware
  vs build-verified only. Users there explicitly distinguish the two.
