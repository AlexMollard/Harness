# agent-core instruction audit — 2026-09-16

Local findings measured against the files as they stand, checked against current
primary-source guidance. Every external claim carries a URL.

## Measured cost

| File | chars | ~tokens | lines | loaded by |
|---|---:|---:|---:|---|
| `adapters/claude.md` | 558 | 150 | 10 | claude |
| `core/00-identity.md` | 291 | 78 | 9 | all |
| `core/10-commit-style.md` | 1,536 | 415 | 34 | all |
| `core/20-principles.md` | 14,732 | **3,981** | 171 | all |
| `core/30-gatekeeper.md` | 4,747 | 1,282 | 100 | all |
| `core/40-code-discovery.md` | 2,079 | 561 | 41 | all |
| `core/50-rtk.md` | 993 | 268 | 29 | all |
| `core/45-memory-mind.md` | 6,759 | 1,826 | 125 | opencode only |

- **Claude Code / omp: ~6,740 tokens, 394 concatenated lines** of always-on
  instruction, plus ~700 tokens for the 10-skill index — **~7.4k per session before
  you type anything**.
- `20-principles.md` alone is **59%** of the instruction budget.

## Against Anthropic's current guidance

Verified at <https://code.claude.com/docs/en/memory> (fetched 2026-09-16):

> **"Size: target under 200 lines per CLAUDE.md file. Longer files consume more
> context and reduce adherence."**

You load **394 lines**. The guidance is per-file and no single file breaches it, but
they are concatenated into one context, and the stated failure mode — reduced
adherence — attaches to the total.

> **"Splitting into `@path` imports helps organization but doesn't reduce context,
> since imported files load at launch."**

Important correction to how I described the build: the import architecture is a
**DRY win, not a token win**. It removes drift between copies; it does not make any
session cheaper. I should not have implied otherwise.

> **"if two rules contradict each other, Claude may pick one arbitrarily"**

This is the documented consequence of Defects 1 and 2 below — they aren't cosmetic.

## Defect 1 — contradictory shortcut marker — FIXED 2026-09-16

Two different literal comment prefixes are mandated for the same practice:

- `core/20-principles.md:94` — `// shortcut: global lock; per-account locks if throughput matters`
- `core/30-gatekeeper.md:70` — `// ponytail: global lock; per-account locks if throughput matters`

Same example sentence, different prefix. Unsatisfiable as a pair, and grepping for
deliberate shortcuts later finds only half of them.

## Defect 2 — contradictory ambiguity rule — FIXED 2026-09-16

- `core/20-principles.md:13` — "If multiple interpretations exist, present them -
  don't pick silently."
- `core/30-gatekeeper.md:23` — "If you can default safely, default and say so — an
  interview is not an interrogation."

Opposite instructions at the exact moment of ambiguity. Gate 1's version is the
better rule and should win.

## Defect 3 — the Gatekeeper largely restates the principles — OPEN

`30-gatekeeper.md` (1,282 tokens) is mostly a second pass over `20-principles.md`:

| Gatekeeper | duplicates |
|---|---|
| Gate 1 "Interview" | §1 Think Before Coding, §7 Ground in Reality |
| Gate 1 "three concrete examples" | §1 Ambiguity check (same rule, verbatim intent) |
| Gate 2 rung 1 (YAGNI) | §2 "Nothing speculative" |
| Gate 2 rung 2 (reuse) | §5 Efficiency pillar, §7 Reuse before you build |
| Gate 2 "Never simplify away" | §2 "Never simplify away" (near-verbatim) |
| Gate 2 shortcut marking | §5 shortcut marking |

"Reuse before you build" is stated **three times** across the two files.

This is exactly what your own `check-resolvable` skill exists to catch — it was just
never pointed at the instruction files.

## Not defects (checked, fine)

- **Emphatic markup is restrained** — 10 emphatic terms across 171 lines. No
  ALL-CAPS shouting.
- **`45-memory-mind` scoping is correct** — opencode genuinely has the `mind` MCP
  server configured, and is the only harness loading the protocol.
- **`~/.claude/CLAUDE.md` is a regular file, not a symlink** — matters for the Cowork
  edge case documented in the memory page.
- **Import depth is 2 hops**; the documented maximum is four.
- **HTML comment headers cost nothing** — "Block-level HTML comments in CLAUDE.md
  files are stripped before the content is injected into Claude's context."

