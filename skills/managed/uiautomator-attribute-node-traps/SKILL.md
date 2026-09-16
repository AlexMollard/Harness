---
name: uiautomator-attribute-node-traps
description: "Verify a Compose control's enabled/selected/checked state on an Android device from a uiautomator dump without misreading it — the attribute sits on the clickable ancestor while the label sits on a child that reports the opposite, plus the control run that proves a forced device setting actually took effect. Use when a dump disagrees with the code, when a validation gate or toggle \"looks wrong on device\", or before claiming any on-device state check passed."
---

# Reading state attributes out of a uiautomator dump

A dump is a tree. Compose puts **state** (`enabled`, `selected`, `checked`) on the
node that owns the semantics — usually the clickable ancestor — and the **label**
on a child `TextView`. A regex over the whole XML that matches on the label and
then grabs the nearest attribute reads the *child*, which reports
`enabled="true"` / `selected="false"` no matter what the control is doing.

Symptom: the dump contradicts code you have just read, in the direction of
"nothing is ever disabled / nothing is ever selected".

## Procedure

1. Dump once and parse it as XML, not as text:

```python
import xml.etree.ElementTree as ET, subprocess, os, re
ADB = os.path.expandvars(r"%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe")
def sh(*a): return subprocess.run([ADB,"-s",SERIAL,*a],capture_output=True,text=True,errors="replace").stdout
def dump():
    sh("shell","uiautomator","dump","/sdcard/ui.xml"); return sh("shell","cat","/sdcard/ui.xml")
```

2. Walk **up** from the labelled node to the first clickable ancestor and read the
   attribute there:

```python
def state_of(label, attr="enabled"):
    root = ET.fromstring(dump())
    parents = {c: p for p in root.iter() for c in p}
    for n in root.iter("node"):
        if n.get("text") == label:
            cur = parents.get(n)
            while cur is not None:
                if cur.get("clickable") == "true":
                    return cur.get(attr)
                cur = parents.get(cur)
    return "absent"
```

3. Print the ancestor chain once when a result surprises you — it shows
   immediately which node carries what:

```python
chain = [(c.get("class","").split(".")[-1], c.get("clickable"), c.get("enabled"), (c.get("text") or "")[:12])]
```

## Prove the check can fail

A state check that only ever reports the good value is worthless. Drive the
control to both states in one run and print both:

| entry | expected |
|---|---|
| empty required field | disabled |
| valid value | enabled |
| out-of-range value | **disabled** |
| back to valid | enabled |

If every row reads the same, the measurement is wrong before the app is.

## The same trap for forced device settings

Before sweeping screens under a forced configuration, prove the forcing worked
by comparing a geometry probe against the unforced run:

- `settings put global debug.force_rtl 1` frequently does **nothing**.
- A per-app locale (`cmd locale set-app-locales <pkg> --locales ar-XB`) is
  filtered against the locales the APK ships; without
  `isPseudoLocalesEnabled = true` on the debug build type it silently falls back
  to English and the sweep measures an LTR layout while reporting no problems.

Control: capture one element's `x1` in both runs. Byte-identical positions mean
the configuration never changed and any "clean sweep" is vacuous.

```
HUNTER  ltr=(195,479)  rtl=(601,885)   <- mirrored, the sweep is real
HUNTER  ltr=(195,479)  rtl=(195,479)   <- nothing happened, discard the result
```

## Related traps worth the same suspicion

- **A negative grep proves nothing** until the positive case is located. Search
  for the setter the UI actually calls, not for an enum's literal values — a
  control built from `Enum.entries` spells none of them.
- **Instrumented Gradle runs uninstall the app afterwards**, so a sweep started
  straight after one drives a launcher, not your app. Check
  `pm path <pkg>` first, and seed live-database fixtures with `am instrument`
  rather than the Gradle task.
- Scroll to the control before judging absence: a dump only contains what is
  currently composed.
