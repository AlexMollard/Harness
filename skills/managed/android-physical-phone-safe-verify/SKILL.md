---
name: android-physical-phone-safe-verify
description: "Verify Android UI changes on the owner's real phone without destroying their data or leaving their device altered — covers pinning instrumented runs to the emulator with ANDROID_SERIAL, the clamp-that-froze-the-size trap where fontSize/fontScale ignores a smaller system font, sweeping scales BELOW 1.0, and restoring every device setting you touched. Use when a phone is attached alongside an emulator, when an owner reports a visual defect on their device, or before running any Gradle instrumented task with two devices connected."
---

# Verifying on the owner's physical phone

The phone is not a test device. It holds real user data and real settings, and
Gradle does not know the difference.

## 1. Pin instrumented runs to the emulator — always

With two devices attached, `connectedDebugAndroidTest` runs on **both**. The
suite typically calls `pm clear`, `deleteDatabase`, or `DELETE FROM sessions`
to seed fixtures. On the owner's phone that is their training history, gone.

```bash
ANDROID_SERIAL=emulator-5554 ./gradlew :app:connectedDebugAndroidTest
```

Target the phone explicitly, and only for install/launch/screenshot/dump:

```bash
adb -s <PHONE_SERIAL> install -r -t app/build/outputs/apk/debug/app-debug.apk
```

Never run a Gradle instrumented task while relying on it picking the right
device.

## 2. Restore every setting you change

Record before, restore after, and print the readback as proof:

```python
orig = sh("shell","settings","get","system","font_scale").strip()
...                       # sweep
sh("shell","settings","put","system","font_scale",orig)
print("restored:", sh("shell","settings","get","system","font_scale").strip())
```

Same for `cmd locale set-app-locales <pkg> --locales ""`, `wm density`,
`settings put global debug.force_rtl`. A device left at 2.0x font or in RTL is
a defect you introduced.

## 3. The clamp that froze the size

A cap on text growth is commonly written as:

```kotlin
fontSize = style.fontSize / LocalDensity.current.fontScale   // WRONG
```

`sp` already multiplies by `fontScale`, so dividing renders **one physical size
at every setting** — including below 1.0, so a user who asked for *smaller*
text is ignored. Cap the growth instead:

```kotlin
fun labelScale(fontScale: Float) =
    if (fontScale <= 0f) 1f else minOf(fontScale, CAP) / fontScale
fontSize = style.fontSize * labelScale(LocalDensity.current.fontScale)
```

Letter spacing is declared in `sp` too — clamp it the same way or the label
keeps growing after the size stops.

## 4. Sweep below 1.0, not just above

A freeze is invisible if you only test 1.0x and up. Measure widths from the
accessibility dump at **0.85, 0.9, 1.0, 1.3, 1.5, 2.0** and check the sequence
*rises then plateaus*:

```
0.85 -> 86    0.9 -> 92    1.0 -> 102    1.3/1.5/2.0 -> 118 (capped)
```

Identical numbers across scales = frozen, not capped.

## 5. "Broken on all screens" is a hypothesis, not a location

Probe several labels on several screens at every scale before agreeing with the
scope. One frozen surface among correct ones is common; measuring is what tells
them apart, and the same numbers then prove the fix.

## 6. Read attributes off the clickable ancestor

`enabled` and `selected` sit on the clickable node; the child `TextView` holding
the label reports `enabled="true"` regardless. Walk up the XML tree:

```python
parents = {c: p for p in root.iter() for c in p}
cur = parents.get(node)
while cur is not None and cur.get("clickable") != "true":
    cur = parents.get(cur)
```

Misreading the child is the most common source of "the dump disagrees with the
code".

## 7. Heads-up notifications pollute screenshots

A banner lands exactly where a top card renders. If a screenshot shows a
"missing" element at the top, retake before diagnosing.
