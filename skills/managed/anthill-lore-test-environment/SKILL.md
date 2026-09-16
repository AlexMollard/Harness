---
name: anthill-lore-test-environment
description: "Get trustworthy results from AntHill's AntHill.Lore.Tests integration suite - start the local loreserver first (the suite silently SKIPS ~47 tests without it) and tell testbed-state failures apart from real code failures. Use before believing any Lore.Tests result, or when Lore tests fail with \"Disconnected from server\", \"merge waiting to be committed\", or \"merge.rs:303\"."
---

# AntHill Lore test environment

`tests/AntHill.Lore.Tests` is an integration suite against a **shared on-disk testbed** and a
**local Lore server**. Both are external state. A green-looking run can be hiding most of the suite.

## 1. Start the Lore server before believing any result

The suite does not fail when the server is down — it **skips**. Observed on this repo:

| Server | passed | failed | skipped |
|---|---|---|---|
| down | 50 | 10 | **53** |
| up | 100 | 7 | 6 |

Starting the server moved **47 tests from skipped to actually running**. A "50 passed" run was
testing about half of what it appeared to.

Locations (not on PATH, not in the repo):

- server binary: `C:/Users/alex.mollard/bin/loreserver.exe`
- config dir: `D:/AntHillTesting/loreconfig` (auth disabled; see
  `docs/superpowers/notes/loreserver-local.toml`)
- listens on **41337**; client CLI is `D:/AntHillTesting/tools/lore.exe`

Start it, waiting on the port:

```
loreserver.exe --config D:/AntHillTesting/loreconfig     # cwd D:/AntHillTesting
```

Check first — `Get-NetTCPConnection -State Listen` filtered to 41337. `netstat` is not reliably
available through the `rtk` proxy; use PowerShell.

**Always report the skipped count**, not just passed/failed. Rising skips = environment regressed.

## 2. Attribute the remaining failures before blaming code

With the server up, failures may still come from the **testbed's state**, not the change under test.
Read the error text — it names the cause:

- `Disconnected from server` → server down. Go back to step 1.
- `There is a merge waiting to be committed in <branch>. Send it back first` → a stuck
  merge in the shared workspace.
- `at lore-revision\src\branch\merge.rs:303:1` / `Invalid merge type` → Lore cannot
  deserialize that workspace's merge state. Environmental, unfixable from AntHill code.

A stuck merge in `D:/AntHillTesting/artist` contaminated **7 tests across four unrelated
fixtures** (`SelectiveFetchTests`, `CherryPickTests`, `BranchSwitchTests`, `BareWorkspaceTests`).
None of them were about merging.

Confirm attribution positively — run the suite filtered to the tests that actually cover your
change and show them passing:

```
dotnet test tests/AntHill.Lore.Tests/... --filter "FullyQualifiedName~<YourType>"
```

Failures in fixtures your change never touches + an error naming the testbed = environmental.

Probe testbed state directly rather than guessing:

```
lore.exe --repository <workspace> -P status
lore.exe --repository <workspace> -P history --only-branch
```

`status`/`history` can succeed while `branch merge resolve` fails — the merge state is a
separate structure from the revision metadata.

## 3. Build locks are not test failures

Running `AntHill.Web` locks `AntHill.App.dll`; a running `AntHill.Client` locks its own
`.exe`. Both surface as build failure, **not** a test result:

- `MSB3026`/`MSB3027`/`MSB3021` + `locked by: "<proc> (pid)"` → lock. Stop the process, retry.
- A genuine run always prints test counts (`9 passed, 3 failed`) and a duration. No counts = nothing ran.
- Zero `error CS` lines means compilation succeeded; only the copy step failed.

Stop the dashboard before any build that touches `AntHill.App`, and restart it afterwards —
otherwise the client stops seeing the real catalogue.

## Cost note

A full `AntHill.Lore.Tests` run is **5–8 minutes**. Budget for it, and prefer `--filter` for
attribution passes.
