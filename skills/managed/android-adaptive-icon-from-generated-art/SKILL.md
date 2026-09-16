---
name: android-adaptive-icon-from-generated-art
description: "Turn one generated emblem into a complete Android adaptive launcher icon and prove it on a real launcher — covers the 66% safe zone that silently eats edge-to-edge art, the monochrome layer whose colour is meaningless, the unkeyed-slab and sketch-frame traps, and resuming a batch under an image quota that dies mid-run. Use when replacing an app icon with model-generated art, or when an icon looks cropped or blank on device."
---

# Adaptive launcher icon from generated art

One keyed PNG becomes ~20 files. The traps are all silent: the icon still
builds, installs and launches while being wrong.

## What the manifest actually references

Check before generating anything:

```
res/mipmap-anydpi-v26/ic_launcher.xml   -> background / foreground / monochrome
res/mipmap-<bucket>/ic_launcher_foreground.png
res/mipmap-<bucket>/ic_launcher_monochrome.png
res/mipmap-<bucket>/ic_launcher{,_round}.png   # legacy, pre-26 launchers
```

Five density buckets (mdpi/hdpi/xhdpi/xxhdpi/xxxhdpi). Miss the legacy pair and
old launchers show the default robot; miss monochrome and themed icons fall
back.

## The three rules that are easy to get wrong

1. **Safe zone.** An adaptive foreground is 108dp but a launcher may mask it to
   any shape; only the centre **72dp (66%)** is guaranteed visible. Art drawn
   edge to edge loses its outer third to a circle mask. Scale the emblem into
   66% of the canvas and leave the rest transparent.
2. **Monochrome is a silhouette, not a picture.** Android tints that layer, so
   colour in it is meaningless. Write flat white on the source's alpha.
3. **Legacy bitmaps have no mask**, so they may use more of the square (~84%).

Sizes: adaptive edge = 108dp x bucket scale (mdpi 108 ... xxxhdpi 432);
legacy = 48dp x bucket scale (mdpi 48 ... xxxhdpi 192).

## Refuse bad input rather than shipping a slab

Two checks, both cheap, both catch a real failure:

- **Unkeyed source**: if >90% of pixels are alpha > 24 the ground was never
  removed — the icon will be a rectangle. Refuse.
- **Empty source**: max alpha 0. Refuse.

Density-keyed art often also carries a **paper film** at alpha 3-24 across the
whole canvas: clear corners and low opaque coverage both pass a naive check
while the icon shows a faint box. Measure the alpha histogram, cut below the
gap with a soft knee.

## Generated art carries its own frame

Image models draw a sketch border in the margin. Inside an adaptive mask that
becomes a stray arc across the icon. Crop ~7% off every edge before installing,
and say "no frame, no border" in the prompt anyway.

## Prompt for a thumbnail, not a poster

The icon is judged at 48dp. Ask for: single centred emblem, massive bold
silhouette, thick pale strokes on transparency, no frame, no text, no
background, readable at 48dp. Fine detail and lettering are wasted.

Match the emblem's value to the background drawable — a dark `ic_launcher_
background` needs pale ink, not a dark shape.

## Verify on a launcher, never on the PNG

The PNG always looks fine; the mask is what crops it.

```
adb install -r -t app-debug.apk
adb shell input keyevent KEYCODE_HOME
adb shell input swipe 540 1800 540 600 300      # open the app drawer
adb shell uiautomator dump /sdcard/ui.xml
# find text="<AppName>" bounds, screencap, crop just above that label
```

Look for: emblem inside the mask, nothing clipped at the corners, adequate
contrast against the background layer.

## Batch under a quota that dies mid-run

Image quotas run out partway. A shell loop leaves no record of which lines
landed. Drive batches from a file of `id|subject` lines with the style suffix in
a `# SUFFIX:` comment, skip ids whose output already exists, and stop on the
first `QUOTA_EXHAUSTED` with a named reason — so a later run finishes the set
instead of redrawing it. Keep the prompts in version control beside the art.

## Do not half-wire a set

If a catalogue (crests, icons, empty states) is partly generated when the quota
dies, leave it **unwired**. Four drawn items beside six procedural ones looks
worse than either set alone. Record the status next to the batch file.
