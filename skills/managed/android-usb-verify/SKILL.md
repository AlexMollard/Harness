---
name: android-usb-verify
description: "Verify/debug an Android app on a USB-connected phone from this Windows box via adb — device auth, wake choreography, uiautomator-driven UI driving, screenshot proof, and the gradle/toolchain quirks (AGP 9 built-in Kotlin, wrapper invocation). Use when asked to install, launch, drive, or screenshot an Android app on a device, or when an Android build/device misbehaves."
---

# Android USB device verification (this Windows workstation)

## Toolchain facts
- SDK: `%LOCALAPPDATA%\Android\Sdk` (platform-tools\adb.exe, emulator\, build-tools\36.0.0, platforms\android-37.0). Registry `HKLM\SOFTWARE\Android Studio` may have empty SdkPath — don't trust it.
- adb restart quirk: `adb kill-server && adb devices` can show empty; poll `adb devices` a few times instead.
- Device unauthorized → RSA prompt on the phone; user must tap Allow (tick "Always allow"). Poll until `devices` shows `device` not `unauthorized`.
- Gradle: NO gradle CLI; `./gradlew` and `cmd //c gradlew.bat` both fail in this bash. Run: `java -cp gradle/wrapper/gradle-wrapper.jar org.gradle.wrapper.GradleWrapperMain <task>` from the project dir. Wrapper files: fetch from raw.githubusercontent.com/gradle/gradle/v<ver>/gradlew{,.bat} + gradle/wrapper/gradle-wrapper.jar.
- JDK: system Oracle 21 works; `C:\Program Files\Android\Android Studio\jbr\bin\java.exe` exists but is flaky to invoke from bash.
- AGP 9.x has BUILT-IN Kotlin: applying `org.jetbrains.kotlin.android` FAILS ("no longer required"). Remove it (root + app + catalog); keep `org.jetbrains.kotlin.plugin.compose` + KSP (≥2.3.1 for AGP 9). Kotlin DSL: drop `kotlin {}` compilerOptions unless needed.
- Version pins: read maven-metadata.xml from dl.google.com / repo1.maven.org for AGP (`com/android/tools/build/gradle`), Kotlin, Compose BOM, Room, Navigation, activity-compose, lifecycle. Pick latest STABLE (skip alphas).

## Device verification choreography
1. `adb shell svc power stayon usb` — screen stays awake while plugged (reduces mid-script lockscreens).
2. `adb shell input keyevent KEYCODE_WAKEUP` + `adb shell wm dismiss-keyguard` before ANY screencap; a black screenshot = screen off, re-run wake.
3. `adb logcat -c` before launches; after: `adb logcat -d *:E AndroidRuntime:E` — Samsung system noise (minksocket, keystore2, BatteryDump) is normal; only `FATAL EXCEPTION` / your package matters. Crash history: `adb logcat -b crash -d`.
4. Install: `adb install -r app.apk` (fresh state: `uninstall` first — destructive Room migrations then reseed cleanly).

## Driving Compose UIs headlessly
- Layout: `adb shell uiautomator dump /sdcard/ui.xml && adb shell cat /sdcard/ui.xml > ui.xml` (one-line XML).
- Extract tap targets by TEXT or class with sed (grep tool can't slice one-line XML): `sed 's/></>\n</g' ui.xml | sed -n 's/.*text="NAME".*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1 \2 \3 \4/p'` → tap center `((x1+x2)/2, (y1+y2)/2)`.
- Checkboxes: nodes with `checkable="true"`; unchecked = `checked="false"`. Do NOT pipe sed output into `while read` (git-bash throws I/O error 87 mid-loop and silently skips taps) — write bounds to a file first, then `while read ... done < file`, or loop over whitespace-split tokens with a for-loop + counter.
- Text entry: `input tap <field>` then `sleep 2` THEN `input text "..."` (typing races focus), `input keyevent 111` to dismiss IME between fields. Verify via screenshot read (vision) — uiautomator dump often omits Compose field values.
- Screenshots: `adb exec-out screencap -p > shot.png`; verify content with a vision read (`?q=` query), not assumptions. Watch for: lock screens, "device unauthorized", stale dumps (check byte size changes).

## Pitfalls learned
- Screen locks between commands without stayon-usb → screenshots of lock screen or all-black.
- `am start -W` after force-stop gives COLD launch status; resumed tasks reopen at last screen — user may have navigated; force-stop for a clean dashboard.
- Editing source between a background gradle run's start and finish = stale/mixed builds; land ALL file writes first, then build.
- Edit-tool anchors on files changed since last read corrupt them — after ANY failed/mis-anchored edit, prefer a full-file rewrite over a second anchored patch.
- Health Connect (androidx.health.connect:connect-client 1.1.0): record class is `BodyFatRecord` (NOT BodyFatMassRecord); permissions in manifest + rationale intent-filter; wrap reads in runCatching; gate the connect button on `HealthConnectClient.getSdkStatus`.
