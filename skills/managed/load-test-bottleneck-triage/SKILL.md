---
name: load-test-bottleneck-triage
description: "Diagnose why a load test degrades or 'dies' - separating harness limits, database capacity, and in-process thread starvation - using runner counters, pg_stat_activity, and a thread-dump histogram"
---

# Load test bottleneck triage

Use when a load run slows, errors, or "dies" and you need to name the constraint rather than guess. Three candidates, each with a distinct signature. Collect all three signals *at the same moment*, mid-hold - a dump taken between steps proves nothing.

## 1. Did the generator actually deliver the load?

Check this first. Most "server collapsed" reports are the harness starving itself.

Read the per-runner counters (attempted / connected / peakActive / failed). If `peakActive` is well under what was asked, the load never arrived and nothing about the server is proven.

Even when `connected == requested`, the generator can still be the constraint:

- **Unramped arrivals.** Everyone logging in at t=0 measures account creation contending with itself, not steady state. A ramp is not optional; it is the difference between hundreds of failures and zero.
- **An in-flight gate applied during the hold.** A per-runner concurrency semaphore sized for the ramp will throttle the whole run. Compute `users per runner : in-flight slots`. Past roughly 5:1 a *paired* operation (one that needs two users in the same window) stops converging, and throughput collapses while the server goes quiet.
- **Generators sharing a box with the server.** Co-located load competes for the same cores; the numbers are then about the machine, not the service.

Signature of a generator-limited run: throughput falls **and** the server gets *quieter* (thread count drops, DB idle, zero failures).

## 2. Is the database the constraint?

One query per sample:

```sql
SELECT coalesce(state,'?'), count(*), count(*) FILTER (WHERE wait_event_type='Lock')
FROM pg_stat_activity WHERE backend_type='client backend' GROUP BY 1;
```

- `active` high, lock waits high -> genuinely the database; find the query.
- `idle in transaction` > `active` -> the app is holding connections rather than using them.
- `active` ~1 with hundreds `idle` **while the run is failing** -> the database is exonerated. The time is going somewhere in-process.

## 3. Is the process out of runnable threads?

When the DB is idle and the app is slow, dump the server's threads mid-hold:

```bash
dotnet-stack report -p <pid> > dump.txt   # install: dotnet tool install --global dotnet-stack
```

Parse it correctly - this is where the analysis usually goes wrong:

- The file may be **UTF-16** when redirected by PowerShell. Decode before matching or every regex silently returns nothing.
- Split threads on `Thread (`.
- Keep only threads parked in a blocking wait: `SpinThenBlockingWait`, `GetResult`, `ManualResetEventSlim.Wait`.
- **`dotnet-stack` prints innermost frame first.** Group by the *first* line matching your own namespace, not the last. The last is the outermost middleware and will blame the pipeline for everything.

```python
import re, collections
text = open('dump.txt', 'rb').read().decode('utf-16-le', errors='replace')  # or utf-8
counts = collections.Counter()
for block in text.split('Thread ('):
    if not any(s in block for s in ('SpinThenBlockingWait', 'GetResult', 'ManualResetEventSlim.Wait')):
        continue
    inner = next((l.strip() for l in block.split('\n') if 'YourNamespace' in l), None)
    if inner:
        counts[inner.split('!')[-1].split('(')[0]] += 1
print(counts.most_common(10))
```

A constructor at the top of that histogram is the finding: work being done per request that should be async or done once at startup. Classic culprit is a DI-scoped service whose constructor calls `SomethingAsync().GetAwaiter().GetResult()` - it blocks a pool thread on every request, and because the pool grows only ~1 thread per 500ms, arrival bursts queue behind thread injection and surface as connection-pool timeouts and 502s.

## Reporting honestly

- A confirmed blocking site is **not** automatically the cause of a collapse. Say which is proven and which is inferred.
- If zero failures occurred at every level tested, say the ceiling was never reached and the throughput figure is a **floor**.
- Fix harness limits before server code, or the before/after of a server fix cannot be measured.

## Make it visible in the tool

If an operator will hit this again, put the three signals in the UI next to each other - DB rollup, server thread count, and a button that captures and histograms stacks. A diagnosis that requires a terminal is one nobody else can reach.
