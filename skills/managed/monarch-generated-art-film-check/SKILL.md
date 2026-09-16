---
name: monarch-generated-art-film-check
description: "Generate, verify and wire hand-drawn ink artwork for the Monarch Android app (D:\\Monarch) with tools/art.py — covers the low-alpha paper film that density keying leaves behind and which reads as a lighter box on a dark panel, the model's own sketch frame in the margin, the resumable batch runner for a quota that dies mid-set, and the rule against half-wiring a catalogue. Use when adding app artwork, when generated art shows a background box, or when the generator's own checks report OK but the art looks wrong on device."
---

# Monarch generated art: the film, the frame, and the quota

`tools/art.py` drives gemini-3.1-flash-image through omp's `google-antigravity`
provider (auth: `omp token google-antigravity`; transport: headroom on
127.0.0.1:8787; the Gemini body must be nested under `"request"`).

## The failure this skill exists for

`--alpha` keys by **density**: ink darkness becomes opacity. Blank paper is not
perfectly white, so it lands at **alpha 3–24 instead of 0** — measured at
**78–91% of the canvas**. Invisible when you view the PNG alone; on the app's
near-black panel (`Abyss = 0xFF0C0C0B`) it is a clearly visible lighter
rectangle the exact size of the image. Three pieces shipped that way and the
owner caught it on a real phone.

`backdrop_audit` did **not** catch it: it only checked corner alpha > 32 and
"opaque" coverage > 180. A canvas entirely at alpha 3–24 passes both.

## Verify every generated asset

```python
from PIL import Image
im = Image.open(path).convert("RGBA")
h = im.split()[3].histogram(); tot = sum(h)
print(f"zero={100*h[0]/tot:.1f}%  film3-24={100*sum(h[3:25])/tot:.1f}%  ink>=41={100*sum(h[41:])/tot:.1f}%")
```

- **film > 5%** → the wash is still there, whatever the tool reported.
- Healthy output: film ≈ 0–3%, zero ≈ 75%+, ink 5–25%.

The histogram shows a clean gap at alpha 25–40 between film and real strokes,
which is why a soft knee (0 below 20, ramp to 40, unchanged above) removes the
film without cutting the drawing's feathered edges. This now runs inside
`postprocess()` via `cut_paper_film()`, and `backdrop_audit` reports
`(N% ink, M% film)`.

To rescue **already-shipped** art, apply the same LUT to the PNG in place and
confirm stroke pixel count (alpha ≥ 41) is unchanged.

## The model draws its own frame

Generated pieces routinely include a faint sketched rectangle in the margin —
the same "box against the dark background" by another route. Crop ~7% off each
edge before shipping, then re-check the histogram.

## Batch + quota

The image quota dies mid-batch with `QUOTA_EXHAUSTED` from
`cloudcode-pa.googleapis.com` (~9–10 images per reset observed). A shell loop
loses its place, so use the resumable runner:

```
python tools/art_batches/run.py tools/art_batches/<batch>.txt [outdir]
```

Batch line format `id|subject`; the shared style suffix lives in a
`# SUFFIX:` comment so each prompt stays in version control beside its art. The
runner skips ids whose PNG already exists and stops with a named reason.

## Rules that are not negotiable

- **Never half-wire a catalogue.** 4 drawn crests beside 6 procedural ones
  looks worse than either set. Generate the full set, then wire.
- **Size the prompt to the render size.** Crests render at 34dp in the player
  sigil: ask for "bold thick strokes, massive simple silhouette, no fine
  detail, no frame, no border". Fine detail is mush at that size.
- **Judge on a dark contact sheet**, not on a white viewer: composite onto
  `(12,12,11)` before deciding.
- Verify on device afterwards; the emulator and phone render ink differently.

## Placement

Assets go in `app/src/main/res/drawable-nodpi/art_empty_*.png`, drawn with
`Image(painterResource(...), alpha = 0.55f)` at an explicit `.size(...)` —
`fillMaxWidth` + `heightIn` lets the intrinsic size win and renders postage-stamp
small.
