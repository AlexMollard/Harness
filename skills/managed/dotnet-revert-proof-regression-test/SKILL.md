---
name: dotnet-revert-proof-regression-test
description: "Prove a new .NET/bUnit test actually catches the bug it claims, and tell real test failures apart from MSBuild file-lock failures caused by a running app/dashboard holding its own DLLs. Use when adding a regression test for a UI/component fix, or when dotnet build/dotnet test exits non-zero with MSB3026/MSB3027/CS2012 while an app is running."
---

# Revert-proof a .NET regression test

A test that passes after a fix proves nothing on its own — it may pass against the
broken code too. Prove it *bites* by temporarily removing the fix and confirming
exactly the new tests fail.

Complication on Windows: a running app (dashboard, WPF client, `dotnet run`
service) holds its own build outputs open, so `dotnet build`/`dotnet test` can exit
non-zero **without ever running a test**. Mistaking that for "the test failed" gives
a false revert-proof.

## Distinguish lock failure from real test failure

Read the failure shape, never the exit code alone.

| Signal | Meaning |
|---|---|
| `MSB3026` / `MSB3027` "Beginning retry N", `Exceeded retry count of 10` | copy-step **lock** — nothing ran |
| `CS2012 Cannot open '<X>.dll' for writing ... locked by 'VBCSCompiler'` | concurrent build **lock** — nothing ran |
| `error CS####` | genuine compile error |
| `N passed, M failed` + a runtime (`687 ms`) | tests genuinely **executed** |

A locked build never emits pass/fail counts. `9 passed, 3 failed` is a real run.
MSBuild names the holder explicitly: `The file is locked by: "AntHill.Web (36272)"` —
use that PID.

Beware output truncation: `| tail -3` can hide the `ok`/`fail` summary line.
Prefer `| grep -iE "^ok|^fail|failed|error CS"` and print `${PIPESTATUS[0]}`.

## Procedure

1. **Write the test**, then run it filtered:
   `dotnet test <proj> --filter "FullyQualifiedName~<Class>"`
2. **Clear locks before trusting any failure.** Stop the holder named in
   MSB3026/CS2012 (supervisor `stop`, or `Stop-Process -Id <pid>`). Re-run.
3. **Neuter only the fix** — replace the added render block / logic with a marker
   comment. Do not delete the test or its parameters (that breaks compilation and
   yields a lock-like non-answer instead of a failure).
4. **Re-run the filter.** Expect: *new tests fail, all pre-existing tests pass.*
   The split is the proof. All-fail or zero-count = still a build problem.
5. **Restore the fix.** Verify the file tag/content matches the pre-revert state.
6. **Re-run full suites** and compare counts to the known-good baseline.
7. Restart any service stopped in step 2.

## Verifying edits really landed

Truncated `git status ... | head -N` can drop alphabetically-late files and look
like a missing edit. Confirm per-path instead:

```
git status --short -- <path>
git diff --stat -- <path>
grep -n "<NewTestName>" <path>
```

Strong independent corroboration: if `dotnet test` *discovered and ran* the new
tests, they were on disk — the compiler reads disk, not editor state.

## Anti-patterns

- Treating a non-zero exit as "test caught the bug" without a pass/fail split.
- Running two `dotnet build`/`test` invocations in parallel on shared projects —
  they fight over `VBCSCompiler` and produce CS2012. Run sequentially.
- Leaving the fix reverted. Always restore and re-verify green.
