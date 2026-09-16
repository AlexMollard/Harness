---
name: antfarm-webui-command-verify
description: "Diagnose and prove fixes for AntFarm dashboard command bugs (toasts like \"missing argument(s): ticket_id\", buttons that silently do nothing) — arg-contract tracing, dist rebuild, colony restart on Windows, and browser payload capture that never mutates live tickets. Use when a D:/NightSmith dashboard action misbehaves."
---

# AntFarm web UI command verification

For bugs in the D:/NightSmith dashboard's *command* path: a toast error, a button
that queues nothing, an action that applies to the wrong thing.

Complements `antfarm-colony-ops` (run/restart/test baseline). This one is only
about the browser → API → supervisor command contract.

## The contract, end to end

Four places must agree. Any mismatch fails silently, because `Api.command`
**drops** unknown args rather than rejecting them:

1. `frontend/src/**` — `run.mutate({ cmd, args })`, e.g. `components/AnswerBox.tsx`
2. `antfarm/webui/api.py` — `UI_COMMANDS`, `_ARG_ALLOW`, `_ARG_REQUIRED`
3. `antfarm/control.py` — `COMMANDS` (closed vocabulary; `drain()` drops the rest)
4. `antfarm/supervisor.py` — `_cmd_<name>`, which reads `args.get("x")`

```python
clean = {k: v for k, v in args.items() if k in _ARG_ALLOW.get(cmd, set())}
missing = _ARG_REQUIRED.get(cmd, set()) - set(clean)   # -> "missing argument(s): ..."
```

Two failure modes:
- Arg in `_ARG_REQUIRED` but the frontend sends a different key → visible toast.
- Handler reads an arg absent from `_ARG_ALLOW` → **silent** wrong behaviour
  (the command runs with that arg missing). This is the dangerous one.

## Diagnose

```bash
rtk grep -rn "missing argument" antfarm/            # the message
rtk grep -n -A12 "^_ARG_ALLOW" antfarm/webui/api.py
rtk grep -n -A20 "_cmd_<name>" antfarm/supervisor.py   # what it really reads
cd antfarm/webui/frontend/src && rtk grep -rn "cmd: '<name>'" --include=*.tsx .
```
Compare the frontend's arg keys against `_ARG_ALLOW[cmd]` against every
`args.get("...")` in the handler. Beware id confusion: a `Question` has both
`id` (its own numeric id) and `ticket_id`.

## Regression test that catches the whole class

Put it in `tests/test_control_vocabulary.py`, which already pins this contract
by parsing `supervisor.py` source:

```python
for cmd in sorted(UI_COMMANDS):
    body = re.search(rf'def _cmd_{cmd}\(.*?(?=\n    def )', source, re.DOTALL)
    if body is None:
        continue
    read = set(re.findall(r'args\.get\("([a-z_]+)"', body.group(0)))
    assert not (read - _ARG_ALLOW.get(cmd, set()))
```
Prove it is revert-proof: patch the allow-list back to the buggy value, expect
FAILED, restore, expect green.

## Make the fix actually reachable

Both steps are required and both are easy to forget:

```bash
cd antfarm/webui/frontend && npm run build     # dist/ is what the server serves
```
Server-side changes to `_ARG_ALLOW` live in the **running process's memory** —
the dashboard is served by the supervisor. Restart it or you will verify the old
code. On Windows `nohup` silently fails to detach; use:

```bash
cmd /c "start /B .venv\Scripts\python.exe main.py --ui > .antfarm\ui-restart.log 2>&1"
sleep 30 && rtk read .antfarm/run.lock      # confirm a NEW pid
```

## Prove it without mutating live data

Reproduce over HTTP first (a nonexistent ticket id gets past arg validation into
the handler, changing nothing):

```js
fetch('http://127.0.0.1:8770/api/command', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', 'X-AntFarm-UI': '1' },  // CSRF guard
  body: JSON.stringify({ cmd, args }),
})
```
Then confirm the arg survived the filter — the event log records the *cleaned*
args, which is the real evidence:

```bash
rtk grep -o '"cmd": "<name>", "args": [^}]*}' .antfarm/logs/events-$(date +%F).jsonl | tail -1
```

To prove the **real button** sends the right payload without touching the
operator's tickets, intercept and abort inside `tab.run`:

```js
await page.setRequestInterception(true);
page.on('request', r => r.url().includes('/api/command')
  ? (seen.push(r.postData()), r.abort())
  : r.continue());
```
Afterwards verify nothing landed (e.g. the question is still `open`,
`answered_at=None`).

## Known design constraint — not a bug

`answer` is deliberately excluded from `Supervisor._OFF_THREAD` (see the comment
above it) because it touches `reporter.write_questions()`, which is not
lock-protected; the off-thread commands only touch the RLock-guarded store. So
`answer` applies at the cycle top, not within 0.25s. Do not "fix" this by adding
it to the list without making the reporter thread-safe first.
