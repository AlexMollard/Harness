---
name: load-test-harness-truthfulness
description: "Audit a load harness before believing its numbers - use when a load test reports mass failures, a suspiciously round latency, a collapse at some user count, or before quoting any capacity figure to stakeholders."
---

# Load-test harness truthfulness

When a load run reports mass failures or a dramatic collapse, the harness is the prime
suspect, not the server. In one multi-day effort roughly 80% of failure volume was
instrumentation. Rule each of these out **before** touching product code.

## The five harness lies, in the order they usually bite

### 1. The offered rate is not the user count
A per-user cadence knob times the user count is what the server is asked for. A default of
"1 per second" means 3,200 users request 3,200 operations/second - a rate no real crowd
produces. Compute and print `users x rate` in the run header so a run cannot be mislabelled.

**Check first.** This one invalidates whole result tables.

### 2. A concurrency gate silently caps the load
Look for a semaphore used in both ramp and steady state. Reusing the ramp's gate for the hold
caps in-flight work at `gate_size x runners` regardless of the user count, so a run offers a
fraction of what it claims. Ramp gate and hold gate must be separate objects.

### 3. Failure reasons carry unique ids, so causes hide behind "(other)"
If reasons are keyed by raw response body or exception message, per-request trace/request ids
make every failure a distinct key, overflowing any distinct-reason cap. Normalise correlation
fields by name before counting. Symptom: a huge `(other)` bucket and no diagnosis.

### 4. A paced crowd arrives in lockstep
Pacing each user against *itself* leaves the whole crowd on the phase the ramp built: N users
at 1/interval arrive as N at once. Offered average looks modest, instantaneous load is the
whole population.

**Spreading by a random offset per user is the obvious fix and is wrong for any paired or
correlated workload** - it pulls partners apart. Derive the offset from the *pair/group id*
(same hash the pairing uses) so both halves land on one slot, and hold a fixed schedule
(`next += interval`) rather than sleeping after each call returns.

### 5. The debugger and shared CPU manufacture failures
Attached debuggers turn timeouts into exceptions; generators on the same box compete with the
server. Compare a runner on a separate machine against a co-located one - a p99 gap of 40x is
generator contention, not the server.

## Reading a result honestly

- **A p50 pinned to a round number is a timeout constant**, not load. Find which timeout
  (gate wait, rent timeout, HTTP client) equals it.
- **Split latency by operation kind.** One climbing percentile hides which half of a flow is
  slow; a gate wait and real work look identical in an aggregate.
- **Count completions of each stage.** If stage-two count is a third of stage-one, most
  attempts never paired/matched - zero failures can coexist with a broken run.
- **First run after a restart is a cold start** (cold pools, first-time account creation).
  Repeat warm before calling it a rate limit. An inversion - lower rate fails, higher rate
  passes - is the signature.
- **Same total, different runner count = different experiment.** Say how many generators
  produced a figure.
- **Closed vs open loop.** Users that wait for their own call self-throttle and degrade
  gracefully; paced users keep arriving and queue without bound. The paced number is lower and
  is the honest one.

## Proving a server-side limit

1. **Thread dump under load**, grouped by innermost application frame. Blocked threads name
   the blocking site directly (`dotnet-stack report -p <pid>`).
2. **Count the process's own sockets to the database** (`Get-NetTCPConnection -OwningProcess`)
   - server-side stats cannot say which client owns a backend. A flat plateau at a round
   number is a pool cap; compare against the documented default.
3. **Check the database's own view**: if it reports ~1 active connection against a high
   `max_connections` while clients report pool exhaustion, the limit is client-side pooling,
   and pools are per process - replicas multiply capacity.

## Blocking patterns worth grepping for

- `GetAwaiter().GetResult()` / `.Result` in **constructors** of request-scoped services. Under
  burst these park a thread per arriving request before any work happens; the thread pool
  injects ~2 threads/second, so arrivals queue behind thread creation and the gateway answers
  502 while the database idles.
- Replacing them with a *synchronous* accessor that opens a connection is a safer flavour of
  blocking, not a non-blocking fix - state that precisely rather than "fixed".
- Static mutable collections written from request paths (a plain `Dictionary` mutated per
  login fails all logins under concurrency).

## Before quoting a capacity number

State: the offered rate (not just users), the pacing implementation, the generator count and
isolation, the build configuration, and what the run did **not** cover. A figure from a Debug
build on loopback against one process is a floor, and any flow that is registered but not
routed has never been tested at all.
