---
name: ksp-missingtype-dropped-imports
description: "Diagnose an Android Room/KSP build failing with one opaque \"[ksp] [MissingType]: Element 'XDatabase' references a type that is not present\" — nearly always a code-editing agent silently deleting imports or clobbering a neighbouring declaration, not a Room annotation problem. Use when KSP aborts with PROCESSING_ERROR and no Kotlin error line is shown."
---

# KSP `MissingType` on the @Database element

Symptom, and it is always this single unhelpful line:

```
e: [ksp] [MissingType]: Element 'com.x.app.data.MonarchDatabase' references a type that is not present
> Task :app:kspDebugKotlin FAILED
KSP failed with exit code: PROCESSING_ERROR
```

**KSP aborts before the Kotlin compiler reports anything**, so the real error — an
unresolved symbol *anywhere in the module* — is invisible. Do not read it as a Room
problem. It is a cascade.

Never patch suspects one at a time from the Room graph (entities, DAO return types,
migration bodies). Those checks pass while the real damage sits in a file the message
never names.

## The probe that works, in order

### 1. Diff imports against HEAD — highest yield by far

Code-editing agents rewrite import blocks and silently drop dozens of lines.

```bash
for f in data/MonarchDatabase.kt data/Repository.kt data/db/Entities.kt data/db/Daos.kt; do
  git show HEAD:app/src/main/kotlin/com/x/app/$f | grep "^import" | sort > /tmp/h.txt
  grep "^import" app/src/main/kotlin/com/x/app/$f | sort > /tmp/n.txt
  d=$(comm -23 /tmp/h.txt /tmp/n.txt); [ -n "$d" ] && echo "=== $f dropped:" && echo "$d"
done
```

Repair by merging both sets, never by hand-picking:

```python
merged = sorted(set(head_imports) | set(current_imports))
out = lines[:first_import] + merged + lines[last_import+1:]
```

Observed twice in one session: 34 imports gone from one file, 44 from two others.

### 2. Diff *declarations* against HEAD — the one everyone misses

An agent adding a member can **overwrite the line that was there**. The build then
fails for a symbol nobody edited.

```python
import re, collections, pathlib
t = pathlib.Path(DB_FILE).read_text(encoding="utf-8")
daos = re.findall(r"abstract fun (\w+)\(\)", t)
ents = re.findall(r"(\w+)::class", t)
print("dup daos:", [k for k,v in collections.Counter(daos).items() if v>1])
print("dup entities:", [k for k,v in collections.Counter(ents).items() if v>1])
```

A duplicate is the tell: the new member got appended *and* pasted over a neighbour.
Real case — `gachaDao()` appeared twice and `profileDao()` had vanished entirely.

Then diff the whole declaration list:

```bash
git show HEAD:$DB_FILE | sed -n '/abstract fun /p' > /tmp/h.txt
sed -n '/abstract fun /p' $DB_FILE > /tmp/n.txt
diff /tmp/h.txt /tmp/n.txt
```

### 3. Check the factory function still exists

The most destructive variant: the `fun create(context) = Room.databaseBuilder(...)`
lines get deleted, leaving the file dangling into `.addMigrations(`. Cheap check:

```bash
grep -c "Room.databaseBuilder" $DB_FILE   # must be 1
```

### 4. Cross-check the Room graph only after 1–3 come back clean

```python
imports = set(re.findall(r"^import com\.x\.app\.data\.db\.(\w+)", t, re.M))
used    = set(re.findall(r"(\w+)::class", t)) | set(re.findall(r"abstract fun \w+\(\): (\w+)", t))
print("referenced but NOT imported:", sorted(used - imports))
```

Genuine Room-side causes, in rough order of frequency:
- a DAO method typed `Flow<Int?>` against `SELECT *` — Room cannot map a row to a
  scalar. Either select the column (`SELECT rolls FROM …`) or return the entity.
  **Match it to what the repository actually calls**: one agent wrote the DAO, another
  wrote `.rolls` on its result, and neither compiled.
- a `@Database` entity list naming a class that no longer exists.
- a DAO returning a type Room cannot convert (`Set<T>` and friends).

### 5. Last resort — bisect with `git stash`

`git stash push <files>` a subset and rebuild. **Verify the stash actually emptied the
working tree** (`git status --porcelain`) before believing a green or red result; a
stash that silently no-ops proves nothing.

## Always check while you are in there

`fallbackToDestructiveMigration` is usually removed on purpose in a mature app (it
wipes user data on an unknown schema). So a migration that is **defined but never
registered** in `addMigrations(...)` is a guaranteed launch crash, not a warning:

```python
registered = re.findall(r"MIGRATION_\d+_\d+", t.split("addMigrations")[1])
defined    = sorted(set(re.findall(r"private val (MIGRATION_\d+_\d+)", t)))
print("defined but NOT registered:", [m for m in defined if m not in registered])
```

Also watch for the same migration registered twice — a sign of the clobber in §2.

## Prevention when delegating

- Tell edit agents: **never rewrite an import block**; add single lines only.
- Gate centrally. An agent forbidden from building will report "green" while the module
  does not compile — that happened on every wave in one session.
- After any agent wave touching Room files, run §1 and §2 *before* the build. They take
  seconds and name the damage precisely, while the build names nothing.
