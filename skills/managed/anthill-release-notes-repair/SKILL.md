---
name: anthill-release-notes-repair
description: "Diagnose and repair AntHill release notes when the client's \"What changed\" screen shows \"Nothing was recorded\" or forge release pages list the wrong/duplicated commits — covers the creatordate tie-sort trap in build/changelog.ps1 after a batch tag push, and backfilling published release pages via the Windows credential store. Use after tagging several commits at once, or when changelog entries look empty or cumulative."
---

# AntHill release notes repair

AntHill (`D:/AntHill`) derives every release note from git tags. After a batch tag
push (see the `anthill-release-tagging` skill — one annotated tag per commit) the
notes come out wrong in two different ways at once. Both have the same cause.

## The symptom pair

| Surface | What it looks like |
|---|---|
| Client/dashboard `/changelog` (from packaged `changelog.json`) | "Nothing was recorded for this one" on most versions |
| Forge release pages (from `release-notes.md` via `vpk pack --releaseNotes`) | Cumulative bodies — one release lists 20+ commits, the next the same list plus one |

Do not assume one implies the other. Check both; the fix is shared.

## Root cause

`build/changelog.ps1` built its ordered tag list with:

```powershell
git tag --list "v*" --sort=-creatordate
```

`creatordate` has whole-second resolution. A scripted tag batch creates many tags
inside one second, ties order non-deterministically, so `$previous` resolves to
the wrong tag and each `"$previous..$this"` range reaches the wrong distance —
empty for some releases, spanning dozens of commits for others.

Fix: order by the version number itself (parse the trailing integer, sort by
prefix then number, descending). Immune to same-second batches, and unlike a
lexical name sort it does not put `beta.9` above `beta.13`.

## Diagnose locally (no forge access needed)

```bash
powershell -NoProfile -File build/changelog.ps1 \
  -JsonPath ./_diag/changelog.json -NotesPath ./_diag/notes.md -Tag <newest tag>
```

Then assert, via PowerShell over the JSON: total release count, count with
`changes.Count -eq 0` (must be 0), and that the newest tag's entry holds exactly
one change under per-commit tagging. "Wrote N note(s)" where N ≫ 1 for a
per-commit tag is the scramble showing itself.

## Repairing already-published release pages

`tools/backfill-release-notes.ps1` PATCHes each release body, computing notes by
*invoking the generator* so the two can never drift. Dry run by default.

Auth on this workstation: there is no `RELEASE_TOKEN` in the environment, but the
Windows credential store holds a working credential for the forge.

```bash
git credential fill   # stdin: protocol=https\nhost=git.ba.bigant-internal.com\n\n
```

- The stored secret is a **password, not a PAT**: `Authorization: token <secret>`
  returns 401; Basic auth (`user:secret`, base64) works. The script's `-UserName`
  switches it to Basic.
- Never print the secret, never write it to a file, and clear it from memory when
  finished.
- TLS to the internal CA is trusted by PowerShell's `Invoke-RestMethod`; Bun's
  `fetch` may not be — prefer PowerShell for the REST calls.

```bash
powershell -NoProfile -File tools/backfill-release-notes.ps1 \
  -From v1.0.0-beta.72 -To v1.0.0-beta.99 -UserName <user> -Token <secret> -Apply
```

Verify afterwards by re-reading every tag in the span and counting `- ` bullets:
one per release is the correct state.

## Traps

- **404 per tag = no release object.** Not every pushed tag produces a release;
  runs fail or never start. Those cannot be PATCHed. Do **not** create bare
  releases to fill the gap — Velopack's feed reads releases for packages, and an
  assetless one is feed pollution. Re-running `publish-client.yml` for that tag is
  the only honest fix.
- **Installed packages keep their embedded `changelog.json`.** Fixing the
  generator heals every *future* install; it cannot reach a package already built.
  Say so rather than implying a global fix.
- **`AntHill.App` is a Razor class library** (`OutputType Library`) — `dotnet run`
  fails on it. The `/changelog` page is served by `AntHill.Web`; seed
  `changelog.json` into `src/AntHill.Web/bin/<config>/<tfm>/` (that is
  `AppContext.BaseDirectory` at runtime) and run that host to screenshot the page.
- **`ReleaseNotesTests` pins the page markup.** Any redesign of `WhatsNew.razor`
  breaks `The_page_lists_each_version`; re-pin it to the new classes rather than
  loosening the assertion.
