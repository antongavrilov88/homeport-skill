# Operations

## The panel

`http://<subnet>.1:8088` — only from inside the VPN (by default `http://10.67.0.1:8088`).
The access code is in `/etc/vpn-monitor/admin-token`; the browser remembers it on its own.

From outside, for the operator:

```bash
ssh -L 8088:127.0.0.1:8088 <relay, or the exit in the single profile>   # then http://127.0.0.1:8088
```

In the panel: who is online, how much they have used, who takes which
route, issuing a new client with a QR code, removal, and the direct-domain list.

## Switch an existing server's panel to English

Servers installed before 0.6.0 keep the Russian panel and Russian notifications until you do this; nothing changes on its own. It replaces three files on the machine that runs the panel (the relay, or the exit in the `single` profile) and restarts two services. Only words change: the three files have the same logic in every release, and clients, routes, the admin code and the stats stay as they are. Do it while the panel says **Tunnel OK** (or the Russian «Туннель в порядке»), not during a failover.

From the skill's folder, on the operator's computer:

```bash
scp scripts/payload/common/dashboard.html scripts/payload/common/vpn-monitor.py \
    scripts/payload/common/vpn-watchdog.py root@<server>:/root/
ssh root@<server> 'install -m644 /root/dashboard.html /usr/local/share/vpn-monitor/index.html \
  && install -m755 /root/vpn-monitor.py /root/vpn-watchdog.py /usr/local/sbin/ \
  && rm /root/dashboard.html /root/vpn-monitor.py /root/vpn-watchdog.py \
  && systemctl restart vpn-monitor vpn-watchdog \
  && systemctl is-active vpn-monitor vpn-watchdog \
  && curl -s http://127.0.0.1:8088/ | grep -o "<title>[^<]*</title>"'
```

Expect `active` twice and `<title>VPN traffic</title>`; with a non-default `dashboard_port`, use that port. Then reload the panel in the browser. The monthly drill's notifications stay in Russian in this release. Re-running an installer built from 0.6.0 or later puts the same English files in place.

## Issue a device from the shell

The panel listens only inside the VPN and on localhost, so the very first device — or any device while the panel is unreachable — is issued through the panel's own API, on the machine that runs it (the relay, or the exit in the `single` profile):

```bash
curl -s -X POST http://127.0.0.1:8088/api/client-new \
  -H "X-Admin-Token: $(cat /etc/vpn-monitor/admin-token)" \
  -d '{"name":"Phone","port":51821,"route":"wg"}' \
  | python3 -c 'import json,sys,base64; r=json.load(sys.stdin); sys.exit(r["error"]) if "error" in r else None; png=base64.b64decode(r["qr"]); open("/root/device.conf","w").write(r["config"]); open("/root/device.png","wb").write(png) if png else None; print(r["ip"], "png" if png else "no qr (qrencode missing) — use the .conf")'
```

`port` 443 for a phone on a strict network; `route` `reality` to put the device through the tunnel at once (relay only). Copy `/root/device.png` (the QR) or `/root/device.conf` down with `scp` and hand it over as a file; then delete both from the server. Without a way to move files, `qrencode -t ansiutf8 < /root/device.conf` draws the QR in the terminal and a phone scans it from the screen. The same call is what the **+ New client** button makes.

## Everyday commands (on the relay)

```bash
# who is in the tunnel right now
sudo nft list set ip xray_tproxy proxied_src

# switch one client, instantly
sudo nft add element ip xray_tproxy proxied_src { 10.67.0.6 }
sudo nft delete element ip xray_tproxy proxied_src { 10.67.0.6 }

# everyone into the tunnel at once
sudo nft add element ip xray_tproxy proxied_src { 10.67.0.0/24 }

# full failover to the direct route
sudo systemctl stop xray-tproxy-route

# state
curl -x socks5h://127.0.0.1:1080 https://api.ipify.org    # must be the exit's IP
sudo cat /var/lib/vpn-monitor/health.json
sudo bash /usr/local/sbin/vpn-verify.sh                   # full check

# direct domains (leave straight from the relay)
sudo nano /etc/vpn-monitor/direct-domains.txt
sudo python3 /usr/local/sbin/vpn-split.py

# state snapshot for diagnosis
sudo /usr/local/sbin/vpn-diag.sh

# send a notification by hand (is the alert channel alive?)
sudo python3 -c "import importlib.util;s=importlib.util.spec_from_file_location('w','/usr/local/sbin/vpn-watchdog.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m);print(m.notify('VPN: test','Checking the alert channel.'))"
```

Switching from the panel also writes the set into `/etc/xray/xray-tproxy.nft` so
it survives a reboot. If you edit `nft` by hand, put the `elements` into that file
yourself, otherwise everything reverts after a reboot.

## How the watchdog works

| State | Probe interval | What happens |
|---|---|---|
| healthy | 30 s | probe through socks: gstatic, then cloudflare |
| first failure | 5 s | fast-confirmation mode |
| 3 failures in a row (~45–60 s after the break) | — | **failover first**: the contents of `proxied_src` are saved and cleared, clients move to the direct route, a notification goes out; **repair second**: Xray is restarted |
| down | 20 s | Xray restart about every 5 minutes, a reminder once an hour |
| 5 successful probes | — | clients restored from the saved list + notification |
| flap protection | — | if there were 3+ failovers within an hour, restore needs 20 successful probes instead of 5 |
| background, every 10 min | — | a separate check of the fallback route; a dead fallback = its own alert |

