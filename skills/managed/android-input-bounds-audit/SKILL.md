---
name: android-input-bounds-audit
description: "Audit an Android/Compose app's user-input trust boundaries for missing bounds — numeric fields checked only for positivity that poison derived maths (negative lean mass, negative BMR), text fields with no cap, and client caps that must match server CHECK constraints — then prove each gate on device by reading the clickable ancestor's enabled state. Use when adding any typed input, before shipping a form, or when a derived metric can show an absurd value without crashing."
---

# Android input bounds audit

Finds the input defects that never crash: a typo reaches derived maths and the
app reports nonsense as fact. Ordered cheapest-first.

## 1. Enumerate every input, don't recall them

```bash
python - <<'PY'
import pathlib, re
for p in sorted(pathlib.Path("app/src/main/kotlin/<pkg>/ui").rglob("*.kt")):
    s = p.read_text(encoding="utf-8")
    for m in re.finditer(r"onValueChange\s*=\s*\{([^}]{0,90})\}", s):
        body = " ".join(m.group(1).split())
        capped = any(k in body for k in ("take(", "coerce", "filter"))
        print(f"{'ok ' if capped else 'RAW'} {p.name}:{s[:m.start()].count(chr(10))+1} {body[:78]}")
PY
```

Also sweep parsing sites: `grep -rn "toDoubleOrNull\|toIntOrNull"`. A field
validated only as `> 0.0` is the headline defect class.

## 2. Compute what the unbounded value does downstream

Do NOT argue from plausibility — run the formula:

```bash
python -c "w=80.0; bf=500.0; lean=w*(1-bf/100); print(lean, 370+21.6*lean)"
# lean mass -320 kg, BMR -6542 kcal  -> shown to the user as a fact
```

If the number is merely large, it may be acceptable. If it is *negative or
NaN*, the field is a defect regardless of how unlikely the typo is.

## 3. Bound it in ONE place

Create a single limits object with wide, defensible ranges and a comment giving
the real-world anchor (tallest human 272 cm, etc.). Wide enough to accept
records, narrow enough to catch a slipped decimal or a unit mix-up.

Wire it at three levels:
- the screen's `enabled =` gate,
- the repository (defence in depth for future callers),
- the **import path** — but *filter* implausible rows rather than `require`,
  because an old archive may carry a typo and losing one row beats losing the
  whole restore.

Never leave the same literal in two files; that duplication is the bug this
object exists to prevent.

## 4. Client caps must equal server CHECK constraints

Parse the migrations and assert against the shared constants, so a tightened
constraint fails a test instead of a sync that dies forever inside
`runCatching`:

```kotlin
Regex("""char_length\((?:trim\()?$column\)?\)\s*<=\s*(\d+)""")
Regex("""char_length\(trim\($column\)\)\s*between\s*(\d+)\s*and\s*(\d+)""")
```

Mutation-prove from the *server* side: tighten a ceiling in the SQL and confirm
the test names that column.

Watch for the false alarm: two similarly-named fields may be different columns
(a device-local profile name vs the cloud handle). Trace what the push actually
sends before calling it a mismatch.

## 5. Prove the gate on device — read the RIGHT node

`enabled` sits on the **clickable ancestor**, not on the button's text node,
which reports `enabled="true"` regardless. Same trap as `selected` on segmented
controls. Walk the ancestor chain:

```python
root = ET.fromstring(dump); parents = {c: p for p in root.iter() for c in p}
for n in root.iter("node"):
    if n.get("text") == "LOG IT":
        cur = parents.get(n)
        while cur is not None:
            if cur.get("clickable") == "true": print(cur.get("enabled")); break
            cur = parents.get(cur)
```

Drive a table of cases and require both directions — a gate that is always
disabled passes a one-sided check:

| entry | expect |
|---|---|
| empty required field | disabled |
| valid value | enabled |
| absurd value | **disabled** |
| valid again | enabled |

## 6. Record what you deliberately left unbounded

Steppers (fixed increment per deliberate tap) usually should NOT be capped — a
cap low enough to matter refuses a legitimate heavy lift. Write the reason down
or the next audit re-opens it.
