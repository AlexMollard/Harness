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

Defect 3 partially fixed 2026-09-16 — and my estimate of it was wrong.

I wrote "~1,300 tokens of duplication", but 1,282 was the *whole Gatekeeper file*,
not its duplicated portion. Removing every genuine restatement without losing a rule
saved only **258 chars (~69 tokens)**: Gate 1 now points at §7 and §1 instead of
re-deriving them, Gate 2 points at §2 for scope and the never-simplify-away list,
and §5's Efficiency pillar points at §7 instead of restating "reuse before you build"
a third time.

The remaining overlap is **conceptual, not textual**: Gate 1 and §1 cover the same
ground in two framings (principle vs procedure), as do Gate 2's ladder and §2.
Collapsing that would save an estimated 800-900 tokens but means deleting one of the
two framings — a structural decision about how you want your own rules organised,
not a defect to be silently fixed. Left to the user.

Note against the evidence above: Anthropic's own `/doctor` trim guidance keeps
"pitfalls, rationale, and conventions that differ from tool defaults" and cuts only
what Claude can derive from the codebase. That argues against stripping the long
rationale sentences, which is where the remaining bulk sits.

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

## Evidence on rule COUNT (the strongest measured result)

Your core files contain **109 discrete directives** (93 bullets + 16 bolded
standalone rules). That number is what the following bears on.

### The decay curve

"Phase Transitions in Compositional Constraint Satisfaction" — 15 models, 8 families,
369,753 constraint checks, deterministic verifiers, temperature 0.
<https://arxiv.org/abs/2608.12426>
*Caveat: single author, "reviewed in the ARR May 2026 cycle", acceptance not stated.
It carries the strongest number here, so weigh accordingly.*

- Per-constraint pass rate decays as **72.0% x 0.922^(k-1)** — each added constraint
  drops the average per-constraint pass rate to 92.2% of the previous level
  (held-out MAE 0.2pp).
- Joint ("all k satisfied") success collapses as roughly the **product** of the
  marginals: "at k = 8, models still pass individual constraints 40.7% of the time
  yet satisfy all eight simultaneously only 5.7% of the time (35pp gap)."
- "Reliable instruction following breaks down beyond **5-6** simultaneous constraints."
  Per-model ceilings: GPT-5.5 k*=7, Claude 4.7 Opus k*=6, most others 3 or fewer.
- **Structural and ordering constraints degrade 2.0x faster than lexical ones.**
- Mitigations mostly fail: "pre-generation planning does not move the threshold at
  all"; self-correction and best-of-5 delay it by one to two constraints.

