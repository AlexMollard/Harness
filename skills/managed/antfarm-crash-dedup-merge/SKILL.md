---
name: antfarm-crash-dedup-merge
description: "Group duplicate AntFarm crash tickets and consolidate their folders on the //psrecap crash share at D:/NightSmith — covers the derived-identity trap that mints new tickets after a merge, the archive/ re-ingest bug, and the stop/apply/restart order. Use when asked to dedupe crash tickets, tidy the crash share, or when ticket counts grow after a merge."
---

# AntFarm crash dedup and share merges

For D:/NightSmith. Reduces duplicate crash tickets and consolidates their folders on the
shared crash drive. The share is other people's data — every step is dry-run-first and
reversible.

## The two traps that cost real tickets

**1. A merge changes a crash's identity unless you pin it.**
`crashes._read_folder` reads subdirectories `sorted(..., reverse=True)` — newest first — and
takes `fingerprint`/`lua_stack`/`stack` from the first instance with a manifest. The group key
is `sha256` of that `cause`, and that key IS the ticket id. So moving a *newer* bundle into a
canonical folder changes its cause, its key, and its ticket id: the next ingest files a brand
new ticket for the crash you just tidied.

Fix already in the tree: `crash_merge.apply` writes `.antfarm-crash-key` (`crashes.IDENTITY_PIN`)
into the canonical **before any bundle moves**, and `group_by_fingerprint` prefers the pinned key
over the evidence. If you add a code path that moves bundles, it must write the pin too.

A folder merged *before* the pin existed keeps its post-merge id. Fix by hand, and do it
**before** linking the stray as a duplicate — otherwise the link absorbs a ticket nothing
points at:

```python
from antfarm.crashes import IDENTITY_PIN, DERIVED_KEY_RE
from antfarm.tickets import crash_ticket_id
assert DERIVED_KEY_RE.match(key) and crash_ticket_id(key) == key
(folder / IDENTITY_PIN).write_text(json.dumps({"key": key, "note": "..."}) + "\n", encoding="utf-8")
```

**2. `archive/` was ingested as one giant fake crash.**
`scan()` walked every top-level directory and `_read_folder` counts every subdirectory as an
occurrence, so retiring a crash re-filed it. `scan` now skips `crashes.ARCHIVE_DIR`. If a ticket
literally named `archive` appears, that skip has been lost.

## Matching rules

`dedupe.groups()` matches on **same crash site** (`crash_family.family_of`) **or** the first 3
**culpable** frames. Culpable means after dropping the funnel — every stack here starts
`ucrtbase` → `std::terminate` → `AbortImmediate` → `paInstallCrashHandler` → `ntdll`, so raw
top-frame matching matches everything. Exclusions live in `crash_title._is_handler_frame`,
`crash_history.ABORT_PLUMBING` and `dedupe.LUA_BRIDGE_PLUMBING`.

Adding a frame to the plumbing list is the safe direction (fewer merges). Measure before and
after on a **copy** of the DB:

```python
con = sqlite3.connect("file:.antfarm/antfarm.db?mode=ro", uri=True)
con.backup(sqlite3.connect(tmp))          # never open the live DB for writing
before = dedupe.groups(Store(tmp, log), log)
```

## Procedure

1. **Dry run** — `.venv/Scripts/python.exe -m antfarm.queen_cli dedupe`. Default writes nothing.
   Read the per-group plan: moves, empties, `retained`, info.md line delta.
2. **Stop the colony** — `queen stop`, then confirm `.antfarm/run.lock` is gone. `--apply`
   refuses while it runs (it re-ingests the share on a cycle) unless `--force`.
3. **Record pre-state** — top-level folder count per share, ticket counts by state,
   `count(*) where duplicate_of<>''`.
4. **Apply** — `queen dedupe --apply`. Variants: `--tickets-only` (no share writes),
   `--group HANDBALL-176`, `--undo BATCH_ID`.
5. **Restart** and verify the churn is closed: **total ticket count and `max(created_at)` must be
   unchanged**. A rise means the identity pin is not being written or read.
6. Expect `/api/duplicates` to report 0 groups.

Undo log is `.antfarm/crash-merge-undo.jsonl` — local on purpose, because the share may be down
when the undo is needed and a log on the share could sit inside a folder the merge removes.

## Verifying counts

Folder-count arithmetic that does not add up is usually **a second project's share**
(`antfarm.yaml` configures Handball 27 *and* Cricket 8). Check the rmdir paths' parents in the
undo log before assuming folders appeared or vanished:

```python
top = [p for p in rmdirs if p.parent == share]   # the rest are another project
```

## Interpreter

`.venv/Scripts/python.exe`. A bare `python` dies with `ModuleNotFoundError: No module named 'yaml'`
before it ever binds a port — a silent-looking failure when launching the dashboard.
