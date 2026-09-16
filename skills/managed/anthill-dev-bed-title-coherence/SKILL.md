---
name: anthill-dev-bed-title-coherence
description: "Diagnose AntHill client showing only one title, empty project counts, or an asset that says \"not in your folder\" then \"already in\" — caused by an empty Projects table, a workspace cloned from a different Lore repo than the dashboard serves, or stale local catalogue rows. Use when the client and the real-art bed disagree."
---

# AntHill dev bed title coherence

Three symptoms share one cause family: the client, the dashboard database, and the
Lore repository describing different worlds. Diagnose in this order — each check is
cheap and rules out a whole class.

## Symptom → cause map

| Symptom | Cause | Check |
|---|---|---|
| Only one title in the picker | `Projects` table empty | `/api/config` shows `"projects":[]` |
| Titles listed but counts all 0 | no asset→project membership | snapshot `assets carrying a project: 0` |
| Sidebar lists titles the server does not | stale rows in client `catalogue.db` | compare local `Projects` to `/api/config` |
| "not in your folder", then "already in" | workspace is a clone of a *different* Lore repo | compare workspace top-level dirs to `rootPrefix` |

## 1. Ask the server what it offers

```bash
curl -s http://localhost:5252/api/config
```

`projects: []` means nothing is checkoutable. `ServerConfigService.BuildAsync` reads
`db.Projects`; `CheckoutableProjects` then filters on `!string.IsNullOrWhiteSpace(Branch)`.
So a project with no branch is listed but cannot be checked out.

The client is NOT caching stale config: `ServerConnection.ConfigAsync` fetches live every
ask and only falls back to `server-config.json` when the server is unreachable (15s backoff
after a failure). If the picker is empty, the database is empty — do not go hunting for a
sync bug.

## 2. Confirm against the database

Postgres usually runs in Docker, and `psql` is often not on PATH:

```bash
docker exec anthill-db-1 psql -U anthill -d anthill_bed -c 'select * from "Projects"'
```

Projects are created from the dashboard's **Settings → Add project** form
(`ProjectAdminService.CreateAsync`). Prefer that over SQL; use SQL only to unblock.
`Name` has a unique index, so seed with
`on conflict ("Name") do update set "Branch" = excluded."Branch"`.

## 3. Check the workspace is a clone of the repo the dashboard serves

This is the one that produces the contradictory pair of messages, and it is easy to miss
because both messages are individually true.

```bash
curl -s http://localhost:5252/api/config      # note loreServerUrl + rootPrefix
lore --repository <workspace> -P status       # note "Repository <id>"
ls <workspace>                                # top-level dirs must match rootPrefix
lore -P repository list lore://127.0.0.1:41337   # map id -> name
```

If `rootPrefix` is `source` but the workspace only holds `intermediate/`, the asset path
genuinely is not in the folder, and Lore then has nothing to bring for that path on that
branch — surfacing as "already in". Fix by re-cloning from the correct repo:

```bash
lore -P clone "lore://127.0.0.1:41337/<repo>" "<path>"
lore --repository "<path>" -P branch switch <branch>
```

A full real-art clone takes 1–3 minutes; run it backgrounded.

## 4. Title branches must exist AND be pushed

A fresh art repo often has only `main`. Creating a branch locally is not enough — the
client clones from the server:

```bash
lore --repository <repo> -P branch create <name>
lore --repository <repo> -P branch push <name>
lore --repository <repo> -P branch list      # confirm under "Remote branches"
```

`branch create` switches the working copy to the new branch; switch back to `main`
afterwards if that repo is the server-side working copy.

## 5. Clear stale local catalogue rows

Catalogue sync reconciles assets but leaves `Projects` and `AssetProject` rows behind, so
titles from an old bed linger with 0 counts. Stop the client first, then:

```bash
sqlite3 "$LOCALAPPDATA/BigAntStudios/AntHill/catalogue.db" \
  "delete from AssetProject; delete from Projects;"
```

They repopulate from the next snapshot.

## 6. Workspace registration

`workspaces.json` (`$LOCALAPPDATA/BigAntStudios/AntHill/`) lists working copies, and
`FolderChoices` shows only these — it never lists catalogue projects, so a title without a
registered folder cannot appear in the folder picker. `ProjectId` must match the *current*
catalogue id; ids from a previous bed silently point at the wrong project. Read at startup,
so **restart the client** after editing.

## Verify

```bash
curl -s http://localhost:5252/api/config          # projects with branches
curl -s "http://localhost:5252/api/sync/snapshot?since=0"   # assets + projects
ls <workspace>/<rootPrefix>/...                   # a real catalogue path resolves
```

## Gotchas

- Membership is derived from a project's `RootPath` during the crawl, or tagged per asset.
  A project with an empty `RootPath` will always show 0 assets however many exist.
- PowerShell inside bash double quotes eats `$_` and `$var`. Write a `.ps1` and run it with
  `-File`, or the script silently mangles.
- Kill leftover `AntHill.Web` before starting your own: an orphan holding 5252 gives
  `Failed to bind to address ... address already in use`.
