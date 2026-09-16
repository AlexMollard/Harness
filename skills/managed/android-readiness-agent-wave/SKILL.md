---
name: android-readiness-agent-wave
description: "Run a parallel agent wave that closes Android production-readiness gaps (R8 + signing, Room migration tests, auto-backup privacy leak, crash journal, monotonic cloud sync, launcher icons, policy docs, CI) with exclusive file ownership, then integrate and verify. Use when asked to \"make this app prod ready\" or to fix a whole readiness audit at once, rather than auditing one gap at a time."
---

# Android readiness agent wave

Companion to `android-release-readiness-audit` (which *finds* the gaps). This is
how to **close them all concurrently** without the agents destroying each other's
work, plus the integration defects that show up every time.

## 1. Slice by exclusive file ownership

One agent per slice; no two agents may touch the same file. Workable split:

| Slice | Owns |
|---|---|
| BuildRelease | `app/build.gradle.kts`, `gradle/libs.versions.toml`, `app/proguard-rules.pro` |
| MigrationTests | `data/MonarchDatabase.kt` (the `@Database` class), `app/src/androidTest/**`, new `app/src/test/**/data/**` |
| BackupPrivacy | `AndroidManifest.xml`, `res/xml/**` |
| CrashJournal | new journal file, `MonarchApp.kt`, `SettingsScreen.kt` |
| SyncGuard | `data/cloud/CloudSync.kt`, `data/cloud/Dtos.kt` |
| LauncherIcon | `res/mipmap-*/**` only |
| PolicyDocs | `PRIVACY.md`, `docs/**`, `README.md` |
| CI | `.github/workflows/**` |
| SdkScout | read-only research (`scout` agent) |

Cross-slice dependencies must be **decided by the parent up front** and written
into the shared context, because agents cannot negotiate mid-flight. The two that
always bite:

- The gradle owner must add the androidTest deps, `testInstrumentationRunner`,
  the `room.schemaLocation` KSP arg **and**
  `sourceSets.getByName("androidTest").assets.srcDir("$projectDir/schemas")` —
  without that last line `MigrationTestHelper` fails with "Cannot find schema file".
- The `@Database` owner turns on `exportSchema`, not the gradle owner.

Tell every agent: **do not run gradle/lint/adb** (parallel Gradle runs fight over
the lock); the parent validates once.

## 2. Parent work while they run

Take anything touching files nobody owns — typically the lint warning cleanup,
which spans many files and would collide with everyone.

## 3. Integration gate — assume damage

```bash
# dropped imports (the #1 agent failure mode); strip CR first, files may be CRLF
for f in <changed .kt>; do
  git show HEAD:$f | tr -d '\r' | grep "^import " | sort > /tmp/h.txt
  tr -d '\r' < $f    | grep "^import " | sort > /tmp/n.txt
  echo "$f dropped: $(comm -23 /tmp/h.txt /tmp/n.txt | tr '\n' ' ')"
done
# non-import deletions, to eyeball for deleted functions/loops
git diff -U0 -- "*.kt" | grep "^-" | grep -v "^---" | grep -v "^-import "
```

CRLF also breaks `$`-anchored `grep`/`comm` checks — a "missing import" that the
compiler clearly resolves is the tool, not the file.

## 4. Defects this wave produces (seen every run)

- **Gradle name shadowing**: `val keyAlias = ...` then `create("release") { keyAlias = keyAlias }`
  → `'val' cannot be reassigned`. Rename locals to `keyAliasValue`.
- **Nullable field into non-null param**: `@Volatile var dir: File?` passed to
  `record(dir: File, …)`. Capture a local non-null first.
- **Early-return guards that disable the feature**: e.g.
  `Thread.getDefaultUncaughtExceptionHandler() ?: return` inside `install()` skips
  recording entirely. Install unconditionally, delegate with `previous?.…`.

## 5. Verification order (each gates the next)

1. `:app:assembleDebug :app:testDebugUnitTest`
2. `:app:assembleRelease` — R8 is the risky change; note the size drop.
3. **Negative test the fail-fast**: back up `local.properties`, blank the keys,
   assert the release task fails, restore, and verify the restore.
4. `:app:lintRelease` → triage the SARIF, not the HTML:
   ```python
   json.loads(Path("app/build/reports/lint-results-release.sarif").read_text())
   # count by (level, ruleId); level falls back to rules[id].defaultConfiguration.level
   ```
5. Device: `connectedDebugAndroidTest`, plus install a **debug-signed copy of the
   release APK** to smoke R8 at runtime (serialization/ktor break here, not at compile).

## 6. Judgement calls worth repeating

- **Don't blanket-fix lint.** `UnusedResources` on drawables is often art that was
  drawn and never wired — wiring it is the fix, deleting it hides a feature gap.
  `ModifierParameter` "should default to `Modifier`" is wrong when a non-plain
  default (`Modifier.fillMaxSize()`) is deliberate; changing it alters layout at
  every call site.
- **Locale in Compose**: `String.format(Locale.getDefault(), …)` inside a
  `@Composable` raises the `NonObservableLocale` **error**. Use
  `androidx.compose.ui.text.intl.Locale.current.platformLocale` (verify
  `platformLocale` exists in the pinned `ui-text` jar). Non-composable helpers may
  keep `Locale.getDefault()`.
- **Refuse i18n extraction** unless a second locale is actually needed — hundreds
  of strings, high breakage, no user-visible benefit.
- **Never create the release keystore.** Wire the config to credentials the owner
  supplies; generating their signing key is not yours to do.