Corroborated by ManyIFEval (<https://arxiv.org/abs/2509.21051>): Claude 3.5 Sonnet
all-instructions-satisfied falls **0.95 at n=1 to 0.48 at n=10**; GPT-4o 0.94 to 0.21.

### The reconciliation that stops this being alarmist

IFScale and Arize's 2026 rerun show frontier models tracking **thousands** of
instructions (GPT-5.5 at 99% through N=5,000).
<https://arxiv.org/abs/2507.11538> · <https://arize.com/blog/llm-instruction-following-benchmark-2026/>

Both are right, because they measure different things:

- **Additive, independently-checkable, no-state-required rules** ("include X",
  "never say Y"): scale to thousands. This is keyword inclusion — exactly the class
  the decay paper finds compositionally immune.
- **Rules requiring sustained state across the output, all of which must hold at
  once** (counts, ordering, structure, cross-references): **5-6**.

### Honest limit on transferring this to your files

**None of this measures judgment-shaped behavioural rules** — "be surgical", "disagree
out loud", "have a recommendation". Every measured result above uses mechanically
verifiable output constraints *by explicit design*; the decay paper rejected
candidates like "maintain formal tone throughout" for needing stylistic judgment.

This is the single biggest gap between the literature and real system-prompt
engineering, and nothing found closes it. Your 109 directives are also mostly
*conditional* (apply when the situation arises) rather than *simultaneous* (all must
hold in every output), so the 5-6 figure does **not** transfer directly. Treat the
direction as supported and the magnitude as unmeasured.

## Conflicting rules fail SILENTLY

ConInstruct, AAAI 2026. <https://arxiv.org/abs/2511.14342>

- Models *detect* conflicts well: DeepSeek-R1 F1 **91.5%**, Claude-4.5-Sonnet **87.3%**.
- They then say nothing: "when an instruction contains 1-2 conflicts, GPT-4o will
  directly generate a response in **97.5%** of cases, satisfying only a subset of the
  constraints but failing to notify the user of the conflicts."
- Best case: "Claude-4.5-Sonnet explicitly alerts users to conflicts in only **45%**
  of cases."

**This is why Defects 1 and 2 mattered.** A contradiction is not surfaced as an
error — it is silently resolved in a direction you never chose and never see.

## Two pieces of folklore that did NOT survive checking

**"Put critical rules at the top or they get ignored" — unsupported.**
The only study that directly tested rule position among peer instructions found
**no effect**: "we found no consistent relationship between IF rates and instruction
position across models. Middle instructions generally did not have lower IF rates
than first or last instructions." It attributes degradation to *conflict*, not
position. <https://arxiv.org/abs/2510.14842> (section 4.2)

The widely repeated "buried rules lose 30-50% compliance" figure has **no primary
source** — it traces back to Liu et al.'s *document-retrieval* result re-skinned as
rule compliance. What does measurably matter is the **channel** (system vs user vs
tool description) and constraint *difficulty ordering*, not depth.

**Emphatic markup ("IMPORTANT", "MUST", ALL CAPS) — no provider recommends it.**
All three argue against it, none cite evidence either way. Anthropic, verbatim:
"Where you might have said 'CRITICAL: You MUST use this tool when...', you can use
more normal prompting like 'Use this tool when...'."
<https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices>
The only legible uppercase experiment found a null (87.7% vs 87.1%). Your files
already follow this — 10 emphatic terms across 171 lines is restrained.

**Negative framing ("don't do X") — effectively a null.** Anthropic's
"tell Claude what to do instead of what not to do" is asserted about *output
formatting* specifically, with no experiment cited. IFEval and IFBench never contrast
the two framings. One unrefereed 2026 preprint suggests prohibitions decay under
context pressure while requirements persist; unreplicated, no affiliation.
<https://arxiv.org/abs/2604.20911> Your 38 negative constructions are not a
demonstrated problem.

## What the evidence actually supports doing

1. **Fix contradictions first.** Highest-confidence, already done for Defects 1-2.
   Conflict is the one mechanism with both a measured effect on following *and*
   a measured failure to report itself.
2. **Cut duplication, not rules.** Defect 3's ~1,300 tokens add zero new constraints
   while adding length. Pure win.
3. **Do not reorder to "put important rules first."** Unsupported by the one direct test.
4. **Do not strip emphasis or rewrite negatives.** No evidence of benefit; your
   current usage is already within what providers recommend.
5. **Prefer concrete over abstract** where a rule can be made verifiable — this is
   the one thing both Anthropic's docs and the measured checklist result agree on.

---

# Token-spend audit — 2026-09-16

Separate from the instruction audit above. Measured from 443 Claude Code session
transcripts and 269 omp sessions over 60 days, summing `input_tokens +
cache_read_input_tokens + cache_creation_input_tokens` per request.

## Spend is concentrated in a handful of sessions

Claude Code, **81.70B input tokens** over 60 days:

| Peak context | Sessions | Share of spend |
|---|---:|---:|
| under 194k | 329 | **1.4%** |
| 194k - 750k | 79 | 6.7% |
| 750k - 970k | 7 | 9.0% |
| **over 970k** | **28** | **83.0%** |

**6% of sessions are 83% of the tokens.** Median session peaks at 108k; p95 at 993k.

The cause: every turn re-sends the whole context, and `opus[1m]` puts auto-compact
at 97% of a 1M window (~970k) instead of ~194k. Context never resets, so per-turn
cost climbs for the whole session.

## Fix applied

| Harness | Setting | Value |
|---|---|---|
| Claude Code | `autoCompactWindow` (settings.json) | `500000` |
| omp | `compaction.thresholdTokens` | `500000` |

Both take a **token count**, confirmed against the Claude Code binary rather than
docs: the CLI describes the resolved window as "in tokens", and actual firing is
`effective_window minus the summary buffer` (~33k), so ~467k.

## Modelled saving

First-order: a session capped at C costs roughly `C/peak` of what it cost running
to peak. Ignores the cost of extra compaction summaries, so expect somewhat less.

| Cap | Claude Code saved | % |
|---|---:|---:|
| 750k | 18.05B | 22.1% |
| 600k | 29.78B | 36.5% |
| **500k** | **37.74B** | **46.2%** |
| 400k | 45.93B | 56.2% |

omp: 2.24B saved (47.4% of its 4.74B). **Combined ~40B of ~86B, about 46%.**

omp is only 5.8% of Claude Code's token volume — median peak 56k, and just 1.5% of
its sessions exceed 500k. The Claude Code change is where the money is.

## Trap avoided

omp has `extendedContext: false` - *"Use larger context windows where supported; may
incur premium pricing."* That reads as a 200k cap, which would make a 500k threshold
**never fire** - worse than leaving it alone. Its own data disproved it: p99 peak
850k, max 1,408k. Verify the window before setting a threshold against it.

## Re-run these

```bash
# Claude Code: peak context and spend per session
find ~/.claude/projects -name '*.jsonl' -mtime -60
# sum input_tokens + cache_read_input_tokens + cache_creation_input_tokens per request

# omp: same, from "usage":{"input":N,...,"cacheRead":N,"cacheWrite":N}
find ~/.omp/agent/sessions -name '*.jsonl' -not -name '__advisor*'

# which MCP servers actually get called
grep -rhoE '"name":"mcp__[^"]+"' ~/.claude/projects --include='*.jsonl'
grep -rhoE '\{"type":"toolCall","id":"[^"]*","name":"[^"]+"' ~/.omp/agent/sessions
```

Config is *not* evidence of use. omp had two MCP servers configured and made zero
MCP calls in 24,088 tool calls; Claude Code's two servers drew 17 calls in 60 days
against 9,615 for the built-in browser.
