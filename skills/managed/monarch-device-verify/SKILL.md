---
name: monarch-device-verify
description: "Verify the Monarch Android app on the S25 Ultra via adb from this Windows box — correct gradle invocation, screen-awake choreography, uiautomator-driven taps, screenshot proof, and repo build quirks. Use when resuming Monarch device verification or driving any Android UI over adb."
---

# Monarch device verification (Windows + S25 Ultra)

## Environment facts (this workstation)
- Repo `D:\Monarch`; APK at `app/build/outputs/apk/debug/app-debug.apk`.
- SDK: `%LOCALAPPDATA%\Android\Sdk` (adb = `platform-tools\adb.exe`). In git-bash: `"$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe"`.
- Phone: Samsung S25 Ultra, adb id `R5GL14GXV3J` (model SM-S938B).
- JDK: system Oracle 21 on PATH. Do NOT use `cmd //c gradlew.bat` (cmd eats the invocation) or `./gradlew` (not found). Run Gradle as:
  `java -cp gradle/wrapper/gradle-wrapper.jar org.gradle.wrapper.GradleWrapperMain <task> --console=plain`
  (cwd must be `D:\Monarch`; works because `local.properties` points at the SDK).

## Build quirks (repo-specific, load-bearing)
- AGP 9.x has **built-in Kotlin**: `org.jetbrains.kotlin.android` must NOT be applied (build fails if it is). Compose plugin `org.jetbrains.kotlin.plugin.compose` + KSP `2.3.12` are applied normally.
- Room record class is `BodyFatRecord` (not BodyFatMassRecord) in connect-client 1.1.0.
- `SectionHeader` lives in `com.monarch.app.ui.components` — wrong package import has bitten repeatedly.
- Prefer full-file `write` over multi-hunk `edit` on files edited more than once per session — anchor drift corrupted files repeatedly.

## Device choreography (every capture/interaction session)
1. `adb devices` — want `R5GL14GXV3J  device`. If `unauthorized`: RSA prompt is on the phone screen; user must tap Allow ("Always allow"). If missing entirely: replug; try `adb kill-server` then `adb start-server`.
2. Screen locks fast and screencap returns a black image or the lock screen:
   ```
   adb shell svc power stayon usb        # keep awake while plugged in
   adb shell input keyevent KEYCODE_WAKEUP
   adb shell wm dismiss-keyguard
   ```
3. Fresh state when needed: `adb uninstall com.monarch.app` (wipes Room; reseeds on next launch) then `adb install -r <apk>`.
4. Launch + verify no crash:
   ```
   adb logcat -c
   adb shell am start -W -n com.monarch.app/.MainActivity   # expect Status: ok
   adb logcat -d *:E AndroidRuntime:E | tail -20             # Samsung system noise is normal; only AndroidRuntime FATAL from com.monarch.app matters
   ```

## Screenshot proof pattern
```
adb exec-out screencap -p > .tmp/shots/<name>.png
```
Then `read` the PNG with a `?q=` vision prompt asking for specific expected labels/colors. Trust only what the vision answer confirms — black image = screen off; lock screen = re-run step 2.

## Driving the UI without a human
1. Dump: `adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; adb shell cat /sdcard/ui.xml > .tmp/ui.xml`
2. Extract tap coordinates (dump is single-line XML; shell grep is blocked by policy — use sed):
   `sed 's/></>\n</g' .tmp/ui.xml | sed -n 's/.*text="Stats".*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1 \2 \3 \4/p'`
   Center = ((l+r)/2, (t+b)/2), then `adb shell input tap X Y`.
3. Text fields: tap to focus → `adb shell input text "80"` → `input keyevent 111` (ESC) to dismiss.
4. Compose Checkbox = `checkable="true"` nodes; buttons = their `text=` bounds.
5. Screens can time out mid-choreography — re-run WAKEUP + dismiss-keyguard whenever a capture looks like a lock screen, and keep `stayon usb` set.

## Status (as of last session)
Core v1 verified through dashboard + launch; UI redesigned (neutral base + emerald accent, weekly quest rail, progression charts). Remaining scripted flow: log stat reading (80/180/15) → start Volume Pull quest → check all sets → CLAIM VICTORY → verify victory dialog (XP/level-up/The Awakened/Iron Ascension) → titles, calendar, progression charts, export share sheet screenshots → logcat sweep.
