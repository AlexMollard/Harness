---
name: compose-layout-device-traps
description: "Diagnose Jetpack Compose layout defects that compile clean, pass unit tests, and only appear on a real device — content stacking inside a Box-slot container (PullToRefreshBox/Scaffold), LazyColumn-in-verticalScroll crashes, chip rows wrapping one letter per line, keyboard covering inputs, and adb taps landing on the IME. Use when a screen \"renders wrong\" but the build is green, or before trusting an agent's \"my file compiles\" claim about UI."
---

# Compose layout defects the compiler cannot see

Scope: **layout/measure/gesture defects that only appear on a device.** Green build + green tests + an agent reporting "zero errors in my file" says nothing about whether the screen is correct.

Sibling skills — do not duplicate them:
- **Wiring** defects (screens built but never routed, defaults that hide missing wiring, `valueOf` crashes from seed data, missing Room migrations) → `compose-feature-wiring-audit`.
- **adb mechanics** (device auth, wake, uiautomator driving, screenshots, gradle quirks) → `android-usb-verify`.

## The rule that catches all of these

A screenshot is the only proof. Run the flow, capture, and *read the image* — do not accept a `uiautomator dump` alone, because a dump lists nodes that are stacked, clipped, or behind the keyboard as though they render fine.

```bash
ADB="$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe"
"$ADB" logcat -c -b crash                      # clear FIRST or you re-read an old crash
"$ADB" install -r app/build/outputs/apk/debug/app-debug.apk
"$ADB" shell am force-stop <pkg>; "$ADB" shell am start -W -n <pkg>/.MainActivity
sleep 6
echo "FATAL: $("$ADB" logcat -d -b crash | grep -c 'FATAL EXCEPTION')  pid: $("$ADB" shell pidof <pkg>)"
"$ADB" exec-out screencap -p > shot.png
```
`FATAL: 0` **and** a live pid **and** a screenshot you looked at. Any one alone is insufficient.

## Trap 1 — Box-slot containers stack their children

`PullToRefreshBox`, `Scaffold`'s content, `Box` — their content slot is a **`BoxScope`**, not a column. Children emitted directly into it all draw at the same origin.

Symptom: only the last-drawn element is visible; earlier elements look "missing" or "empty" (a podium renders its plinths but the names appear blank because a later card is painted over them). Dumps still list every node, so automation reports success.

```kotlin
PullToRefreshBox(isRefreshing = …, onRefresh = …) {
    Column(Modifier.fillMaxWidth()) {   // REQUIRED: the slot is a Box
        Header(); Rows()
    }
}
```

## Trap 2 — LazyColumn inside a verticalScroll parent

Crashes at measure time:
`IllegalStateException: Vertically scrollable component was measured with an infinity maximum height constraints`

Fix structurally; do **not** drop laziness (that defeats the point for a growing list). The lazy list owns the scrolling, and the caller passes a bounded modifier:

```kotlin
// parent: no verticalScroll on this branch
Column(Modifier.fillMaxSize()) {
    Header()
    MyList(modifier = Modifier.fillMaxWidth().weight(1f))   // bounded height
}
// child
@Composable fun MyList(modifier: Modifier = Modifier.fillMaxSize()) { LazyColumn(modifier) { … } }
```
When one tab of a screen needs a lazy list and the others scroll, branch the modifier:
`.then(if (lazyTab) Modifier else Modifier.verticalScroll(rememberScrollState()))`.

## Trap 3 — chip rows overflow instead of scrolling

A fixed `Row` of filter chips silently wraps each label to one letter per line off the right edge (`CLIMBING` → `C/L/I/M…`) once the set grows.

```kotlin
Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), …) { … }
Text(label, maxLines = 1, softWrap = false)   // on the chip's own Text
```
Also check for **duplicated filter axes**: if two rails end up offering the same values (e.g. a muscle-group enum that grew to include activity groups already present in a category rail), the fix is to narrow one rail, not to scroll both.

## Trap 4 — keyboard covers the input, and eats your taps

With `enableEdgeToEdge()` the IME overlays content even with `windowSoftInputMode="adjustResize"`.

```kotlin
Column(
    Modifier.fillMaxSize()
        .imePadding()                               // BEFORE the scroll modifier
        .verticalScroll(rememberScrollState())
)
```
Sweep **every** screen with a text field, not just the reported one — grep for `BasicTextField|OutlinedTextField|TextField(` and compare against files containing `imePadding`.

A submit button below the field can still sit under the keyboard. Wire the IME action so the entry is never stranded:

```kotlin
keyboardOptions = KeyboardOptions(keyboardType = …, imeAction = ImeAction.Done),
keyboardActions = KeyboardActions(onDone = { submit() }),
```

**Automation corollary:** `uiautomator dump` reports app-window coordinates, but the IME floats above them. A scripted tap at a button's dumped `y` lands on a *keypad key* instead — symptom: a typed `84.5` mysteriously becomes `84.52` (it hit `2`). Dismiss the IME or use the Done action before tapping anything low on screen.

## Trap 5 — never interpolate an object into Text

`"$row.lifetimeStrength"` interpolates the whole data class `toString()` then appends the literal text `.lifetimeStrength`. It compiles, and prints `LeaderboardRow(userId=0ce6…, …).lifetimeStrength` on screen. Always `"${row.lifetimeStrength}"`, and grep for `"\$[a-z]+\.` after any UI agent's work.

## Verification checklist before believing a UI is done

1. Screenshot read by eye — not a dump, not a compile.
2. `FATAL: 0` from a **cleared** crash buffer, plus a live pid.
3. Count what should render vs what does (header says "5 hunters ranked" → count five).
4. Grep the diff for `"\$[a-z]+\.`, new `LazyColumn`, new `Row(` chip rails, new text fields.