## Capabilities available but unused (Claude Code 2.1.259 installed)

| Feature | Since | What it gives you |
|---|---|---|
| `~/.claude/rules/` | current | Topic files that load like CLAUDE.md, no import approval needed |
| `paths:` frontmatter on rules | current | Rules that load **only** when Claude touches matching files |
| `/doctor` trim check | v2.1.206 | Proposes cuts to a CLAUDE.md |
| `/skill-doctor` | v2.1.252 | Shows what each skill costs and how often it's used |
| `skillOverrides` | current | Per-skill visibility: `on` / `name-only` / `user-invocable-only` / `off` |
| `claudeMdExcludes` | current | Skip ancestor CLAUDE.md files by glob |

All are available on your installed version.

## External evidence on whether these files even help

- An ETH-Zurich-style study reported by InfoQ (March 2026): LLM-**generated**
  AGENTS.md files *reduced* task success ~3% and raised steps/cost >20%;
  human-written files gave ~4% success gain while still raising cost up to 19%.
  Agents follow such files **indiscriminately** — doing unnecessary work rather than
  ignoring irrelevant guidance.
  <https://www.infoq.com/news/2026/03/agents-context-file-value-review/>
- Practitioner consensus for AGENTS.md is <300 lines, with some teams under 60.
  <https://www.philschmid.de/writing-good-agents> (secondary, not spec)
- The AGENTS.md spec has **no import mechanism**; the request is open and unresolved.
  <https://github.com/agentsmd/agents.md/issues/11>
- Claude Code still does not read AGENTS.md natively; the official workaround is the
  `@AGENTS.md` import — which is the shape agent-core already uses.
  <https://code.claude.com/docs/en/memory>

## Verification still outstanding

The memory docs note that **Cowork desktop sessions** skip user-scope imports that
resolve outside the working directory. This session (desktop Code tab) *did* expand
`@RTK.md` from `~/.claude/`, which is outside the scratch working directory — strong
evidence the Code tab is unaffected. Confirm directly by running `/context` in a new
desktop session and checking that the `agent-core` files appear under **Memory files**.

## Status

Defects 1 and 2 fixed 2026-09-16: one `// shortcut:` marker, and section 1 now
defers to Gate 1 on when to ask versus default.

Defect 3 (the ~1,300-token Gatekeeper/principles overlap) is left OPEN. It is a
judgement rewrite of your own rules, not a mechanical fix, and is the single
biggest lever on the 394-line total.

## Evidence on instruction length (arXiv, 2026)

All preprints, no stated peer-review venue — weigh accordingly. Verified via the
arXiv API; titles and IDs confirmed.

**Detailed, specific instructions measurably help.** This cuts *against* blanket
trimming:

- Coding-agent audit task: a detailed external checklist beat a generic self-check
  **10/10 vs 5/10 runs** (p=0.0325). <https://arxiv.org/abs/2607.17937>
- Replacing detailed specialist system prompts with a minimal generic one dropped
  semantic accuracy **0.67 → 0.58**. <https://arxiv.org/abs/2601.06640>

**But verbosity costs real work.** This is the same shape as the InfoQ finding:

- Augmenting MCP tool descriptions raised task success by a median **+5.85pp** yet
  increased execution steps **+67.46%** and *regressed* 16.67% of cases. The authors
  note "compact variants often preserve behavioral reliability while reducing
  unnecessary token overhead." <https://arxiv.org/abs/2602.14878>

**Position still matters in 2026.** Middle-of-context degradation persisted across
all tested models, from **-16pp to -56pp** depending on filler.
<https://arxiv.org/abs/2605.23170>

**Long context degrades coding agents — but the headline result is weak.** 8/10
passes at ~11k chars vs 3/10 at ~299k chars, **p=0.0698: a trend, not statistically
significant**, n=10 per arm. Do not treat as established.
<https://arxiv.org/abs/2607.17937>

No clean replication of Chroma's original context-rot protocol was found.

### What this changes

The recommendation is **not** "cut instructions." Specificity earns its tokens;
duplication and prose do not. So:

- **Keep** concrete, verifiable rules — they measurably improve adherence.
- **Cut** the Defect 3 duplication (~1,300 tokens saying the same thing twice) and
  the 8 sentences over 40 words, which add length without adding a rule.
- **Expect** that every rule retained will be followed indiscriminately, adding
  steps. That is the real price of the 394 lines, more than the tokens.
