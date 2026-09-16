---
name: anthill-row-grid-track-overflow
description: "Diagnose AntHill list rows that render a stray full-width band, a stretched button, or a control floating on its own line — caused by a row grid declaring fewer tracks than the row has children (usually an Advanced-only trailing button). Use when a .file-list/.change-list/.history-list row looks broken after showing files, expanding, or enabling Advanced mode."
---

# AntHill row grids: children outnumbering tracks

## The fault

AntHill's list rows are CSS grids with **fixed track counts** in
`src/AntHill.App/wwwroot/app.css`. Razor rows conditionally render an extra
trailing control — almost always `Advanced`-only. When that control has no
track, CSS grid puts it on an **implicit row** spanning the full width.

Symptom on screen: a wide empty band under every row with one small word
floating in it, a button stretched across the whole panel, or a control
centred on its own line. It looks like a styling nit; it is a track-count bug.

Found three times in one page (source control), same cause each time:

| Row selector | Children in Advanced | Tracks declared | What showed |
|---|---|---|---|
| `.change-list li` | 6 (+ `discard`) | 5 | empty band + floating `discard` |
| `.change-list li.change-file` | 3 (+ `what changed`) | 2 | full-width stretched button |
| `.history-list li` | 5 (+ `what it changed`) | 4 | centred band per entry |

## Diagnose

1. Count children the Razor row actually renders, **including every
   `@if (Advanced)` branch** and any `else` that emits a spacer such as
   `<span class="uses-blank">`. Non-advanced rows often have one fewer.
2. Count tracks in `grid-template-columns` for that selector. Check for a
   more specific override (`.change-list li.change-file` beats
   `.change-list li`, which beats `.file-list li`).
3. Children > tracks is the bug.

## Fix

Give the trailing control its own `auto` track:

```css
.change-list li { grid-template-columns: minmax(0, 1fr) auto auto 88px 80px auto; }
```

`auto` (not `1fr`) — `1fr` is what stretches a button across the panel.

Rows that are genuinely one full-width thing (a confirmation, a diff, an
expanded sub-list) should say so rather than inherit the parent's tracks:

```css
.change-list li.change-discard,
.change-list li.change-patch { grid-template-columns: minmax(0, 1fr); }
```

## Verifying — one pitfall that will mislead you

`getComputedStyle` returns a **live** declaration. Read it *before* detaching
the node, or it reports `none` and you will conclude your fix failed:

```js
const cs = getComputedStyle(li);
const tracks = cs.gridTemplateColumns;   // read FIRST
ul.remove();                             // then detach
```

Proof a row is fixed — all children share one `top`:

```js
[...new Set([...li.children].map(c => Math.round(c.getBoundingClientRect().top)))].length === 1
```

Build a synthetic row with the exact child count Advanced renders; you do not
need the client running. For loading the stylesheet and the `--no-build`
empty-CSS trap, see `anthill-shared-css-verify`.

## Note

These grids are shared with the Web dashboard, so a track change affects both
surfaces. `AntHill.Web.Tests` renders these components and will catch markup
breakage, but **no test sees a wrapped row** — the markup is valid either way.
Only measurement or a screenshot catches it.