The order — move people first, repair second — is deliberate: an Xray restart drops
connections by itself, and doing it before the failover means breaking people's
connectivity twice.

In the `single` profile (one machine) the watchdog runs in a reduced mode: it probes
the channel, restarts Xray and sends a notification. There is nowhere to move
people to.

## The drill

```bash
sudo /usr/local/sbin/vpn-drill.sh --check   # readiness check only, breaks nothing
sudo /usr/local/sbin/vpn-drill.sh           # a real outage of ~2 minutes
sudo /usr/local/sbin/vpn-drill.sh --force   # ... even if people are online right now
```

The full run: readiness check → block the path to the exit (the server abroad) →
wait for failover → lift the block → wait for restore → compare the client set
before and after → report via notifications. A safety net via
`systemd-run --on-active=10min` lifts the block even if the script dies.

**What the household sees.** For a minute or two foreign sites stop opening while
local sites stay reachable; the failover moves everyone onto the direct route and
the drill puts them back. Nobody has to touch a phone.

**It postpones itself while people are using the channel.** Before breaking
anything the drill adds up the last five minutes of traffic in
`/var/lib/vpn-monitor/stats.db` — or, if that database is missing, looks for a
WireGuard handshake in the last 180 s. Above 5 MB it sends a "postponed"
notification, writes `skip: clients active` to the log and exits 3 without touching
the route. `--force` runs it regardless; use it only when the person has said that
everyone can wait.

**A plain run detaches from your session.** The drill breaks the very path an
operator usually reaches the server through, so it re-execs itself as the transient
unit `vpn-drill-manual` and returns immediately — the report still arrives as a push
if your SSH session dies with the channel, and the block is never left standing by a
script that died halfway. `--fg` does the run in the current process instead; the
timer units already run under systemd, so they take the `--fg` path by themselves and
needed no change. If `systemd-run` fails, the script says so and continues in the
foreground.

It runs on its own on the night of the 1st of each month; the readiness check runs
every Monday. Log: `/var/lib/vpn-monitor/drill.log`.

The drill is the only way to know that automatic failover works. A failover that is
configured but has never been tested is not a failover.

## Replacing the exit after its IP gets blocked (~15 minutes)

The order is strict.

1. `provision-do.py list --tag vpn-exit` — note the old machine's id and IP. If there
   is more than one machine, clean that up first.
2. Create the new one **with `--ssh-key`** and the same `out/setup-exit.sh`.
3. Point the `@`, `www` and `push` A records at the new IP and wait for the
   certificates (watch `/var/log/vpn-kit-install.log` on the new machine).
4. Copy over from the old machine, if it is still alive: `/var/www/<domain>` and `/var/lib/ntfy`.
5. On the relay, replace the address in `/usr/local/etc/xray/config.json`
   (`outbounds[0].settings.vnext[0].address`), then
   `xray run -test -c /usr/local/etc/xray/config.json` and `systemctl restart xray`.
   Do not forget the `bypass` set in `/etc/xray/xray-tproxy.nft` — the old address is in there.
6. Verify: `curl -x socks5h://127.0.0.1:1080 https://api.ipify.org` → the new IP.
7. **Only now** run `provision-do.py destroy --id <old id> --tag vpn-exit`
   and confirm it is gone from the list. This step is mandatory, not optional:
   a forgotten machine is a bill every month.

The REALITY keys do not need to change on replacement — they live in `params.json`
and simply move to the new machine along with the installer.

## Traffic and bills

```bash
sudo wg show wg-clients transfer     # per device, since the interface came up
```

The panel shows 14 days of history. Estimate the monthly usage: above 800 GB on a
1 TB quota, it is time either to move to the $12 droplet or to find out who is downloading.

Once a month it is worth looking through the full `provision-do.py list` output:
check that no stray machines have appeared.

## What lives where

**The relay**

| Path | What it is |
|---|---|
| `/usr/local/etc/xray/config.json` | Xray config (REALITY client) |
| `/etc/xray/xray-tproxy.nft` | interception; the `proxied_src` and `bypass` sets |
| `/etc/xray/wgports.nft` | redirect udp/443 → WireGuard port (unit `vpn-wgports`) |
| `/usr/local/sbin/vpn-*.py`, `vpn-*.sh` | monitor, watchdog, split routing, diagnostics, drill |
| `/usr/local/share/vpn-monitor/index.html` | the panel |
| `/etc/vpn-monitor/` | `config.json`, `admin-token`, `alerts.json`, `direct-domains.txt`, `names.json` |
| `/var/lib/vpn-monitor/` | `stats.db` (14 days), `health.json`, `failover-set.json`, `drill.log`, diagnostic snapshots |
| `/etc/wireguard/` | server keys, client configs, `removed/` — archive of deleted clients |

**The exit**

| Path | What it is |
|---|---|
| `/usr/local/etc/xray/config.json` | inbound VLESS+XHTTP+REALITY |
| `/etc/nginx/sites-enabled/` | `:80` (ACME and redirect) and `127.0.0.1:8443` (self-steal target, ntfy) |
| `/var/www/<domain>/` | the cover site |
| `/etc/ntfy/server.yml`, `/var/lib/ntfy/` | notifications |
| `/root/vpn-kit/exit-summary.txt` | install summary (mode 600) |
| `/var/log/vpn-kit-install.log` | install log |
