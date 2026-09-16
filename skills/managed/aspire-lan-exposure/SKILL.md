---
name: aspire-lan-exposure
description: "Expose or repair LAN access to an Aspire stack's containerized endpoints (Caddy/proxy, Valkey/Redis) when other machines get connection refused, or after a Docker/WSL restart breaks it"
---

# Aspire LAN exposure and portproxy repair

Use when a machine other than the AppHost host cannot reach an Aspire-hosted
endpoint, or when a previously working `http://<machine>:PORT` starts refusing
while `localhost:PORT` still works.

## Root cause (do not re-derive)

Aspire's DCP publishes **container** ports loopback-only: a stable
`127.0.0.1:PORT` listener proxies to a random docker host port. Nothing binds
the LAN interface. `ASP_HOSTNAME` only rewrites *advertised* URLs
(`GetHostName()` in `Orchestration/AppHost/Extensions.cs` feeding `WithUrl` and
`GAMECORE_URL`) — it changes no binding, so the dashboard can advertise a name
that has no listener.

## Triage

```bash
# 1. Is it loopback-only?
netstat -ano | grep -E ":(5000|6379)\s" | grep LISTENING   # expect 127.0.0.1 + [::1] only
# 2. Do bridging rules exist?
powershell -NoProfile -Command "netsh interface portproxy show all"
# 3. Are they actually bound?
powershell -NoProfile -Command "(Test-NetConnection <HOST> -Port 5000 -WarningAction SilentlyContinue).TcpTestSucceeded"
```

Rules listed but `TcpTestSucceeded=False` => iphlpsvc dropped the listeners
(typically after a Docker Desktop / WSL network restart).

## Fix: delete + re-add each rule (elevated)

Re-adding rebinds immediately. **Never** `Restart-Service iphlpsvc` — it errors
with `ServiceHasDependentServices`, and `-Force` stops the NAT/ICS dependents
Docker networking rides on.

```powershell
$ip = '<LAN-IP>'
foreach ($p in 5000, 6379) {
    netsh interface portproxy delete v4tov4 listenaddress=$ip listenport=$p | Out-Null
    netsh interface portproxy add    v4tov4 listenaddress=$ip listenport=$p connectaddress=127.0.0.1 connectport=$p | Out-Null
}
```

Run it elevated from bash (the gsudo shim is not exec'able by path):

```bash
powershell -NoProfile -Command "& 'C:\Program Files\gsudo\Current\gsudo.exe' powershell -NoProfile -ExecutionPolicy Bypass -File '<abs path>.ps1'"
```

Also open the firewall once per rig:
`New-NetFirewallRule -DisplayName '<name>' -Direction Inbound -LocalPort 5000,6379 -Protocol TCP -Action Allow`.

## Related failure it is often confused with

Every container `Exited (255)` at the same timestamp = Docker daemon/WSL
restart, not an app fault. Aspire-launched .NET services then sit **alive at
0.00s CPU with zero console output** (blocked on DB/cache sockets before the
logging pipeline flushes) while the dashboard still shows Running/Healthy.
Confirm with `docker ps -a`, a CPU delta sample, and
`mcp__aspire_list_console_logs` (only dependency-wait lines, no app output);
recover by restarting the whole stack, then repair portproxies as above.

## Client-side corollary

Any address handed to *other* machines must never be `localhost`. Rewrite it at
the point it is published (e.g. job payloads:
`Regex.Replace(url, "//(localhost|127\\.0\\.0\\.1)", "//" + (ASP_HOSTNAME ?? MachineName))`)
and default such fields to the machine name, not localhost.
