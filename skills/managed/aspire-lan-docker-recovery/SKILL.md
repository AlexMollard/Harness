---
name: aspire-lan-docker-recovery
description: "Recover an Aspire stack after a Docker Desktop/WSL restart when services hang silently or the machine's LAN hostname stops answering while localhost works"
---

# Aspire LAN + Docker restart recovery

Use when an Aspire stack misbehaves after Docker Desktop or WSL restarts: services "Running/Healthy" but unresponsive, or the box's LAN name refusing connections that `localhost` still serves.

## Triage first (cheap, decisive)

```bash
# 1. Are containers actually alive, and do they have HOST port bindings?
docker ps --format "{{.Names}}\t{{.Status}}\t{{.Ports}}"
# healthy looks like: 127.0.0.1:56117->6379/tcp
# broken  looks like: 5432/tcp            <- no host binding at all

# 2. Simultaneous Exited (255) across unrelated containers = the DAEMON restarted,
#    not a per-container failure.
docker ps -a --format "{{.Names}}\t{{.Status}}"

# 3. Are the service processes blocked rather than crashed?
#    Alive + 0.00s CPU over 5s + ZERO app log output = blocked on a DB/cache socket
#    that Docker's proxy accepts but never serves.
```

Aspire's dashboard reporting **Running/Healthy is not evidence** here - the wait-gates passed before the backing store died.

## Fix A - persistent container has no port publishing

Symptom: `docker inspect <c> --format '{{json .HostConfig.PortBindings}} {{json .NetworkSettings.Ports}}'` shows bindings requested but `{"5432/tcp":[]}` actual.

Port publishing is fixed at container creation; `docker start` cannot re-establish it. Recreate:

```bash
docker inspect <container> --format '{{json .Mounts}}'   # confirm a NAMED VOLUME holds the data
aspire stop                                              # never pkill
docker rm -f <persistent-db> <persistent-clickhouse> <event-stream> <stale session containers>
aspire run                                               # DCP recreates with bindings; volume reattaches
```

Data lives in the named volume (e.g. `db-data-<title>`), so removal is safe once you have verified the mount.

## Fix B - LAN name refuses connections, localhost works

DCP publishes container ports **loopback-only**. LAN reachability comes from `netsh portproxy`, whose rules persist but whose listeners die with the network stack.

```powershell
# Rules present but nothing bound is the signature:
netsh interface portproxy show all              # lists rules
Test-NetConnection <THISBOX> -Port 5000         # False

# Repair: delete + re-add each UNREACHABLE port (elevated)
netsh interface portproxy delete v4tov4 listenaddress=<lanIP> listenport=<p>
netsh interface portproxy add    v4tov4 listenaddress=<lanIP> listenport=<p> connectaddress=127.0.0.1 connectport=<p>
```

- **Never** `Restart-Service iphlpsvc`: it stops NAT/ICS dependents that Docker's networking uses.
- **Only** repair ports that actually fail a TCP probe - re-adding a live rule drops the connections flowing through it (mid-load-test that reads as server failures).
- Make it self-healing with a SYSTEM scheduled task at boot + every 10 minutes running the same probe-then-repair script.

## Related gotcha: advertised hostnames

If the AppHost derives URLs from an env var (e.g. `ASP_HOSTNAME`), setting it machine-wide changes every advertised URL and dashboard link to the machine name. That is correct for anything remote (a remote worker reading `localhost` targets *itself* and gets connection-refused), and harmless locally since both names hit the same listener. Delete the variable rather than blanking it - `?? "localhost"` fallbacks do not catch an empty string and you get `http://:5000`.

## gsudo from bash

The shim is not directly executable from bash. Use:

```bash
powershell -NoProfile -Command "& 'C:\Program Files\gsudo\Current\gsudo.exe' powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\path\to\script.ps1'"
```
