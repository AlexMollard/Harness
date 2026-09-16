---
name: aspire-docker-restart-recovery
description: "Recover an Aspire stack after a Docker/WSL restart when services run with 0% CPU and no logs, or a LAN hostname refuses connections while localhost works."
---

# Aspire + Docker restart recovery

Two failures follow a Docker Desktop / WSL restart. Both present as "the stack is broken"
while every dashboard resource still reports **Running / Healthy**, because Aspire only
watches processes, not whether they are serving.

## Symptom A: services alive, silent, 0% CPU

`.NET` processes exist, no port is bound, console logs show only Aspire's dependency-wait
lines ("Finished waiting for resource 'cache'") and **not one line of app output**.

Diagnose in this order:

```bash
# 1. Are they spinning or blocked? 0.00s over 5s = blocked on I/O, not a livelock.
powershell -NoProfile -Command "$ids=<pids>; $a=Get-Process -Id $ids|Select Id,CPU; Start-Sleep 5; ..."

# 2. Do they listen at all?
netstat -ano | grep -E ':(8090|9080|5000)\s' | grep LISTENING

# 3. THE TELL - every container exited at the same moment with the same code:
docker ps -a --format "{{.Names}}\t{{.Status}}"     # Exited (255) N minutes ago, all of them
docker run --rm hello-world                          # daemon itself healthy again
```

Simultaneous `Exited (255)` across unrelated containers (including ones from other projects)
= daemon-level event, not a per-container fault. The services were blocked on DB/cache sockets
that Docker's proxy accepted but never served, which is why they never logged.

### Persistent containers need recreating, not restarting

`docker start` on a container that survived a daemon crash **cannot re-establish port
publishing**. Confirm before blaming the app:

```bash
docker inspect <container> --format '{{json .HostConfig.PortBindings}} {{json .NetworkSettings.Ports}}'
# HostConfig wants a binding, NetworkSettings.Ports is empty  ->  nothing is forwarded
```

Fix: check the data lives in a named volume, then remove and let Aspire recreate.

```bash
docker inspect <container> --format '{{json .Mounts}}'   # verify a named volume exists
aspire stop
docker rm -f <persistent-db> <persistent-clickhouse> <event-stream> <orphaned session containers>
docker volume ls | grep <project>                        # volumes survive; data is safe
aspire run
```

Verify with real requests, not resource state: `curl -m 6 -o /dev/null -w '%{http_code}'`
against a health endpoint and the gateway.

## Symptom B: LAN hostname refuses connections, localhost works

Aspire's DCP publishes **container** ports loopback-only, so a gateway container listens on
`127.0.0.1:<port>` and nothing else. Reaching it by machine name requires a
`netsh portproxy` rule. A network-stack restart makes `iphlpsvc` drop the **listeners** while
the **rules** stay in the registry — so `netsh interface portproxy show all` looks correct
while nothing is bound.

```powershell
netsh interface portproxy show all                       # rules present ... but
Test-NetConnection <machine> -Port <port>                # TcpTestSucceeded = False
```

Repair by re-adding each rule; **do not restart `iphlpsvc`** — it stops the NAT/ICS dependents
Docker's networking rides on.

```powershell
netsh interface portproxy delete v4tov4 listenaddress=$ip listenport=$p
netsh interface portproxy add    v4tov4 listenaddress=$ip listenport=$p connectaddress=127.0.0.1 connectport=$p
```

Repair only ports that actually fail the connect test: re-adding a live rule drops connections
through it, which mid-load-test looks like server failures.

Make it durable with a scheduled task running the same check at boot and every 10 minutes
(`schtasks /Create /SC ONSTART /RU SYSTEM` plus `/SC MINUTE /MO 10`).

## Gotchas

- Elevation from bash: `"C:\Program Files\gsudo\Current\gsudo.exe"` is not directly
  executable. Use `powershell -NoProfile -Command "& 'C:\...\gsudo.exe' powershell -File <script>"`,
  with the payload in a `.ps1` file rather than an inline command string.
- Aspire MCP tools go stale after a stack restart: `refresh_tools` → `list_apphosts` →
  `select_apphost` before `execute_resource_command`.
- Dashboard login tokens regenerate every run; a bookmarked `?t=` URL is always wrong after a
  restart. Get the current one from `aspire ps`.
