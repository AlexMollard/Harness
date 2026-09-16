---
name: antfarm-crash-dedup
description: Manage crash ticket deduplication and folder consolidation on the AntFarm share
---

# AntFarm Crash Dedup and Consolidation

Procedures for detecting, linking, and consolidating duplicate crash tickets and share folders in AntFarm (`D:/NightSmith`).

## Core Architecture & Key Concepts
- **Matching rules**: Two crashes match if they share the same site and masked detail (`crash_family.family_of`), OR share the top 3 culpable native stack frames (`dedupe._culpable_frames`).
- **Funnel filtering**: All native game stacks start with abort/handler frames (`ucrtbase.dll`, `std::terminate`, `AbortImmediate`, `paInstallCrashHandler`, `ntdll.dll`). Native frame comparison MUST strip these plus `LUA_BRIDGE_PLUMBING` (`paluaerrorhandler.cpp`, `paluabindfunction.h`, `paluaclassbinder.h`, `lj_api.c`, `paluabindinvoker.h`).
- **Identity Pinning**: Merging newer occurrence bundles into a canonical folder changes which bundle sorts newest in `_read_folder`, which alters `ident = repr(min(cause))` and mints a new ticket ID upon next ingest. A pin file (`.antfarm-crash-key`) containing JSON `{"key": "crash-..."}` must be written to the canonical folder before moving bundles.

## Operations

### 1. Dry Run / Inspect Duplicates
To inspect proposed groups without writing to the share:
```bash
.venv/Scripts/python.exe -m antfarm.queen_cli dedupe
```
Or check the Web UI Ready-to-Fix panel / query `GET /api/duplicates`.

### 2. Consolidate Crash Share Folders
Merging moves timestamped occurrence bundles from duplicate folders into the canonical folder, updates `info.md` (combining the `## Machines` table and updating `*First seen:*`), and removes the emptied duplicate folders.
**Important**: The supervisor must be stopped first to prevent ingest races:
```bash
# 1. Stop the supervisor
.venv/Scripts/python.exe -m antfarm.queen_cli stop

# 2. Run dedupe with apply
.venv/Scripts/python.exe -m antfarm.queen_cli dedupe --apply

# 3. Restart supervisor
cmd /c "start /B .venv\Scripts\python.exe main.py --ui > .antfarm\ui-restart.log 2>&1"
```

### 3. Undo a Consolidation Batch
Actions are logged to `.antfarm/crash-merge-undo.jsonl`. To reverse a batch:
```bash
.venv/Scripts/python.exe -m antfarm.queen_cli dedupe --undo <batch_id>
```

### 4. Automatic Ingest Linking
Automatic ticket linking is enabled by default via `pipeline.link_duplicates: true` in `antfarm.yaml`.
- Ingest only absorbs tickets created or reopened by *that specific pass*.
- Incumbent tickets already on the board always keep their write-ups and canonical status.
- Tickets in `needs_clarification`, `needs_file`, or with open questions are excluded from absorption.
- Share folders are **never** moved by the automatic ingest pass (share consolidation remains explicit/manual).
