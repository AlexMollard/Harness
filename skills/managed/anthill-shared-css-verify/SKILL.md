---
name: anthill-shared-css-verify
description: "Change and verify AntHill's shared app.css (AntHill.App/wwwroot/app.css) used by both the WPF client and the Web dashboard — avoid the empty-stylesheet trap from --no-build, and prove layout rules in a headless browser when the WPF client can't be screenshotted."
---

# Verifying AntHill shared CSS changes

`src/AntHill.App/wwwroot/app.css` is **one file served to two hosts**:

- Web dashboard → `AntHill.Web/Components/App.razor`, fingerprinted via `@Assets[...]`
- WPF client → `AntHill.Client/wwwroot/index.html`, plain `_content/AntHill.App/app.css`

So a rule change lands in both. Scope deliberately.

## Trap 1: `--no-build` serves a 0-byte stylesheet

After editing `app.css`, starting the dashboard with `dotnet run --no-build` can serve a **stale fingerprinted asset with content-length 0 and 0 CSS rules** (e.g. `app.3typwxqhjs.css`). The page renders near-unstyled and looks exactly like a CSS regression you just caused.

Always rebuild Web after touching `app.css`:

```bash
dotnet build src/AntHill.Web/AntHill.Web.csproj -c Debug --nologo
```

Confirm the sheet actually loaded before trusting any measurement:

```js
for (const s of document.styleSheets)
  if (s.href?.includes('AntHill.App/app')) console.log(s.cssRules.length); // expect ~800+, not 0
```

## Trap 2: build "failures" that are file locks

A running `AntHill.Web` or `AntHill.Client` holds `AntHill.App.dll` / `AntHill.Client.exe`. You get `MSB3026`/`MSB3027`/`MSB3021` and a non-zero exit **with no `error CS` lines**. That is a lock, not a compile error, and not a test result.

```bash
# distinguish
... 2>&1 | grep -E "error CS" || echo "no compile errors - lock only"
```

Stop the holder (`hub stop web`, or `Stop-Process -Id <pid>`) before building. Restart it afterwards.

## Verifying layout without a client screenshot

The WPF client can't be screenshotted if the workstation is locked (capture returns the lock screen). The dashboard serves the *same stylesheet*, so verify rule mechanics there instead — and say plainly that it proves computed rules, not the client's appearance.

Measure at the user's real window width (check it first; a maximized studio monitor is often ~2560 CSS px, not the screenshot's pixel size):

```js
const tab = await browser.open({ url: "http://localhost:5252/settings",
                                 viewport: { width: 2560, height: 1300 } });
await tab.evaluate(`(() => {
  const body = document.querySelector('.detail-body');
  const res = { maxWidth: getComputedStyle(body).maxWidth,
                actual: Math.round(body.getBoundingClientRect().width) };
  // synthesise a row with the real child count to catch grid-track bugs
  const ul = document.createElement('ul');
  ul.className = 'file-list change-list';
  const li = document.createElement('li');
  for (let i=0;i<6;i++) li.appendChild(document.createElement('span'));
  ul.appendChild(li); body.appendChild(ul);
  const cs = getComputedStyle(li);
  res.tracks = cs.gridTemplateColumns;
  res.rows = [...new Set([...li.children].map(c => Math.round(c.getBoundingClientRect().top)))].length;
  ul.remove();
  return res;
})()`);
```

`rows > 1` means children are wrapping onto implicit grid rows.

## Grid-track count is a real bug class here

Rows are CSS grids with **fixed** tracks; a conditionally-rendered child (e.g. an Advanced-only `discard` button) silently wraps to a second row and renders as a wide empty band. Count the children a row can render — including conditional ones — and match the track count.

- `.file-list li` — 4 tracks
- `.change-list li` — 6 (name, status badge, shared/held badge, size, file count, discard)
- Full-width children (`.change-discard`, `.change-patch`) need `grid-template-columns: minmax(0, 1fr)`

## Diagrams are bounded on purpose

`.flow-svg` is capped (`max-width`) and centred. The figures are drawn in their own SVG units, so stretching one across a wide panel scales every label with it (13px text arriving ~32px). To make a diagram feel tighter, **lower the cap** — never remove it.

## Finish

Rebuild Client and Web, run both suites (`AntHill.Client.Tests`, `AntHill.Web.Tests`), and state explicitly whether a real visual check happened or only computed-rule verification.
