---
name: compose-dialog-density-override-leak
description: "Prove a CompositionLocal override (LocalDensity/font scale, locale, layout direction) actually reaches Compose Dialog and popup content — covers the leak where a theme-level pin holds on every screen but not inside a Dialog's own window, and the geometry comparison that exposes it. Use when pinning a fixed text scale, when a dialog ignores a theme-level override, or before claiming an app-wide composition local is applied everywhere."
---

# Compose dialog density / CompositionLocal override leak

A `CompositionLocalProvider` installed in the app theme covers **the tree it is
provided to, and nothing else**. A Compose `Dialog` (and `Popup`) hosts its
content in its **own window and its own composition**, which re-provides the
platform values — `LocalDensity`, and with it `fontScale`.

So an app that pins a fixed text scale in its theme still has every dialog
following the system font setting, while every screen behind the dialog holds
still. This is invisible in code review and invisible to a sweep of the
activity's screens.

## The symptom, measured

With the app pinned at `fontScale = 1f` in the theme:

```
weigh-in dialog "LOG BODY READING":   system 1.0x -> 409px    system 2.0x -> 756px
every screen behind it:               identical at both
```

## Procedure

1. **Pin at the theme**

   ```kotlin
   val fixed = Density(density = LocalDensity.current.density, fontScale = FIXED_FONT_SCALE)
   CompositionLocalProvider(LocalDensity provides fixed) { MaterialTheme(...) { content() } }
   ```

2. **Re-pin inside every dialog.** Wrap the dialog's content, not the call:

   ```kotlin
   @Composable
   fun FixedTextScale(content: @Composable () -> Unit) {
       val current = LocalDensity.current
       if (current.fontScale == FIXED_FONT_SCALE) { content(); return }
       CompositionLocalProvider(
           LocalDensity provides Density(current.density, FIXED_FONT_SCALE),
           content = content,
       )
   }

   Dialog(onDismissRequest = ...) { FixedTextScale { /* content */ } }
   ```

3. **Prove it by cross-setting geometry**, on a device, for the dialog itself —
   not for the screens behind it:

   ```python
   # for scale in ("1.0", "2.0"): set it, relaunch, OPEN THE DIALOG, dump
   adb shell settings put system font_scale 2.0
   adb shell uiautomator dump /sdcard/ui.xml
   # compare text-node width/height per label between the two runs
   ```

   Pass condition is **zero differing nodes** for labels inside the dialog.
   Comparing only the host screen's nodes passes while the dialog still leaks.

4. **Guard the omission.** The next dialog added will forget the wrapper, and
   nothing fails. A source scan is justified here for the same reason as any
   "no machined geometry" scan — the violation is textual and otherwise only
   visible by changing a system setting and looking:

   ```kotlin
   val offenders = sources.filter { f ->
       val t = f.readText()
       Regex("""\n\s*Dialog\(""").containsMatchIn(t) && !t.contains("FixedTextScale")
   }
   assertEquals(emptyList<String>(), offenders.map { it.name })
   ```

   **Mutation-prove it**: remove the wrapper from one dialog and confirm the
   scan fails by name. A scan that has never failed proves nothing.

## Traps

- **"0 differing nodes" on the screens is not proof.** That sweep walks the
  activity's composition; the dialog is a different window. The result is true
  and irrelevant.
- Same leak applies to any composition local you rely on app-wide: layout
  direction, locale, custom theme locals. If a dialog must honour it, it must
  be re-provided inside the dialog.
- Wrap the **content**, not the `Dialog(...)` call — providing outside the
  call changes nothing, because the new composition starts inside it.
- When deleting per-screen large-font defences after pinning, delete them
  rather than leaving branches that can no longer fire; then `grep` for the
  local (`fontScale`) to confirm nothing outside the theme still reads it.
