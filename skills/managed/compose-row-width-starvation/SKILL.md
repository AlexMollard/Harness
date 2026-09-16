---
name: compose-row-width-starvation
description: "Diagnose a Jetpack Compose Row whose children render as one-letter-per-line labels, zero-width steppers, or vanished controls — caused by an unweighted sibling calling fillMaxWidth() (or otherwise inflexible) inside the same Row, starving the weight(1f) children. Use when on-device controls collapse but the code compiles and the Row \"looks correct\", or when uiautomator bounds disagree with what renders."
---

# Compose row width starvation

A `Row` where one child is **inflexible and greedy** (typically `Modifier.fillMaxWidth()`, or a
fixed `width()` larger than the slack) measures that child first. Every `weight(1f)` sibling
divides what is left — which can be **zero**.

## Signature on device

- Text labels wrap **one character per line** (`L` / `O` / `A` / `D` stacked vertically).
- Steppers, fields, or icon pairs collapse to slivers or disappear entirely.
- The build is green, unit tests pass, and the `Row` body reads as correct.

## Locate it

Read the Row's **whole child list**, not just the children that look wrong. The culprit is the
sibling nobody suspects, often appended later by a feature that was meant to sit *below* the row:

```kotlin
Row(Modifier.fillMaxWidth()) {
    Column(Modifier.weight(1f)) { /* starved */ }
    Column(Modifier.weight(1f)) { /* starved */ }
    SomeBadge()            // <- internally Row(Modifier.fillMaxWidth()), takes everything
}
```

Grep the suspect child's own composable for `fillMaxWidth()` / `width(`:

```
grep pattern: "private fun <ChildName>|fillMaxWidth\(|width\("
```

A comment on the offending call site saying the element belongs "under" / "below" the row is
strong confirmation the structure, not the sizing, is wrong.

## Fix structurally, not with sizing hacks

Wrap in a `Column` and move the greedy child out of the `Row`. Carry the outer modifiers
(`fillMaxWidth`, `alpha`, `padding`) up to the `Column` so behaviour is unchanged:

```kotlin
Column(Modifier.fillMaxWidth().alpha(..).padding(..)) {
    Row(Modifier.fillMaxWidth(), ...) { /* controls only */ }
    SomeBadge()
}
```

Do **not** "fix" it by shrinking the badge, adding `weight` to the greedy child, or setting
`maxLines` on the starved labels — those hide the measurement bug and it returns with the next
label change.

## Verify

Reinstall, drive to the screen, and compare **child widths** before/after via uiautomator:

```python
# widths of the row's children; starved children report w≈0 or a 6px-tall text node
for b, txt in nodes(xml, r'text="[^"]{1,60}"'):
    print(repr(txt), "w=", b[2]-b[0], b)
```

Expect starved children to go from absent/slivers to real widths (e.g. a stepper's
`−` `value` `+` each reporting ~100px+).

## Trust the screenshot over uiautomator geometry

uiautomator can report nonsense bounds for a text node (e.g. a title 6px tall, hit-rects
overlapping in Y) **while the screen renders correctly**. Confirmed: such bounds persisted
unchanged after a fix whose screenshot was visibly correct. Treat odd bounds as a reporting
artifact and adjudicate with `exec-out screencap`, not the XML.

## Related but different

Children **stacking at a shared origin** (elements drawn over each other) is a different bug:
content emitted straight into a `Box`-style content slot, e.g. `PullToRefreshBox`, whose slot is
a `BoxScope`. Fix by wrapping that content in a `Column`. Starvation squeezes widths; slot
stacking overlays whole elements.
