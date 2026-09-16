---
name: anthill-client-tests-port-5252
description: "Diagnose AntHill.Client.Tests SetupFlowTests failing 2-instead-of-skipping when a stray AntHill.Web process occupies localhost:5252 — find and kill the orphan, restore the skip baseline."
---

# AntHill.Client.Tests: stray web process on port 5252

## Symptom
`dotnet test tests/AntHill.Client.Tests` reports exactly 2 failures in
`SetupFlowTests` (`Once_told_where_the_server_is_it_can_list_the_titles`,
`A_machine_that_loses_the_network_still_knows_what_it_saw`) with skips down
from 3 to 1. Code baseline is innocent.

## Mechanism
`tests/AntHill.Client.Tests/SetupFlowTests.cs` gates its server-dependent
`[SkippableFact]`s on `Reachable("localhost", 5252)` (const `DashboardUrl`).
Any process listening on 5252 un-skips them; if it is not the real dashboard
backed by a live database, they fail. Classic source: a leftover debug
`AntHill.Web.exe` from `dotnet run src/AntHill.Web` (e.g. an agent's repro)
whose database container was already removed.

## Diagnosis
1. `netstat -ano | findstr :5252` → note PID (a `[::1]:5252 LISTENING` line).
2. `Get-Process -Id <pid> | Select ProcessName,Path` — expect
   `AntHill.Web` under `src\AntHill.Web\bin\Debug\net10.0\`.
3. Confirm attribution before killing: re-run the suite after killing, expect
   `Passed: 271, Skipped: 3, Failed: 0`.

## Fix
`Stop-Process -Id <pid> -Force`, re-run Client.Tests. Do not touch unrelated
listeners (41337 is the studio Lore server; `anthill-db-1` on 5432 is the dev
compose stack).

## Prevention
Any workflow that boots AntHill.Web for repro/verification must kill the
process (not just the containers) and verify the port is free before
yielding.
