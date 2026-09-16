---
name: android-font-scale-verification
description: "Verify an Android/Compose app survives large system font scales (1.5x, 2.0x) — sentinel-string checks that catch a primary button measured at zero height, cross-scale width comparison that exposes sp-tracking still scaling after fontSize is clamped, the scroll-aware rule that separates real defects from below-the-fold false positives, and why an unvalidated geometric detector reporting \"0 issues\" proves nothing. Use when checking large-text accessibility, when labels wrap mid-word or clip, or before claiming a layout is font-scale safe."
---

# Android font-scale verification

Large-text users run 1.3–2.0x. Layouts that look fine at 1.0x fail in ways a
screenshot will not show you. Work these checks in order; each is one command.

```bash
adb shell settings put system font_scale 2.0
adb shell am force-stop <pkg>
adb shell monkey -p <pkg> -c android.intent.category.LAUNCHER 1
adb shell uiautomator dump /sdcard/ui.xml && adb shell cat /sdcard/ui.xml
# ALWAYS restore when done
adb shell settings put system font_scale 1.0
```

## 0. The install must be fresh, and you must see it say so

An instrumented test run **uninstalls the app**. A sweep right after a gate
reports every screen "unreachable", and `install >/dev/null` hides the failure.
Never silence install output; confirm the nav bar exists in the dump before
trusting any measurement.

## 1. Sentinel strings find what the eye misses

The highest-value check is the cheapest: assert the primary control's text is
present in the dump at each scale.

```python
for s in ("ACCEPT QUEST", "LOG WEIGHT", "SIGN IN"):
    print("OK" if s in dump else "MISSING", s)
```

A real case: nine full-screen visual inspections at 1.5x and 2.0x all passed
while the app's primary button **did not exist** at 2.0x. One string check
caught it immediately.

## 2. A missing control is usually measurement order, not overflow

In a Compose `Column`, **unweighted children are measured in declaration
order** and the flexible child takes what is left. If the header is unweighted
and the CTA is declared last, a tall header consumes the container and the
button is measured at **zero height** — not pushed off screen, simply gone.

Fix: make the CTA the *only* unweighted child.

```kotlin
Column {                                   // the card
    Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState())) {
        Title(); Note(); Rows()            // everything that may shrink
    }
    PrimaryButton()                        // unweighted -> measured first
}
```

Verify by geometry, not presence alone: the button's bottom must sit above the
nav bar's top (both come from the dump).

## 3. Clamping fontSize alone is not clamping

`fontSize` **and** `letterSpacing` are both declared in `sp`. Clamp only the
first and the label still grows ~10% at 1.5x, ~20% at 2.0x.

```kotlin
fontSize = style.fontSize / LocalDensity.current.fontScale,
letterSpacing = style.letterSpacing / LocalDensity.current.fontScale,
```

Prove it by comparing the **same label's width across scales** — they must be
identical, not merely "still fitting". A measured progression like
`102 -> 112 -> 123px` is the tell; identical widths at 1.0/1.5/2.0x is the
proof. Pinning nav labels is a defensible tradeoff (the icon and the
`contentDescription` carry the meaning, and neither scales) — argue it in a
comment rather than doing it silently.

## 4. Absence only matters on a screen that does not scroll

Before calling a missing sentinel a defect, swipe and re-dump:

```python
for i in range(8):
    if mark in dump(): break
    adb("shell","input","swipe","540","1700","540","800","250")
```

Two "regressions" found this way were both reachable after one swipe. Only
non-scrolling screens (typically the dashboard) make first-viewport absence a
real failure.

## 5. Validate any geometric detector against a known-bad build

A heuristic that has never fired proves nothing. Revert the fix, rebuild, and
confirm the detector flags it.

A width-based squish detector (`w < 90 && h > 2w`) reported **0 issues** on a
build whose nav labels demonstrably wrapped mid-word — the wrapped labels
measured `154x162px`, far outside the threshold. The discriminating signal was
the aspect ratio of a single-word label: **1.05 broken vs 0.29–0.40 fixed**.

## 6. Mutation-prove the fix

Rebuild the pre-fix source and confirm the symptom returns:

```bash
git show HEAD~2:path/to/Screen.kt > .tmp/prefix.kt   # repo-local, not /tmp
```

`/tmp` is not reliably shared between git-bash and a Python subprocess on
Windows; use a repo-local `.tmp/`. Restore afterwards and confirm
`git status` is clean — that also proves the restore was byte-exact.

## What to record

State what was measured and what was not. No instrumented suite guards this:
tests run at the device's own font scale, so a regression needs the manual
sweep. Where large text forces a real product tradeoff (e.g. a card that fits
its CTA but not its list), present costed options to the owner instead of
choosing silently.
