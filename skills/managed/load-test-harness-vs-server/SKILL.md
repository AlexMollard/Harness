---
name: load-test-harness-vs-server
description: "Diagnose a load test that is failing or slow, separating harness artifacts (pacing, gates, pairing, generator CPU) from real server limits (pools, threads, DB) before drawing any capacity conclusion."
---

# Load test: is it the harness or the server?

Most "the server falls over at N users" findings are the harness measuring itself. Establish
which before reporting any capacity number. Every step below cost a real session to learn.

## 1. Convert users into offered rate, first, always

`offered rate = users x per-user cadence`. A user count alone says nothing. A tester whose
cadence defaults to 1/s means 10,000 users asks for **10,000 operations a second** - a load no
real crowd produces and no server survives.

Get the real-world cadence before choosing one: e.g. a player finishing a match every 10-20
minutes is 0.001/s, so 10,000 players offer 8-17/s, not 10,000/s.

Make the tool print the product next to the user count. A run that cannot say what it is
asking for cannot be interpreted.

## 2. Suspect round-number latencies

**A p50 sitting on a round number is a timeout constant, not load.** p50 of 15,027 ms against
a 15 s gate means the client waited out a timeout on most calls - nothing was working hard.
Compare the operation's parts: if one sub-step is at the timeout and the next is 50 ms, the
fast one is the server and the slow one is the harness waiting for a precondition.

Also compare *counts* between sub-steps: if step A ran 2,303 times and dependent step B only
787, two thirds of attempts never got past A. Tolerated outcomes (a 303, a "no partner") hide
this, because zero failures is compatible with almost nothing happening.

## 3. Check the generators before blaming the target

- Per-runner `peakActive` vs the users it was asked for. Equal => generators delivered.
- Zero client-side connect failures => generators were not the bottleneck.
- Compare runners: a generator sharing a CPU with the server under test shows a much worse
  tail (e.g. p99 7,568 ms) than an isolated box on the identical job (p99 180 ms). Exclude
  co-located generators before quoting a tail.
- More processes per machine does **not** add load when the server is already refusing; it
  adds failures. Prefer more machines, and watch ephemeral ports (~16k per Windows box).

## 4. Watch for gates and synchronisation in the harness

- **A ramp gate reused for the hold** silently caps in-flight work; the run then measures the
  semaphore. Ramp gates exist to stop a login stampede; size the hold gate to the crowd.
- **Pacing that only spaces a user against itself leaves the crowd in lockstep** - average
  rate looks right while arrivals are one spike per interval. Spread the first call across
  one interval.
- **For paired/matched workloads, spread by pair, not by user.** A random per-user offset
  desynchronises partners and every pair then waits out its matchmaking timeout. Derive the
  offset deterministically from the pair number (hash it, same as the pairing key) so both
  halves land on the same slot from any machine, with no coordination.
- Keep both halves on a fixed schedule (`next += interval`), not `delay(interval)` after each
  call returns, or a slow call permanently shifts one partner out of step.

## 5. Make failures nameable before fixing anything

If failure reasons embed per-request ids (trace id, request id), a bounded distinct-reason map
fills with ids and the real cause collapses into `(other)`. Normalise correlation fields out of
the reason before counting. One session lost hours to 4,876 failures reported as `(other)` that
were all one nameable cause.

## 6. Then, and only then, measure the server

- Thread dump under load, histogrammed by the **innermost frame in your own code** - that names
  the blocking site. `.NET`: `dotnet-stack report -p <pid>`.
- Blocking constructors are a common finding: a scoped service doing
  `GetSomethingAsync().GetAwaiter().GetResult()` in its constructor blocks a thread-pool thread
  on **every** request before any work happens. The pool injects ~2 threads/s, so an arrival
  burst queues behind thread creation and the gateway answers 502 while the database idles.
  Fix: hold the factory/session and resolve inside the async methods.
- Connection pools: the database being idle does **not** mean the pool is fine. Connections are
  checked out and parked. `pg_stat_activity` cannot attribute a backend to a client process -
  count the server process's own sockets instead (`Get-NetTCPConnection -OwningProcess`), and
  watch for a plateau on a round number, which is the pool cap.
- Verify pool defaults from the vendor's docs, not memory, and confirm nothing in the repo or
  runtime config overrides them.

## 7. Rules for reporting numbers

- Say which pacing/build produced each figure. Changing *when* calls arrive changes results as
  much as changing how many; rows from different pacing implementations are not a ladder.
- Say how many generators produced it. The same user count over 5 vs 7 runners can differ by
  15x near a cliff.
- One run either side of a knee will disagree with itself - bracket it, do not extrapolate.
- Closed-loop (each user waits for its own call) self-throttles and degrades gracefully.
  Open-loop (paced arrivals) keeps arriving and collapses. The paced number is lower and is the
  honest one, because it is the shape a real crowd has.
- If the ceiling is structural (pool size, port range, thread cap), say so plainly and stop
  hunting for one more code bug.
