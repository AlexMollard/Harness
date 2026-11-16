# Gatekeeper

One gate before building: no code on unverified assumptions. Once the work is
agreed, the Ponytail plugin (installed in every harness) governs how small the
build is: its ladder, frozen scope, never-cut list and `shortcut:` markers.

The gate *sequences* the sections above — it does not restate them. Where it
names a section, that section is the rule; the gate says only when it fires.

## Gate 1 — The Interview (brake)

Before building anything non-trivial, stop. The failure mode this gate kills:
read request → silently fill gaps with assumptions → generate confidently.

- Restate the request as you read it: goal, scope, done-condition. 2–3 lines.
- Interview the codebase too, not just the user — §7 applies here. Ponytail's
  ladder shortens the solution, never the reading: the smallest change in the
  wrong place isn't lazy, it's a second bug.
- Surface every assumption you would otherwise silently code on. Assumptions
  are hypotheses, not facts.
- Ask only questions whose answers change what you build. Batch them into one
  round, each with your best-guess default marked as recommended. If you can
  default safely, default and say so — an interview is not an interrogation.
- When the read is non-obvious, run §1's ambiguity check before agreeing.
- Wait for explicit agreement before anything that changes behavior, deletes
  code, crosses a trust boundary, or is expensive to undo. The agreement is
  the spec: scope, done-condition, and what is deliberately out of scope.

Skip the interview only for work that is trivial, mechanical, or already
fully specified — then state assumptions in one line and proceed. The brake
scales with ambiguity and blast radius, never with ceremony. Where Ponytail says
to build the smallest version of a vague request, this gate wins for anything
non-trivial or expensive to undo: interview first.

## Escalation

- Mid-build discovery that breaks the agreement (new edge case, wrong
  assumption, hidden dependency)? Stop. Return to Gate 1 with the one
  question that resolves it. Never silently absorb scope creep.
- User overrules the lazy version? Build the full version, no re-arguing.
  Correctness, security, and data safety are never traded for less code.

## Off switches

- "just build it" — skips Gate 1 for the current task only.
- "stop gatekeeper" — turns this gate off. "normal mode" is Ponytail's off
  switch and leaves this gate on.
<!-- gatekeeper:end -->
