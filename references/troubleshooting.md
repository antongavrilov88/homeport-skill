# Troubleshooting

Work top to bottom and stop at the first mismatch. First thing: take a state
snapshot with `sudo /usr/local/sbin/vpn-diag.sh` (it prints the path to the file).

## The certificate is not being issued

Symptom: the installer prints `certificate for … failed` six times and exits.

Almost always DNS. Check:

```bash
dig +short A <domain> @1.1.1.1        # must return the exit's IP
dig +short A push.<domain> @1.1.1.1
```

- Empty or someone else's address → the A records are not set or have not
  propagated. Set them, wait (TTL), run the installer again (after cloud-init:
  `bash /opt/vpn-kit/exit/install.sh`).
- The address is right but it still fails → check that 80/tcp is open from the
  outside (`curl -I http://<domain>`) and that nginx serves `/.well-known/acme-challenge/`.
- `too many certificates already issued` → you have hit the Let's Encrypt limit
  (5 per domain per week). Wait a week or use a subdomain.

Without a certificate REALITY is useless: active probing gets a TLS error instead
of a real site, and that stands out more than having no VPN at all.

## The install is stuck on apt (`waiting` lines in the log)

Cloud-init on a fresh machine competes with unattended upgrades. The installer
waits up to five minutes and then moves on. If it hangs longer than that:

```bash
ssh root@<IP> 'systemctl stop unattended-upgrades; bash /root/setup-exit.sh'
```

## Clients connect, but there is no internet

```bash
sudo wg show wg-clients            # is there a fresh handshake?
sysctl net.ipv4.ip_forward         # must be 1
sudo nft list table ip vpnnat      # there must be a masquerade rule
```

- No handshake → UDP is not reaching the server. Check the firewall
  (`nft list ruleset | grep dport`) and that the ISP is not cutting the port. Try
  issuing a client on port 443.
- Handshake present, no traffic → almost always NAT or forwarding.
  `systemctl restart wg-quick@wg-clients` recreates the rule.
- Small pages open, large ones hang → MTU. The client config must have
  `MTU = 1280`.

## The tunnel is down (the socks probe fails)

Order of checks on the relay:

1. **No internet from the machine itself** (`curl -sI https://www.gstatic.com`) →
   the relay's provider has a problem. Wait, and tell the person.
2. **443 to the exit is silent, 22 answers** → on the exit, the server abroad,
   check whether Xray is listening (`ss -lntp | grep 443`). It is → filtering at
   the border; go to "Replacing the exit" in `operations.md`.
3. **Neither 443 nor 22, ping does not get through** → check the machine's state
   with `provision-do.py list`. Alive but not answering → the IP got blocked →
   replace the machine.
4. **TLS serves the wrong certificate** (`openssl s_client -connect <IP>:443
   -servername <domain>` shows a foreign issuer) → traffic is being tampered with →
   replace the machine.
5. **Everything is reachable, but Xray on the relay complains** → `journalctl -u xray -n 40`,
   `xray run -test -c /usr/local/etc/xray/config.json`, and compare the UUID,
   public key, shortId and path against the exit's config
   (`/root/vpn-kit/exit-summary.txt`). A mismatch in even one of them means
   silence with no clear error.

## `failover: true` and it is not coming back

- The tunnel answers but the failover is still in place → the watchdog is waiting
  for 5 (or 20 when flapping) successful probes. More than two hours → restore by hand:

```bash
sudo nft add element ip xray_tproxy proxied_src { $(python3 -c "import json;print(', '.join(json.load(open('/var/lib/vpn-monitor/failover-set.json'))))") }
sudo systemctl restart vpn-watchdog
```

- The tunnel does not answer → this is not a failover bug, it is a real outage; see above.

## `fallback_ok: false`

A separate emergency: the fallback route is dead. The tunnel still works for now,
but there is nowhere to fail over to. Check the direct route out of the relay:

