---
name: android-large-type-visual-defects
description: "Find Android/Compose layout defects at large system font scales that a geometric sweep passes — sliced labels in equal-width segmented controls, a clamp that freezes text instead of capping it, a counter drawn inside a fixed-size ring, a fixed spacer meant to clear a text-sized floating button. Use when an owner says a screen \"looks bad\" at big text while an automated check reports no clipping, or before claiming a layout is font-scale safe."
---

# Large-type visual defects a geometric sweep will pass

A bounds-based sweep ("no node off-screen, nothing squished, every node grew")
measures **geometry**. It does not see sliced words, a control parked on top of
content, or text that is the right size for the wrong reason. When an owner
looking at a real screen says it "looks really bad" while the sweep is green,
**the owner is right and the sweep is answering a different question.**

Run the sweep to find frozen/overflowing nodes, then *look at screenshots* at
1.0x and 2.0x for every screen before claiming anything.

## The four defect shapes

### 1. A clamp that freezes instead of capping
```kotlin
fontSize = typography.labelMedium.fontSize / LocalDensity.current.fontScale  // WRONG
```
This renders at one physical size at **every** setting — including below 1.0, so
a user who asked for *smaller* text is ignored. Cap the growth instead:
```kotlin
fun labelScale(fontScale: Float) =
    if (fontScale <= 0f) 1f else minOf(fontScale, CAP) / fontScale
fontSize = base.fontSize * labelScale(LocalDensity.current.fontScale)
```
Detect it by measuring the same label at several scales including **below 1.0**:
identical widths at 0.9/1.0/1.5/2.0 is the signature. A cap shows
`0.85 < 0.9 < 1.0` then flat.

### 2. Equal-width segments slicing their labels
A segmented control giving each option `Modifier.weight(1f)` cannot hold three
words at 2.0x: `BODY | TRAINING | ACTIVITY` renders as `BODY | TRAININACTIVIT`,
mid-word, with no ellipsis to hint at it. Above ~1.3x lay the segments out in a
`Column` inside the same bordered group so every label stays whole. Verify the
normal scale is untouched (all labels share one y).

### 3. Text inside a fixed-size container
A counter drawn *inside* a ring (`Modifier.size(104.dp)`) or a rail
(`Modifier.height(20.dp)`) overflows its own container once the type grows.
Either let the container grow (`heightIn(min = …)`, `size(base * scale)`) or let
the decorative shape **yield** to a plain row that cannot overflow.

### 4. A fixed spacer clearing a text-sized floating button
`Spacer(Modifier.height(128.dp))` under a list clears an
`ExtendedFloatingActionButton` at 1.0x only. The button is text and grows, so
the last row ends up underneath it. Scale the clearance:
`128.dp * fontScale.coerceIn(1f, 2f)`.

## Procedure

```bash
# per scale, per screen: dump + screenshot, then READ the screenshot
adb -s "$SERIAL" shell settings put system font_scale 2.0
adb -s "$SERIAL" shell am force-stop "$PKG"
adb -s "$SERIAL" shell am start -n "$PKG/.MainActivity"
adb -s "$SERIAL" shell uiautomator dump /sdcard/ui.xml
adb -s "$SERIAL" shell screencap -p /sdcard/s.png
```
Signals worth extracting from the dump, as a *supplement* to looking:
- nodes whose text ends in `…` (ellipsised — something is hidden)
- per-label width across scales (frozen = defect 1)
- identical y for segmented labels (still a row) vs distinct y (stacked)

Always restore the scale afterwards and say which value you restored.

## Traps that void the result

- **Device gone.** `adb shell settings get system font_scale` returns an empty
  string when the device is disconnected. That is a failed call, not a device at
  default — check `adb devices` before reading anything into an empty result.
- **App uninstalled.** A Gradle instrumented run uninstalls the app afterwards,
  so a sweep straight after it drives the launcher and reports a clean screen.
  Reinstall first and assert the app is actually on screen.
- **Wrong node.** `enabled` and `selected` sit on the clickable *ancestor*; the
  child text node reports `enabled="true"` regardless. Walk up to the first
  clickable parent before believing a state read.
- **Someone else's phone.** Pin instrumented runs with `ANDROID_SERIAL=<emulator>`
  when a real phone is also attached; those suites clear app data.
