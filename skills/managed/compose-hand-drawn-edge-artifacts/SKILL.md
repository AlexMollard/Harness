---
name: compose-hand-drawn-edge-artifacts
description: "Diagnose and fix visual artifacts in hand-drawn/procedural Compose UI on a real device — jagged \"torn\" outlines and bright corner spikes from jittered polylines stroked with miter joins, accent ticks that stack brush ends or float off a rounded edge, and raster art that shows a lighter box against a dark background from a low-alpha paper wash. Use when borders look rough on some screens, a panel corner shows a bright notch, or artwork's own background is visible."
---

# Hand-drawn Compose edges: artifact triage

Procedural "ink" UI (jittered outlines, brush ticks, paper-grain art) produces a
specific family of defects that compile clean, pass every test, and only show on
a real screen. Each has a measurable cause — do not eyeball-tune constants.

## 0. Safety first: pin the device when a phone is attached

An instrumented suite that seeds/clears the app database will **destroy the
user's real data** if Gradle picks their phone. Gradle runs
`connectedAndroidTest` on *every* connected device.

```bash
ANDROID_SERIAL=emulator-5554 ./gradlew :app:connectedDebugAndroidTest
```

Install/screenshot on the phone explicitly with `adb -s <serial>`. Never run the
instrumented gate unpinned while a personal device is plugged in.

## 1. Rough / "torn" outlines → polyline kinks

**Symptom:** edges read as a zig-zag or torn ribbon, worse on high-density
screens.

**Cause:** the outline joins jittered points with `lineTo`. Every point is a
sharp vertex; at ~55px facets on 450dpi that is visible as a kink.

**Fix:** curve *through* the jitter — original points become quadratic control
points, midpoints become anchors:

```kotlin
private fun smoothClosedPath(pts: FloatArray): Path {
    val n = pts.size / 2
    val path = Path()
    if (n < 3) return path
    fun x(i: Int) = pts[((i % n) + n) % n * 2]
    fun y(i: Int) = pts[((i % n) + n) % n * 2 + 1]
    var mx = (x(0) + x(1)) / 2f; var my = (y(0) + y(1)) / 2f
    path.moveTo(mx, my)
    for (i in 1..n) {
        val nx = (x(i) + x(i + 1)) / 2f; val ny = (y(i) + y(i + 1)) / 2f
        path.quadraticTo(x(i), y(i), nx, ny); mx = nx; my = ny
    }
    path.close(); return path
}
```

Apply to **every** outline kind — rect shape, circle shape, cut-corner plate,
filled dots. Grep for `lineTo(` in the theme package; each one is a suspect.

## 2. Bright notch at a corner → miter spike

**Symptom:** a small bright mark shooting past a panel's corner.

**Cause:** `Stroke()` defaults to `StrokeJoin.Miter`. A near-180° turn in a
jittered path produces a spike whose length grows without bound.

**Fix:** always stroke procedural paths with round join and cap.

```kotlin
fun stroke(px: Float) = Stroke(px, cap = StrokeCap.Round, join = StrokeJoin.Round)
```

## 3. Accent ticks that blob or float

**Symptoms:** a fat bright blob at a corner; or, once outlines are smoothed, an
accent mark detached from the edge.

**Causes:**
- A tapered tick helper is thick at `from`. Anchoring *two* ticks at the same
  corner point stacks two full-width ends on the same pixels.
- Straight ticks drawn at bounding-box coordinates cannot follow a wobbled,
  rounded corner.
- Drawing the accent on an inner child measures a different box than the element
  carrying the border.

**Fix — make the accent a stretch of the border itself**, on the *same* modifier
chain as the border:

```kotlin
val outline = when (val o = shape.createOutline(size, layoutDirection, this)) {
    is Outline.Generic -> o.path
    is Outline.Rounded -> Path().apply { addRoundRect(o.roundRect) }
    is Outline.Rectangle -> Path().apply { addRect(o.rect) }
}
val measure = PathMeasure().apply { setPath(outline, false) }
// Find where the path PASSES the corner; a fixed fraction lands mid-edge.
fun nearest(target: Offset): Float { /* sample ~96 points, argmin distance */ }
measure.getSegment(at - run / 2f, at + run / 2f, seg, true)
```

Weight matters: ~1.5dp line plus a ~4dp bleed at ~0.2 alpha reads as a mark;
2–3dp at full alpha reads as a highlighter.

## 4. Raster art shows a lighter box on a dark background

**Symptom:** a PNG with alpha still shows its canvas as a visible rectangle.

**Cause:** the "transparent" area is not transparent — it is a light ink wash at
low alpha (e.g. RGB 232,232,228 at alpha 7–17). Over a near-black UI that is a
visible film.

**Diagnose with the alpha histogram, not by eye:**

```python
from PIL import Image
a = Image.open(p).convert("RGBA").split()[3]
hist = a.histogram()   # look for a big mass at low alpha, then a GAP, then strokes
```

**Fix — soft knee above the gap**, which removes the film and keeps stroke
edges. Verify by corner-alpha mean (→0) and by counting pixels above the stroke
threshold before/after (must be unchanged):

```python
lut = [0 if v <= LOW else (v if v >= HIGH else round(HIGH*(v-LOW)/(HIGH-LOW))) for v in range(256)]
img.putalpha(a.point(lut))
```

## 5. Verification loop

1. `adb -s <phone> install -r -t app-debug.apk`, force-stop, launch, `screencap`.
2. Crop and magnify the suspect region with PIL (`Image.NEAREST`) — a full
   screenshot hides a 6px artifact.
3. Quantify when possible (most-green pixel, corner alpha mean) so "better" is
   a number, not an impression.
4. Beware heads-up notifications landing exactly over the area being judged;
   re-take before concluding anything is missing.