```bash
curl -s -m 8 --interface 10.67.0.1 -o /dev/null -w '%{http_code}\n' https://www.gstatic.com/generate_204
```

Usually the NAT or routing rules are to blame. `systemctl restart wg-quick@wg-clients`.
A quiet but dangerous failure — tell the person right away.

## The `proxied_src` set is empty, but `failover: false`

Either someone took everyone off the tunnel by hand, or this is the normal state
right after install. Restore from `/var/lib/vpn-monitor/failover-set.json` if it exists;
if not, ask who should be put back.

## The panel does not open

- Open it only from inside the VPN, at `http://<subnet>.1:8088`. It does not exist
  from the outside — that is by design.
- `systemctl status vpn-monitor`, `journalctl -u vpn-monitor -n 30`.
- `admin code required` (`нужен код администратора` on a server installed before 0.6.0) → the code is in `/etc/vpn-monitor/admin-token`.

## An existing client's config cannot be downloaded

The panel hands out a config only if the key was created in the panel itself —
private keys of clients added by hand are not stored on the server. The only way
out: issue a new client and delete the old one.

## Notifications are not arriving

```bash
sudo python3 -c "import importlib.util;s=importlib.util.spec_from_file_location('w','/usr/local/sbin/vpn-watchdog.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m);print(m.notify('VPN: test','Checking the alert channel.'))"
```

`False` → look at `/etc/vpn-monitor/alerts.json`. The watchdog tries each target
three ways (through the tunnel, directly, and via the WireGuard interface) — if
none of them got through, check the ntfy token and that `https://push.<domain>` opens at all.
Every alert is also posted, every time, to the public topic on `ntfy.sh`
(`ntfy_public_topic`, no login) — it is a second channel that is always on, not one
used only when yours fails. If the test still returns `False`, `ntfy.sh` is unreachable too.

**The message is in the app, but the phone never woke up (iPhone).** iOS keeps no
background connection to a self-hosted ntfy, so the phone only sees the alert once
you open the app by hand. The server has to hand the wake-up to `ntfy.sh`:
`/etc/ntfy/server.yml` needs `upstream-base-url: "https://ntfy.sh"` (only the bare
fact that a message exists travels there — a message ID under a hashed topic name, no text; the phone then fetches
the text from your server). Installers since this release write that line themselves;
on a server built earlier, add it by hand and `systemctl restart ntfy`. Then **delete
the subscription in the app and add it again** — without that the phone never
re-registers for the upstream wake-up and nothing changes.

## Pitfalls we have already fallen into

- **SSH to the relay may itself go through the tunnel.** If the tunnel is down, you
  have no control until you turn off the VPN on your own machine. The relay's
  address is in the `bypass` set, but verify that before you need it.
- **A drill cuts the channel you are sitting on.** `vpn-drill.sh` breaks the relay's
  route out on purpose, so an SSH session running through this VPN dies with it — and
  a foreground script dies with the session, leaving the block in place until the
  safety timer lifts it. That is why a plain run now detaches into its own systemd
  unit and returns at once, and why it postpones itself while clients are pushing
  traffic (`--force` overrides, `--check` never breaks anything).
- **`pkill -f <pattern>` kills your own session** if the pattern appears in its
  command line.
- **`xray run -test` requires the `.json` extension** on the config file.
- **Long commands over SSH get cut off by the tool's timeout.** Run them in the
  background via `setsid nohup ... & disown`, writing output to a file.
- **Benchmarks on a two-core machine choke SSH.** Run them in the background.
- **`/etc/nftables.conf` deliberately does NOT contain `flush ruleset`** — it recreates
  only its own `inet filter` table. The `xray_tproxy`, `wgports` and `vpnnat` tables
  live separately and are brought up by their own units (`xray-tproxy-route`,
  `vpn-wgports`, `wg-quick@wg-clients`). If the rules are gone after a
  reboot — `systemctl restart xray-tproxy-route vpn-wgports wg-quick@wg-clients`.
