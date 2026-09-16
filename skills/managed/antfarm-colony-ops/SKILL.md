---
name: antfarm-colony-ops
description: "Run, restart, and verify the AntFarm colony at D:/NightSmith after code changes — correct interpreter, run.lock handling, dashboard checks, and the known-failing test baseline. Use when editing antfarm/ code, when the dashboard says \"Failed to fetch\", or when attributing pytest failures in this repo."
---

# AntFarm colony ops (D:/NightSmith)

Repo-specific operational facts learned the hard way. Applies to the AntFarm
colony: supervisor loop + `queen` CLI + web dashboard on `127.0.0.1:8770`.

## Interpreter

**Always `.venv/Scripts/python.exe`.** A bare `python` on PATH lacks the
project deps and dies with `ModuleNotFoundError: No module named 'yaml'`
*before* binding the port — which looks exactly like a server that started and
then broke.

```
.venv/Scripts/python.exe main.py --ui          # colony + dashboard
.venv/Scripts/python.exe -m antfarm.queen_cli status
.venv/Scripts/python.exe -m pytest tests/ -q
```

`AntFarm.cmd` locates the venv itself, but it does **not** survive a
non-interactive/PTY shell: its `rem` comment lines get fed back to `cmd.exe`
as literal commands (`'tarts' is not recognized...`). Launch it by hand, or use
the venv interpreter directly from a script.

## Is it actually running?

"Cannot reach the dashboard server — TypeError: Failed to fetch" almost always
means *nothing is listening*, not a code regression. Check in this order:

```
netstat -ano | findstr :8770        # LISTENING + pid, or nothing
tasklist /FI "PID eq <lock pid>"    # is the run.lock pid even alive?
curl -sS -i http://127.0.0.1:8770/api/overview
```

Then read `.antfarm/heartbeat.json` (`pid`, `cycle`, `uptime_s`) and the newest
`.antfarm/logs/events-*.jsonl` for `ui_listening` / `colony_start` / a traceback.

## run.lock needs no cleanup

`.antfarm/run.lock` holding a **dead** pid is not a blocker. `runlock.read()`
returns `None` when `_pid_alive(pid)` is false, so `acquire()` takes it. Never
delete it manually; never propose "clear the stale lock" as a fix.

## Restarting after a code change

1. Read `.antfarm/run.lock` and check whether that pid is alive — **never start
   a second colony**.
2. If live, stop it. `queen stop` is acked immediately but cannot abort an
   LLM call already streaming; if it is mid `streaming:planner` it may need
   `taskkill /PID <pid> /F`. `reconcile_interrupted()` cleans up the open
   episode on the next start.
3. Start detached with the venv interpreter, leave it running and unpaused.
4. Prove it: `netstat` LISTENING + `curl /api/overview` 200 + heartbeat pid
   matches the new `run.lock`.

## Known-failing test baseline

`pytest tests/ -q` has **12 pre-existing failures** unrelated to any current
change. Confirm the set is unchanged; do not "fix" them and do not count them
against your work:

- 9 × `tests/test_watchdog_liveness.py` — `AttributeError: '_Sup' object has no
  attribute '_drain_control_off_thread'` (test double predates the method)
- 2 × `tests/test_lint_is_clean.py` — `TestPython` (`RUFF_BASELINE=29` constant
  is stale, actual 43) and `TestFrontend` (oxlint drift in `ScreenMap.tsx`)
- 1 × `tests/test_subprocess_decoding.py[supervisor.py-]` — a `subprocess.run(text=True)`
  without `errors=`

Attribute any *new* failure properly: `git stash`, re-run the same test ids,
`git stash pop`. Never assert "pre-existing" without that comparison.

## Repo conventions that bite

- **No shell heredocs.** They have corrupted source files here by interpreting
  `\n`. Use the file-write tool.
- Ruff runs `I001` import sorting — adding an import to a module can fail the
  lint test by itself. Check the ruff finding count against baseline, not just
  the test's pass/fail.
- Never `rm` in the repo root during cleanup: an untracked, never-committed
  `AntFarm-LAN.cmd` was destroyed that way and was unrecoverable (not in git,
  not in the backup zip, not in `$Recycle.Bin`).
- Commit style: imperative subject < 72 chars, no `feat:`/`fix:` prefixes, no
  attribution, flat `- Imperative phrase` bullets only when grouping.

## Architecture facts worth not re-deriving

- Live roles are exactly `queen`, `planner`, `explorer` (`config.ROLES`).
  `coder`/`critic`/`tester` are removed and a config naming them is *rejected*
  (`config.py` `_REMOVED_ROLES`); so are the `vram`/`telemetry`/`budget`/
  `farm`/`backend`/`ollama` sections (`_REMOVED_SECTIONS`).
- Every role needs `roles.<role>.model`; nothing picks one. Startup refuses
  with `NoModelForRole`.
- `dispatch.triage_order()` is the single ordering source read by both
  `Queen.cycle` and the dashboard's `/api/queue`. Keep them on one function —
  they diverged once and the queue page silently showed nothing for months.
- Control commands: `control/inbox.jsonl` append-only + byte offset. Both ends
  must open with `newline=""` or Windows CRLF translation drifts the offset.
