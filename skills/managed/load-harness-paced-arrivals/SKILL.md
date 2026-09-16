---
name: load-harness-paced-arrivals
description: "Diagnose a paced load test whose latency pins to a round number or whose throughput collapses while the server sits idle - separating arrival-pattern bugs (lockstep, per-user jitter breaking paired workloads) from real server limits"
---

# Paced load harnesses lie in three specific ways

Use when a load run shows any of: a p50/p95 pinned to a suspiciously round number, throughput collapsing while the server's CPU/threads/DB sit idle, or failures that move when you change runner count rather than offered load.

## First: compute what the run actually offered

Almost every harness expresses cadence **per user**. Offered load = `users x rate`, and the default rate is usually 1.

- "10,000 users" at the default rate is often **10,000 operations per second**, not 10,000 sessions.
- Convert to the real-world unit before believing any collapse. A player finishing a whole match every second is not a crowd; a real one might finish one every 10-20 minutes (0.001/s).
- Make the UI or driver print `users x rate = N/s offered`. A number nobody computes is a number everybody misreads.

## Second: a round-number percentile is a timeout constant

If p50 sits on 15,000 ms, 30,000 ms or 5,000 ms, stop looking at capacity. Find the constant:

- Grep the server for that timeout (gate waits, rent timeouts, HTTP client timeouts).
- Check the per-operation-kind breakdown. If one kind pins to the constant while its sibling is tens of milliseconds, the fast one is the server working and the slow one is something waiting.
- Cross-check counts: if operation A ran 3x more often than the operation that must follow it, most A's never completed their handshake.

## Third: how arrivals are spread decides paired workloads

Three implementations, three different results, and they are NOT comparable to each other:

| Pacing | Behaviour | Failure mode |
| --- | --- | --- |
| None (`delay after own call returns`) | Users drift apart by their own response times | Crowd stays in whatever phase the ramp built |
| Random offset per user | Crowd spreads evenly | **Breaks any pairing/matchmaking**: partners never coincide, latency pins to the gate timeout |
| Offset derived from the pair/group id | Both halves take the same slot; groups spread | Correct for paired workloads |

Derive the offset from the **same identifier the pairing uses** (hash the pair number), so both halves compute it independently with no coordination between runners. Keep them on a fixed schedule (`nextCall += interval`) rather than sleeping an interval after each call returns, so a slow call cannot desynchronise a pair for the rest of the run.

## Fourth: check gates apply where you think

An "in flight" or "concurrency" cap often exists to stop a login stampede during the **ramp**. If the same semaphore is reused for the steady-state hold, the run silently offers a fraction of what it claims. Read which semaphore instance each phase passes; they are easy to conflate when declared near each other.

## Fifth: make failures nameable before fixing anything

Harnesses cap distinct error keys. If reasons embed per-request ids (trace id, request id, connection id, GUIDs, ports), the cap fills with ids and the real cause collapses into `(other)`.

- Normalise correlation fields **by name** before counting.
- Raise the key cap once the keys are real causes.
- A run reporting thousands of `(other)` failures has told you nothing; fix the instrument first.

## Sixth: separate generator from server

- Read the runners' own counters: `attempted`, `connected`, `peakActive`, `failed`. If each runner delivered exactly what it was asked for with zero connect failures, the generators are fine and the server refused.
- Never run generators on the machine under test when quoting a figure; compare a co-located runner's p99 against a remote one's to see the contamination.
- The same user count spread over a different number of runners is a **different experiment**. Say the runner count beside every figure.

## Closing rule

When a load test "dies", suspect the harness first. Fix the instrument, re-run the identical job, and only then attribute the difference to the server. Every capacity number is the harness's until proven otherwise.
