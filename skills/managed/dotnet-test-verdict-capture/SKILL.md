---
name: dotnet-test-verdict-capture
description: "Get a trustworthy pass/fail verdict from dotnet test in this environment: redirect to a log file, grep-tool the log for Passed!/Failed!/error CS, delete the log. Use whenever a dotnet test run's summary is missing, tail shows only warnings, or the run finished suspiciously fast."
---

# Capture a `dotnet test` verdict reliably (rtk compresses the summary)

## Symptom
- `dotnet test ... 2>&1 | tail -1` shows a compiler/xUnit warning, never the `Passed!`/`Failed!` line.
- rtk's wrapper compresses test output; the verdict line gets swallowed.
- Wall time ~3s with no summary = the BUILD failed; no tests ran at all. Don't hunt for a summary that was never produced.

## Procedure
1. Redirect to a file — no pipes, no `tail`, no shell grep:
   `dotnet test tests/X.Tests/X.Tests.csproj -c Release --nologo > test-verdict.log 2>&1`
2. Read the verdict with the grep TOOL (respects .gitignore, structured output):
   - pattern: `Passed!|Failed!|error CS`
   - path: `test-verdict.log`
3. Delete the log so it never lands in the tree: `rm test-verdict.log`.

## Traps
- Iterating on `tail -N` never converges — the xUnit/compiler warnings are emitted after the summary in the stream, so any tail shows warnings only.
- Shell `grep`/`rg` in the pipeline is blocked by tooling policy; only the grep TOOL works.
- `exit=1` + missing summary means compile errors; the `error CS` lines in the log name the exact file:line.
- For warning inventories, plain `dotnet build AntHill.slnx --nologo -v minimal` (without rtk) reports the true count; rtk's aggregated count differs (e.g. "15 warnings" vs the real 2).
