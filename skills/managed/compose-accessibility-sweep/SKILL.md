---
name: compose-accessibility-sweep
description: "Prove a Jetpack Compose app is announceable and hittable with an instrumented semantics sweep — covers the sibling-placeholder BasicTextField that announces nothing, the two-tier size floor (WCAG 24dp everywhere / Material 48dp for nav), sweeping the surfaces behind each tab rather than only the front door, and the two traps that make such a sweep lie: silently skipped surfaces passing vacuously, and clipped bounds misreading a half-scrolled control as too small. Use when adding accessibility coverage to an icon-forward UI, or when a control looks fine but a screen reader lands on nothing."
---

# Compose accessibility sweep

Drive every surface through the semantics tree and assert two things per
control: an accessibility service can **announce** it, and it is big enough to
**hit**. Both are measured, never eyeballed.

## The two defects this finds most often

**1. A `BasicTextField` whose placeholder is a sibling `Text`.** The field looks
labelled on screen and announces *nothing* — a screen reader lands on an
unlabelled input. Label the field; leave the decorative icon `null`, because
naming both makes TalkBack read it twice.

```kotlin
BasicTextField(
    modifier = Modifier
        .fillMaxWidth()
        .heightIn(min = 24.dp)              // one line of text measures ~20dp
        .semantics { contentDescription = "Search movements" },
)
if (query.isEmpty()) Text("search movements")   // sibling placeholder
```

**2. Controls under the size floor.** Use a two-tier policy and say so in the
test, or reviewers will argue about it forever:

- **WCAG 2.5.8 AA = 24dp** for *every* tappable control.
- **Material 48dp** for the nav bar only — the one control on every screen.
- The 24–48 band on dense in-panel chips is a **layout decision, not a defect**.
  Compose clips touch delivery to the parent's bounds, so widening a child
  inside a padded panel changes nothing measurable.

Typical fix for chips: `.heightIn(min = 32.dp)` — Material chip height, costs a
few density pixels, no relayout.

## Sweep behind each tab, not just the front door

Top-level destinations are the least likely place to find anything. The dense
screens — a live session, an editor, a picker — are where unlabelled glyphs
hide. Drive `destination -> sub-surface` pairs.

## Three traps that make the sweep lie

**Vacuous skips.** Skipping a surface whose label doesn't match is right for a
missing feature and fatal as a silent default: every assertion then passes on an
empty node set. Assert the surfaces were actually *reached*, and name the
missing ones:

```kotlin
assertEquals(
    "surfaces the sweep could not reach: ${ALL.map { "${it.first}/${it.second}" } - visited.toSet()}",
    ALL.size, visited.size,
)
```

This is what exposes a settings screen that was never opened at all.

**Clipped bounds ≠ target size.** `boundsInRoot` is clipped to the *visible*
region, so a half-scrolled 40dp button measures 23dp and reads as a defect. Use
`node.size` — the laid-out size. A test that fails on scroll position gets
deleted within a week.

**Icon-only entry points.** A settings gear has a *content description*, not
text. Match text first, then description, or the surface is silently skipped:

```kotlin
private fun openSurface(label: String): Boolean {
    val byText = compose.onAllNodesWithText(label, substring = true)
    if (byText.fetchSemanticsNodes().isNotEmpty()) { byText.onFirst().performClick(); return true }
    val byDesc = compose.onAllNodesWithContentDescription(label, substring = true)
    if (byDesc.fetchSemanticsNodes().isNotEmpty()) { byDesc.onFirst().performClick(); return true }
    return false
}
```

## Ordering and navigation

- Some surfaces **replace the nav bar**; walk back until it returns rather than
  assuming it is there: press `onBackPressedDispatcher` until a known nav
  content description resolves (cap the retries).
- Put **destructive surfaces last** — starting a session leaves a live trial
  whose abandon prompt sits between the sweep and the nav bar.

## Name the control in failures

`178x23 dp` sends the next reader hunting across every screen. Build an
identifier from `node.config`: `SemanticsProperties.Text`, then
`ContentDescription`, else `"unnamed"` → `"CONNECT & SYNC" 178x23 dp`.

## Prove it bites

Revert each fix and confirm the matching assertion fails — label removed →
`role=null at Rect(...)`; height floor removed → `"PULL" 45x23 dp`. An
accessibility test that has never failed has never been tested.

## Environment notes

- The clock is often held (`mainClock.advanceTimeBy`) because ink/gradient
  animations never idle; `ComposeNotIdleException` otherwise.
- Instrumented runs **uninstall the app**; reinstall before driving the device
  by hand afterwards.
- `uiautomator` dumps do **not** expose Compose's merged click nodes — measure
  from the semantics tree, not the flat XML dump.
