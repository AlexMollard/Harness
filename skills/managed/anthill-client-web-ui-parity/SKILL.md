---
name: anthill-client-web-ui-parity
description: "Diagnose AntHill UI that looks wrong only in the WPF client (oversized Lucide icons, unstyled panels) or features that are blank only in the client (the notification bell) — covers the Blazicon attribute-vs-class selector trap, verifying shared app.css in a headless dashboard, and the rule that client-only data must be plumbed because the catalogue snapshot is shared by every machine. Use before blaming WebView2 caching or a stale install."
---

# AntHill: when the client looks or behaves differently from the dashboard

`src/AntHill.App` is one component library and **one `app.css`** served to two hosts:

- Web dashboard → `AntHill.Web/Components/App.razor`, fingerprinted `@Assets[...]`
- WPF client → `AntHill.Client/wwwroot/index.html`, plain `_content/AntHill.App/app.css`

Two failure classes look host-specific and are not. Diagnose before blaming caching.

## 1. Icons render huge (~24px): the selector never matched

**Blazicons renders an attribute, not a class:**

```html
<svg blazicon="" width="24" height="24" viewBox="0 0 24 24" ...>
```

So every rule written as `svg.blazicon { ... }` is **dead on both hosts**. With no CSS
width, the SVG falls back to its intrinsic `width="24"`.

The dashboard can still *look* fine — a flex parent shrinks the 24px SVG to roughly the
heading's font-size — which is why this reads as "client-only". It is not.

Fix is one mechanical swap across `app.css`:

```
svg.blazicon  →  svg[blazicon]
```

Then the intended sizes apply by construction (`.facet h2 svg[blazicon] { font-size: 13px }`).
Project rule: the client's side-panel icons must match the web's size, and the web is the
reference — so fix the selector rather than inventing a new px value.

**Confirm what Blazicon actually emits before swapping:**

```js
document.querySelector('.facet h2 svg').outerHTML.slice(0, 120)
```

## 2. Verifying shared CSS when the WPF client cannot be screenshotted

The dashboard serves the identical stylesheet, so measure there:

```bash
docker run -d --name nb-pg -p 5437:5432 -e POSTGRES_USER=anthill \
  -e POSTGRES_PASSWORD=smoke -e POSTGRES_DB=anthill_nb postgres:18.3
dotnet build src/AntHill.Web/AntHill.Web.csproj   # never --no-build; it serves a 0-rule sheet
```

Then in a headless tab: check the sheet loaded (`cssRules.length` ~800, not 0), measure the
element, and **inject the component's markup** to see a state the local host cannot reach
(the bell hides for `unattributed`, so a signed-out dev dashboard never renders it):

```js
host.innerHTML = `<details class="bell-menu" open>...`;  // real classes, real stylesheet
await tab.screenshot({ path: "_diag/probe.png" });
```

Injection proves styling only. Pair it with a bunit test for the component's own contract.

## 3. A feature that is blank only in the client is usually missing data plumbing

`SyncSnapshot` carries projects, assets, files, revisions, dependencies, comments, claims —
**one answer shared by every machine, cached as bytes**. Anything addressed to one person
was never in it. The notification bell read the client's local `Notifications` table, which
nothing ever wrote to, so it showed "Nothing yet." to every artist since it shipped.

Pattern for per-artist data:

- Its own endpoint, not the snapshot (`GET /api/sync/notifications?for=<name>`), because
  folding per-person data into the shared snapshot breaks its cache or leaks it.
- Identity is the Windows user the client already runs as (`ICurrentUser` →
  `DesktopCurrentUser`), sent by name and canonicalised server-side with
  `IdentityName.Canonical` — the same trust model `EditPush.MadeBy` already uses.
- **Never send the server's row ids as if they mean something locally.** The two catalogues
  number independently; carry the asset *path* and resolve it against the local catalogue.
- Write-back state (read/seen) belongs to the library, or the next sync resurrects it.
- Refresh on the `CatalogueWatcher` tick; a once-at-startup read means an artist who leaves
  the window open all day never sees anything arrive.

## 4. Adding a service the page chrome injects breaks every page test

`PageChrome` renders the bell, so every bunit harness that renders a page needs the new
service registered exactly like `ICurrentUser`. Symptoms: `Cannot provide a value for
property 'Feed'`, and in one harness a **stack overflow inside `Bunit.Htmlizer`** that
aborts the whole run mid-suite ("Passed!" with a short count + `Test Run Aborted`).

Register a quiet double in every harness that renders a page: `WorkflowPageTests`,
`PageChromeTests`, `GalleryComponentTests`, `ReleaseNotesTests` (Web.Tests, via
`AntHill.TestSupport`) and `SourceControlPageTests` (Client.Tests — use a local double;
that project does not reference TestSupport and should not pull Testcontainers in).

Bisect an aborted run by filtering per test class; the summary line lies about totals.
