---
name: load-test-collapse-triage
description: "Diagnose why a load test collapses or shows huge latency — separate harness artifacts (pacing, arrival sync, in-flight gates, error-key overflow) from real server limits (thread starvation, connection pools) before fixing anything"
---

# Load test collapse triage

When a load run shows failures, absurd latency, or a throughput ceiling, the first job is deciding **whether you are measuring the server or your own harness**. Most "server limits" turn out to be harness artifacts. Work the checks in order; each is cheap and rules out a whole class.

## 0. Establish what was actually offered

User count is not load. **Offered rate = users x per-user rate.** Print it in the driver:

```
cadence 0.01/user/s = 100 matches/s offered, ramp 120s hold 180s
```

A default of "1 op/s each" means 10,000 users ask for 10,000 ops/s — a rate no real crowd produces. Compare against real user cadence (e.g. a match every 10-20 min = 0.001/s) before calling anything a server limit.

Also verify the driver actually *sends* the knob. A parsed-but-unplumbed variable silently runs the default and invalidates the run.

## 1. Make failures legible before fixing anything

If the top failure bucket is `(other)` or an opaque count, stop and fix the harness's error reporting first — you cannot fix what you cannot name.

Common cause: reason strings embed per-request ids (`trace_id`, `request_id`), so every failure becomes a unique key and overflows the distinct-reason cap. Normalise correlation fields by name before counting:

```csharp
var normalised = TraceFields.Replace(body, "\"$1\":\"{id}\"");
```

## 2. Read a latency p50 as a possible constant

A p50 pinned near a round number (15,000 ms) is a **timeout, not load**. Look up what has that timeout — a matchmaking gate, an HTTP client, a rent timeout — and check whether the operation is waiting on a peer rather than the server.

Per-operation-kind percentiles are what make this visible. Whole-flow timing hides it: split `prematch` / `postmatch` / `login` and compare. A fast second half beside a timeout-pinned first half means waiting, not work.

Also compare the count of each kind. If stage two ran far fewer times than stage one, most attempts never got past the gate.

## 3. Check arrival synchronisation (paced runs only)

Pacing spaces each user against *itself*. It does not desynchronise the crowd: after a ramp, all users fire together, sleep, and fire together again — average rate looks low, instantaneous concurrency equals the whole population.

Fix by spreading first calls over one interval, then holding a fixed schedule (`nextCall += interval`) rather than sleeping after each call returns.

**Critical for paired/multiplayer flows:** derive the phase from the *pair* (or party/group) id, not per user, using the same deterministic hash the pairing itself uses, so both halves land on the same slot from any machine without coordination. A random per-user offset removes failures but pulls partners apart — you get zero failures and a p50 sitting exactly on the gate timeout.

## 4. Check in-flight gates in the harness

A semaphore sized for the ramp (login stampede control) must not carry into the hold, or the run measures the semaphore. Symptom: users N, but only `runners x gate` ever in flight, and paired flows stop converging.

Verify by reading which semaphore instance the steady-state pumps receive — ramp and hold gates are easy to conflate when declared a few lines apart.

## 5. Only now, look at the server

Take a thread dump mid-hold and group blocked threads by the innermost frame in *your own* code:

```
dotnet-stack report -p <pid>
```

- **Many threads blocked in a constructor** -> sync-over-async DI. Scoped services calling `GetSomethingAsync().GetAwaiter().GetResult()` in a constructor block a thread-pool thread on every request before doing any work; the pool injects ~2 threads/s, so bursts queue behind thread creation and the gateway answers 502 while the database idles. Fix: hold the session/factory, resolve inside the async methods.
- **`connection pool has been exhausted`** -> client-side pool, not the database. Confirm by comparing: database `max_connections` and active count (often ~1 active while failing) against the client process's own sockets.

### Proving a pool ceiling

`pg_stat_activity` cannot say which client owns a backend. Count the process's own sockets instead:

```powershell
Get-NetTCPConnection -OwningProcess $pid -State Established |
  Where-Object { $ports -contains $_.RemotePort }
```

A flat plateau on a round number (e.g. exactly 200 = two pools x default 100) is proof. Check the *runtime* connection string for an override, not just source files, and confirm the default from primary docs rather than memory.

## Reporting rules

- One user count driven by a different number of generators is a **different experiment**, not a repeat. A step either side of a knee will disagree; get both shapes before quoting a ceiling.
- Generators sharing a machine with the server inflate tail latency. Compare a remote generator's p95/p99 against a co-located one before blaming the server.
- Zero failures is not success if the flow silently tolerates a miss (e.g. an unpaired match counted as a skip). Always check completion counts per stage.
