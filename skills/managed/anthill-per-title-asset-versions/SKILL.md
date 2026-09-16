---
name: anthill-per-title-asset-versions
description: "Wire up AntHill so every asset has a tracked version per title/branch (the TitleVersions axis) - branch creation, crawler BranchPaths, forcing real divergence, and verifying it in the catalogue. Use when per-title versions are missing, all titles read \"current\", project counts are 0, or the title picker offers nothing."
---

# AntHill per-title asset versions

Getting "one version of each asset per title" working. The model already exists — do
not build a new one.

## The model (verify before changing anything)

- `AssetRevisions` is UNIQUE on `(AssetId, Branch)` — one recorded version per asset
  per branch. `AssetLibraryContext` defines this.
- `TitleVersion.Current` compares by **ContentHash, not date**. Two titles holding
  identical bytes both read current; older bytes read `Behind`.
- `TitleVersionsPanel` (asset page) reads the **catalogue**, not workspaces — so it
  works offline and dashboard/client agree.
- Populated only by the crawler via `Indexer:BranchPaths`.

## Preconditions, in order

1. **A branch per title on the repo the dashboard points at.** Check
   `/api/config` → `loreServerUrl`. A project whose `Branch` has no matching Lore
   branch gives "this machine does not know a branch called X".
2. **A project row per title with `Branch` set.** `ServerConfigService` reads
   `db.Projects`; an empty table ⇒ `"projects": []` ⇒ title picker offers nothing.
   Create via dashboard Settings → Add project (not SQL).
3. **A workspace per branch** for the crawler.

## Setup

```bash
LORE=D:/AntHillTesting/tools/lore.exe

# branches (from a workspace on the repo)
"$LORE" --repository <mainWs> -P branch create <title>
"$LORE" --repository <mainWs> -P branch push   <title>
"$LORE" --repository <mainWs> -P branch switch main   # restore

# one workspace per branch
"$LORE" -P clone "lore://HOST:PORT/<repoName>" <path>
"$LORE" --repository <path> -P branch switch <title>
```

Crawl (RunOnce seeds; drop it for the 5-min loop):

```
ConnectionStrings__AssetLibrary=Host=...;Database=<db>;...
Indexer__RepositoryPath=<workspace on main>      # the library
Indexer__BranchPaths__0=<title workspace>
Indexer__BranchPaths__1=<title workspace>
Indexer__Rules=bigant-source                     # authored art; bigant = cooked
Indexer__RootPrefix=source
Indexer__RunOnce=true
dotnet run --project src/AntHill.Indexer.Host
```

Expect per branch: `Crawled branch workspace <path>: N entries recorded`, then
`Filed N asset(s) into projects by the branch holding them` — that line also
populates project membership, fixing 0-count sidebars.

## Divergence is required for the axis to mean anything

Branches created from one revision are byte-identical, so every title reads
"current" — correct and useless. Force a real difference:

```bash
# modify a file, then (message is POSITIONAL, -m is rejected)
"$LORE" --repository <ws> -P stage <path>
"$LORE" --repository <ws> -P commit "message"
"$LORE" --repository <ws> -P push
```

## Verify in the catalogue, not the UI

```sql
select r."Branch", r."RevisionId", left(r."ContentHash",16)
from "AssetRevisions" r join "Assets" a on a."Id"=r."AssetId"
where a."Path" like '%<asset>%' order by r."Branch";
```

Diverged branch shows a different RevisionId *and* ContentHash. Multiple rows per
branch = multi-file asset; only changed files differ.

## Traps

- **A title's crawl deliberately concludes very little**: records that branch's
  revision only. It will not add/remove assets or rewrite derived fields. Crawling a
  title *as if it were main* empties the catalogue on the first pass.
- Main is crawled first on purpose, so new assets land everywhere in one pass.
- **Never point BranchPaths at folders being edited** — the crawl records
  uncommitted work as what the title holds. Use dedicated read-only clones.
- `RootPath` on a project must be a real prefix of the tree (e.g. under `source/`),
  or it matches nothing. Branch-based filing still works regardless.
- Indexer refuses to start if migrations are pending (the web app owns schema).

## Lore CLI gotchas

- `clone` needs the repo name: `lore://host:port/<repoName>`, not the bare host.
- Find it: `lore -P repository list "lore://host:port"` and match the repository id
  from `<ws>/.lore/config.toml` / `lore status`.
- `--repository <path>`, not `-o`. `history <N>` is positional, not `-c N`.
