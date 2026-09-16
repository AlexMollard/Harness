---
name: compose-selection-state-semantics
description: "Prove a Jetpack Compose app tells a screen reader WHICH control is active — nav destinations, in-screen tab rows, and filter chips that mark selection only with a gradient/border — plus the symbol-only label trap (a control announcing \"−\" or \"→\" passes a non-blank check and says nothing). Use after adding tabs, segmented controls or filter chips, or when an icon-forward UI has accessibility coverage for labels and sizes but none for state."
---

# Selection state in Compose semantics

Complements `compose-accessibility-sweep` (announceability + size floors). That
sweep asks *can this control be announced and hit*. This one asks *does the UI
say which control is currently active* — a separate axis with its own defects.

Failure mode: selection is drawn with a gradient fill and a brighter border, and
the `selected` boolean never leaves Kotlin. A screen reader then reads every tab
identically, so the user has no sense of place. On an icon-forward app whose nav
is the only chrome on every screen, that removes navigation entirely.

## 1. Three families, three roles

Audit every place a `selected`/`isOn` boolean drives only colour:

```bash
rtk grep -rn "selected\|isOn" app/src/main/kotlin/**/ui --include=*.kt | rtk grep -v "semantics"
```

| family | example | role |
|---|---|---|
| nav destinations | bottom bar slots | `Role.Tab` |
| in-screen tab rows | tab pills, segmented controls | `Role.Tab` |
| filter chips | status/rarity/group filters | `Role.Checkbox` |

Chips are **not** tabs: they narrow a list while you stay put, so they read as
checkboxes. Getting this wrong announces "tab" for something that never moves.

```kotlin
.semantics {
    role = Role.Tab
    this.selected = selected
}
```

**`this.` is load-bearing.** If the enclosing composable has its own `selected`
parameter (common: `InkSegmented(selected: T, …)`), the bare name resolves to
the parameter and you get `'val' cannot be reassigned` — or, when the types
happen to agree, a silent assignment to the wrong target.

## 2. Assert the property, not the plumbing

Check *exactly one* is selected and that it follows the tap. Asserting only
"something reports selected" passes on a component hardcoded to `true`.

```kotlin
val selected = DESTINATIONS.filter { candidate ->
    compose.onNodeWithContentDescription(candidate).fetchSemanticsNode()
        .config.valueOrNull(SemanticsProperties.Selected) == true
}
assertEquals("after opening $destination", listOf(destination), selected)
```

For chips, assert both directions — default on, others **off**, then tap and
watch the state move. The `false` assertions are what catch a blanket `true`.

## 3. The symbol-only label trap

A naive unlabelled check tests for non-blank text. `"−"`, `"→"`, `"—"` are all
non-blank and all announce as punctuation characters — the control is legible
on screen and useless to TalkBack. Sharpen the predicate:

```kotlin
private fun String.saysSomething(): Boolean = any { it.isLetterOrDigit() }
```

This found seven defects in one pass, including a 44dp stepper that passed every
size check. Note the labels must also *disambiguate*: two `"+"` glyphs on one
screen become "More" and "More added load", not two identical announcements.

Expect a **cascade** — failure lists truncate, so fixing six surfaces exposes a
seventh. Re-run until green rather than assuming the first list was complete.

## 4. Proof

Each family needs its own mutation; one shared assertion can hide two broken
components. Strip the `semantics` block, confirm the failure *names* the control,
restore, re-run green.

```
after opening Train the nav should report exactly it as selected expected:<[Train]> but was:<[]>
in Codex, opening DEEDS should leave exactly it selected expected:<[DEEDS]> but was:<[]>
the default deed filter must report itself on expected:<true> but was:<false>
```

Substring matchers are safe here without extra guarding: the assertion keys on
`Selected == true`, so a match against body prose contributes nothing and cannot
produce a false pass. Compose's `onAllNodesWithText(substring = true)` is
case-sensitive, so an uppercase pill label will not collide with lowercase prose.
