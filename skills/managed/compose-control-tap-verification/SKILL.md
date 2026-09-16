---
name: compose-control-tap-verification
description: "Prove a Jetpack Compose control (like button, toggle, chip) actually fires on a real device by targeting it through the accessibility hierarchy instead of guessed coordinates, and confirming the effect against backend/DB ground truth rather than the UI alone. Use when an adb tap \"does nothing\", when a count does not change after tapping, or before claiming any interactive Compose control works."
---

# Verifying a Compose control actually fires on-device

Guessed coordinates are the #1 cause of false "this control is broken" reports.
A tap that lands 20px off silently hits a sibling — often a whole-card
`clickable` that navigates away — and the evidence looks identical to a dead
button.

## 1. Never guess coordinates

Text nodes whose content is a bare number (`"3"`) are ambiguous: a stat strip
value and a like count look the same in a dump. Filtering by "small node near
the left edge" picks the wrong one.

Target by **accessibility label**, which is stable across redesigns:

```python
sh("shell","uiautomator","dump","/sdcard/ui.xml")
xml = sh("shell","cat","/sdcard/ui.xml")
for n in xml.split("<node")[1:]:
    d = re.search(r'content-desc="([^"]*)"', n)
    b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', n)
    if d and d.group(1) in ("Like", "Liked") and b:
        print(d.group(1), tuple(map(int, b.groups())), 'clickable="true"' in n)
```

Split on `<node`, not `<` — splitting on `<` shreds attributes across fragments
and every `content-desc` comes back empty.

If the filter returns nothing, **confirm which screen you are on first**. An
empty result usually means the control isn't on the current screen, not that it
lacks a label.

## 2. Expect the icon to be non-clickable

In Compose, `Modifier.clickable` usually sits on the **parent** `Row`/`Box`,
while the `Icon` only carries the `contentDescription`. So the labelled node
reports `clickable=false`:

```
('Like', (152, 1035, 194, 1077), False)   <- icon: labelled, not clickable
```

That is normal. Tap the **centre of the labelled node anyway** — the parent's
hit rect encloses it. `clickable=false` on the icon is not a defect.

Only treat it as a finding when *no* ancestor is clickable: dump the clickable
nodes and check whether any encloses the icon's bounds. If none does, the tap
target was genuinely lost in a redesign.

## 3. Confirm against ground truth, not the UI

Optimistic UI updates can show success while the network write failed, and a
rollback can hide a real failure. Read the backing store either side of the tap:

```bash
PG() { docker run --rm -i -e PGPASSWORD="$PGPW" postgres:17-alpine \
  psql "$CONN" -tAc "$1" 2>&1 | tail -1; }
echo "before: $(PG "select count(*) from session_likes where user_id='<uid>'")"
adb shell input tap <cx> <cy>; sleep 5
echo "after:  $(PG "select count(*) from session_likes where user_id='<uid>'")"
```

A toggle is stateful: read the current row first so you know whether the
expected outcome is +1 or −1. Pair the DB delta with a screenshot so you have
both the write and the render.

## 4. Attribute a "nothing happened" result correctly

Before reporting a control as broken, rule out in order:

1. **Wrong screen** — dump and check a known label is present.
2. **Missed target** — tap centre was outside the reported bounds.
3. **Hit a sibling** — took a screenshot and the app navigated somewhere else;
   that is a greedy parent `clickable`, not a dead control.
4. **Fired but failed** — UI reverted and the store is unchanged; now it is
   real, and the error copy (if any) is the next thing to check.

Only #4 is a bug in the control.
