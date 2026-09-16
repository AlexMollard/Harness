---
name: load-ceiling-triage
description: "Determine whether a load test's ceiling is database capacity, an application bug, or the load harness itself - use when a service slows or fails under load and you need evidence, not a guess."
---

# Load ceiling triage

When throughput plateaus or a run "dies", there are only four candidates. Rule them out in this order, because each step is cheaper than the next and eliminates the one people usually blame.

## 0. First, is the run even shaped correctly?

Two harness mistakes look exactly like server failure:

- **No ramp.** All virtual users arriving at t=0 measures account creation and cold caches contending with themselves. Symptom: login p50 in seconds, mass 500/502, failures concentrated at the start. Fix: stagger arrivals (30-60s) and re-run before diagnosing anything. An identical 480-user run went 246 failures -> 0 with a 30s ramp.
- **Generators sharing the box with the server.** Load processes compete with the thing they measure. Symptom: local runners succeed while remote ones fail, or vice versa.

Also confirm the target address means the same thing to every runner: `localhost` in a job spec makes each remote worker aim at itself (instant connection-refused).

## 1. Exonerate (or convict) the database

Sample during the hold, not after:

```sql
SELECT state, count(*), count(*) FILTER (WHERE wait_event_type='Lock')
FROM pg_stat_activity WHERE backend_type='client backend' GROUP BY 1;
```

- `active` high, lock waits high -> genuine DB contention. Go read `pg_stat_statements`.
- `active` ~1 with hundreds `idle`, zero lock waits, while latency climbs -> **the database is not the bottleneck**. The app is holding connections without querying. Continue.

## 2. Look at the server's threads, timed to the hold

Thread count alone is a smell; the stacks are the diagnosis. Capture *during* the hold - a dump taken between steps shows an idle process and proves nothing. Wait for the step to be posted, sleep past the ramp, then:

```
dotnet-stack report -p <pid>
```

Parse it correctly or you will blame the wrong code:

- Split on `Thread (`.
- Keep only threads whose stack contains `SpinThenBlockingWait`, `GetResult`, or `ManualResetEventSlim.Wait` - a blocking wait is the signature worth counting.
- **Group by the FIRST frame of your own code in each thread.** `dotnet-stack` prints innermost frame first, so the first match is the call that blocked and the last is only the outermost middleware. Grouping by the last blames the pipeline (e.g. a response-buffering middleware that is entirely async).
- Note the file may be UTF-16 when redirected by PowerShell; decode accordingly.

A constructor appearing here is the jackpot: combined with a `AddScoped` registration it means the blocking work runs **per request**. Sync-over-async in a scoped constructor starves the thread pool (which only injects ~1 thread per 500ms), so arrival bursts queue, hit connection-rent timeouts, and surface as 502s from the proxy.

## 3. Prove the harness is not the ceiling

Before claiming any capacity number, check the generators actually delivered:

- Per-runner `connected` / `peakActive` should equal the requested share. If they do, logins were fine - do not blame login.
- Compute **users-per-runner : in-flight-slots**. Any gate that limits concurrent operations throttles the steady state, not just the ramp.
- If the workload has a **rendezvous** (matchmaking, pairing, barriers), a low in-flight ratio makes partners fail to coincide, every attempt burns the full server-side wait timeout, and throughput collapses *while the server goes idle*. The tell is unmistakable: more requested load -> fewer server threads, idle database, zero failures, near-zero throughput.

## Verdict table

| Failures | DB active | Server threads | Throughput | Verdict |
|---|---|---|---|---|
| many, early | low | normal | low | unramped stampede - re-run with a ramp |
| none | high, locks | high | plateau | real DB capacity |
| none | ~idle | climbing, many blocked in one frame | plateau | app-side bug (sync-over-async); scaling out multiplies fragility rather than fixing it |
| none | ~idle | **falling** | collapses as load rises | harness gate / rendezvous starvation - the number is the harness's, not the server's |

## Reporting rules

- Distinguish "confirmed bug" from "confirmed cause of the collapse". A blocking constructor can be real and still not be what failed the run.
- A ceiling measured with a throttling harness is a **floor** on server capacity, never a ceiling.
- Put the diagnosis in the product, not just the transcript: a thread-count readout plus an on-demand stack histogram grouped by innermost own-code frame turns a terminal-only diagnosis into one button.
