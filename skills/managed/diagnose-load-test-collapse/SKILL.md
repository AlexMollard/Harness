---
name: diagnose-load-test-collapse
description: "Diagnose why a .NET web service collapses under load testing - distinguishes thread-pool starvation from connection-pool ceilings from harness artifacts, using thread dumps, socket counts and failure-reason normalisation."
---

# Diagnose load-test collapse in a .NET service

Use when a load run reports mass failures, 500s/502s, or throughput that falls as users rise. The goal is to name **which of four different things** is failing, because they look identical from the client and have opposite fixes.

## The four causes, and the evidence that separates them

| Cause | Signature | Where to look |
| --- | --- | --- |
| Thread-pool starvation | Many threads parked in one stack frame; DB idle; gateway 502 | Managed thread dump |
| Connection-pool ceiling | `"The connection pool has been exhausted"`; DB idle but client holds a flat plateau of sockets | Socket count per client process |
| Harness artifact | Failures change when runner *count* changes at the same user total | Re-run with different generator split |
| Genuine DB limit | DB shows high `active`, lock waits, or hits `max_connections` | `pg_stat_activity` |

**Always check the database first.** If it reports ~1 active connection while the app fails, the database is exonerated and every remaining cause is in-process.

## Order of work

### 1. Make failures legible before fixing anything

Harnesses commonly key failure counts by raw message. If the message embeds a trace id, request id, or port, **every failure becomes a unique key** and overflows into an `(other)` bucket that reports a count and no cause. Normalise correlation fields by name before counting, and raise the distinct-key cap:

```csharp
private static readonly Regex TraceFields =
    new("\"(trace_id|request_id|traceId|requestId)\":\\s*\"[^\"]*\"", RegexOptions.Compiled);
```

Skipping this step wastes whole cycles guessing at a hidden cause.

### 2. Thread dump during the hold, not after

Capture while the run is at peak (`dotnet-stack report -p <pid>`), then histogram by the **innermost frame belonging to your own code** — runtime frames are noise. A count like "78 of 80 blocked in X" names the site directly.

**The dominant .NET bug class this finds:** a `Scoped` service resolving async work in its **constructor** via `.GetAwaiter().GetResult()`. DI constructors run on the request thread, so every arrival blocks a thread-pool thread *before doing any work*. The pool injects only ~1-2 threads/second, so an arrival burst queues behind thread creation and the gateway answers 502 while the database sits idle.

Fix: hold the *session/factory*, not the resolved context, and resolve inside the async methods that already `await`. Constructors cannot be async; the answer is to remove blocking work from them, not to make them async.

### 3. Count sockets to prove a pool ceiling

`pg_stat_activity` cannot say which client process owns a backend, so count from the client side:

```powershell
$pid_ = (Get-Process <Service>).Id
(Get-NetTCPConnection -OwningProcess $pid_ -State Established |
    Where-Object { $_.RemotePort -eq <dbPort> }).Count
```

Sample once a second through a failing run and compare with rest. **A flat plateau on a round number is the pool cap.** Npgsql defaults to `Maximum Pool Size` 100 per data source, so a reader pool plus a writer pool plateaus at exactly 200.

Gotchas: the port may be a proxy/sidecar port, not the published container port — list the process's remote ports first rather than assuming. If the count reads zero, the filter is wrong, not the theory.

### 4. Rule out a leak

A leak and a ceiling both exhaust a pool. They differ in time: a leak degrades *within* a steady run and never recovers; a ceiling fails immediately at a given concurrency and is clean below it. A long clean run at lower load, plus connections pruning back at rest, rules out a leak.

## Rules for trustworthy numbers

- **Isolate generators.** Load generators sharing a CPU with the service under test corrupt every number. State it explicitly when they do.
- **One user count driven by fewer, heavier generators is a different experiment, not a repeat.** Two runs either side of a knee will disagree by an order of magnitude. Before concluding "broken at N", vary the generator split at fixed N.
- **Upgrade every generator before comparing absolute counts.** Mixed harness builds make totals meaningless; only per-generator ratios survive.
- **Watch for harness in-flight caps.** A cap like `Concurrency = 25` per runner means "800 users" is really ~125 concurrent. Removing such a cap makes results look *worse* because the load finally became real - say so, rather than reporting a regression.

## Reporting

Give the ladder as a table (users, generators, throughput, failures, blocked threads), name the binding constraint with its measurement, and separate *fixed* from *structural*. When the remaining limit is arithmetic (slots x hold time < demand), say plainly that no further code fix moves it and list the levers by cost.

**Blast radius:** shared base classes and DAL infrastructure are the last place to fix, not the first. Surface the evidence and get explicit approval before editing a type every consumer inherits - a load test is not authorisation to rewrite the data layer.
