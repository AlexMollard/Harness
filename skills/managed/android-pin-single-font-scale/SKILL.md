---
name: android-pin-single-font-scale
description: "Pin an Android/Compose app to one fixed text scale so the system font setting cannot reach its layouts, prove it with cross-setting geometry comparison, and delete the per-screen defences it replaces — use when an owner says \"I just want the single scale\", or when large-font defences are multiplying across screens."
---

# Pin a Compose app to one text scale

Use when an owner decides the app should ignore the system font setting, or when
per-screen large-type defences keep multiplying (a nav label cap here, a control
that stacks there) and each one is a branch nobody verifies again.

## The change

Override `LocalDensity` once, at the theme:

```kotlin
@Composable
fun AppTheme(content: @Composable () -> Unit) {
    val fixed = Density(
        density = LocalDensity.current.density,   // keep display size / DPI
        fontScale = FIXED_FONT_SCALE,             // pin ONLY the text scale
    )
    CompositionLocalProvider(LocalDensity provides fixed) {
        MaterialTheme(/* ... */, content = content)
    }
}

const val FIXED_FONT_SCALE = 1f
```

Keep `density` from the real `LocalDensity`. Overriding it too would pin display
size as well, which is a different setting and usually not what was asked for.

## Prove it — geometry across settings, not a screenshot

A screenshot at one scale proves nothing. Compare measured text-node geometry at
several system settings and expect **zero differences**:

```python
for scale in ("0.85", "1.0", "2.0"):
    sh("shell", "settings", "put", "system", "font_scale", scale)
    # force-stop, relaunch, wait, then uiautomator dump
    geom[scale] = {text: (w, h) for each text node}
diff = [k for k in shared if geom["1.0"][k] != geom[scale][k]]   # must be []
```

Include a setting **below** 1.0. A formula like `fontSize / fontScale` freezes
text at one physical size and passes an "is it capped?" check while ignoring a
user who asked for *smaller* text — that exact bug shipped before the pin.

Also re-check any control that previously had a large-type branch (a tab row
that stacked, a dial that yielded) and confirm it now renders one way at every
setting.

Always restore the device setting afterwards.

## Then delete the defences — this is the point

The pin is only worth it if the per-screen workarounds go with it. Typical
removals: font-scale label caps, `heightIn` growth added for oversized labels,
fallback layouts above a threshold, `maxLines` that varied by scale, spacers
scaled to clear a text-sized floating button, and any test pinning those
formulas.

Finish with `grep -rn "fontScale"` over the source: nothing should reference it
outside the theme. A surviving reference is a branch that can never fire.

## Say the cost out loud

Pinning the scale is an accessibility regression against Android's guidance:
enlarged system text no longer enlarges the app. Record it as an owner decision
with the tradeoff named, not as an implementation detail. It matters if the app
ever faces a store accessibility review.

## Traps

- Instrumented suites that clear app data will run on **every** attached device.
  Pin them with `ANDROID_SERIAL=emulator-5554` so a real phone's data survives.
- An empty `adb shell settings get system font_scale` usually means the device
  is gone, not that the setting is unset. Check `adb devices` before reading
  anything into an empty result.
- The instrumented gate uninstalls the app; reinstall before any UI sweep or the
  dump is of the launcher.
