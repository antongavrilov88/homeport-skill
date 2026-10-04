# How it is built and why

## The `relay` profile: two machines

```
devices (WireGuard) ──► relay inside the home country ──VLESS+XHTTP+REALITY──► exit abroad ──► internet
                                   └──────────► direct route out of the relay (the fallback)
```

- **The first leg** is plain WireGuard, entirely inside the home country. It never
  changes: any edit means a visit to every device.
- **The second leg** is VLESS + XHTTP + REALITY on Xray, port 443/tcp. This is the
  leg that breaks when filtering tightens, and it is the leg you can repair
  and rebuild without anyone having to touch their devices.
- **Who goes through the tunnel** is decided by the `proxied_src` set in nftables on
  the relay. Empty = everyone goes direct. Switching is instant, from the panel or
  with a command.
- **Split routing**: domains from the direct-domain list and, if `home_geoip` is set,
  home-country addresses leave straight from the relay. Everything else goes into
  the tunnel.

## Why REALITY and not just WireGuard out

Modern DPI makes its decision on a combination of signals without decrypting the
stream. Here is what we set against each one:

| Signal | Why bare WireGuard gets caught | What this design does |
|---|---|---|
| Packet shape | fixed header, recognized from the first packet | from the outside it is ordinary TLS 1.3 |
| TLS fingerprint (JA3/JA4) | UDP on 443 is an anomaly in itself | uTLS impersonates Chrome completely |
| Active probing | they knock on the port, get no answer → VPN | self-steal: the prober gets a real site with a valid certificate |
| Flow behavior | constant symmetric UDP to a foreign data center | XHTTP multiplexes into 1–2 long H2 connections with padding |
| Destination address | foreign hosting = a reason for a closer look | **we do not win this one** — it is the main residual risk |

**Why XHTTP and not classic REALITY+Vision.** Vision opens a separate TLS session
for every client connection. For a relay with several people behind it, that is a
burst of simultaneous handshakes to the same SNI — exactly the pattern DPI answers
with a throttling freeze of the connection for a couple of minutes. XHTTP keeps
one or two long connections and never produces that pattern.

**Why our own domain (self-steal) and not someone else's SNI.** When you disguise
yourself as someone else's site, the network owner, the IP and the SNI do not match,
and active probing sees that. Xray warns outright that impersonating Apple/Microsoft
leads to the IP getting blocked. With our own domain on our own machine, the prober
gets a real site — because it is a real site.

## Why the relay exists — and when you can do without it

Technically, devices can talk straight to the exit, the server abroad, over
VLESS+REALITY. What you lose without the relay:

1. Every user's home ISP starts seeing a round-the-clock TLS session to a foreign
   data center instead of a connection to a local cloud. That is exactly the signal
   DPI uses to pick candidates for a closer look.
2. Control. Changing the exit, changing the route, failing over — today that is one
   command on one machine. Without the relay it is a visit to every user.
3. Automatic failover and split routing live on the relay; the panel moves to the exit.
4. If things move to allowlists, a local cloud address is more likely to stay
   permitted than a foreign one.

What you gain: 30–50 ms less latency, no bill for the relay's outbound traffic,
one machine fewer, and no dependence on a provider that is legally required to
filter when ordered to.

**Bottom line:** if the users are inside the filtered country and changing settings
on their devices is expensive, you need the relay. If the person is setting up a
VPN for themselves and is willing to reinstall a config once every six months, the
`single` profile is the more honest choice money-wise.

## The `single` profile: one machine

```
devices ──WireGuard──► the exit ──► internet
devices ──VLESS+REALITY──┘  (for the Hiddify / v2rayNG apps)
```

WireGuard is what the panel issues and what every device gets by default,
phones inside the filtered country included: plain WireGuard, straight to the
server abroad. REALITY on this layout is the `vless://` link from
`client-link.py`, for people who use a VLESS app (Hiddify, v2rayNG) — the
better choice on networks that detect or slow down plain WireGuard, as is the
`relay` profile. The panel shows WireGuard clients; REALITY clients are issued
as a `vless://` link and do not appear in the panel.

Automatic failover is impossible in this profile — there is nowhere to switch to.
The watchdog still runs: it probes the channel, restarts Xray and sends a
notification.

## What we considered and rejected

- **Vision instead of XHTTP** — the risk of two-minute throttling freezes on a relay
  with several users.
- **Someone else's SNI** — Xray's own warning about the IP getting blocked.
- **Direct VLESS for everyone instead of WireGuard on the first leg** — breaks both
  stealth and manageability (see above).
- **A brochure site for a made-up company with testimonials** — poor cover (a blank
  placeholder page looks more suspicious than a live site) and simply dishonest.
  The cover must be real and our own.
- **The person's personal site on the same domain** — ties their name to the address
  the VPN traffic goes through, and goes down with it when the IP gets blocked.

## Limits and money

- **Traffic** is the main ceiling. The s-1vcpu-1gb DigitalOcean droplet comes with 1 TB/month.
  Real consumption for a family of several people is on the order of 10–15 GB/day,
  i.e. 300–450 GB. Bottom line: **10–15 ordinary devices** or 4–5 active HD
  viewers. The cure is the next size up (2 TB), not a redesign.
- **CPU** tops out at roughly a gigabit — which is to say it does not top out.
- **The relay's outbound traffic** is billed separately at its provider's rates.
  Split routing (home-country domains bypassing the tunnel) cuts it noticeably.

## Risks and horizons

An engineering estimate, not statistics.

| What happens | How likely | What it looks like | What to do |
|---|---|---|---|
| The exit's IP gets blocked | high, 3–6 months | everything stops for everyone, but the machine itself is alive | new machine + A records + the address in the relay config, ~15 minutes |
| Behavioral throttling freeze | medium, 6–12 months | stalls while the tunnel is alive | tune XHTTP xmux/padding/intervals |
| The relay's provider starts filtering | medium, 6–12 months | only the tunnel is down, and plain HTTPS to the exit does not get through either | move the relay to another provider |
| Allowlists on home networks | medium, ~12 months | almost nothing opens for people | second leg behind a CDN; the first leg is already right |
| They learn to catch REALITY itself | low, within a year | mass complaints across the whole country | XHTTP via a CDN, or Hysteria2 |
| The fallback turns out to be no fallback | medium, on carrier-restricted networks | failover works, but only local sites open until the exit is replaced | a standby exit (next section); until it exists, replace the exit fast |

## A standby exit instead of the direct fallback

**Not built.** A design note, kept here so the next person does not have to derive it again.

Today the watchdog has exactly one place to put people when the tunnel dies: the
relay's own direct route. On an ordinary network that is a real fallback —
everything still opens, just without the tunnel. On a carrier-restricted network it
barely is one: local sites stay reachable, foreign sites are unavailable, which is
usually the part the household bought the VPN for. So the fallback that reads fine in
a drill report is weakest exactly where the `relay` profile is most needed.

**The shape.** A second exit — call it B — at a different provider and in a different
region from A, with its own domain, its own cover site and its own REALITY key pair.
The relay carries both as outbounds and fails over A → B → direct instead of
A → direct. B costs one more small machine and carries traffic only while A is down.

**What it buys.** An exit whose IP gets blocked stops being an outage: people land on
B within the same minute or two it now takes to move them to the direct route, and
replacing the banned exit turns from an emergency into unhurried maintenance. Monthly
drills stop being visible to the household at all — the drill blocks A, everyone
lands on B, foreign sites keep opening.

**What it would touch**, if it is ever built:

- `scripts/gen-secrets.py` — a second REALITY key pair and a second domain.
- `scripts/build-installers.py` — the exit installer parameterised per exit, so B is
  built from the same payload as A.
- the relay's Xray config — a second outbound, and the routing rules that choose it.
- `scripts/payload/common/vpn-watchdog.py` — failover order becomes A → B → direct,
  plus a liveness probe for B so nobody is ever moved onto a dead standby.
- `scripts/payload/common/vpn-drill.sh` — the drill blocks A only, and a pass becomes
  "everyone is on B", not "everyone is on the direct route".
- the panel — show which exit is live right now; otherwise nobody can tell.

**Why it is not built.** It doubles the exit-side cost and the number of things that
can rot unnoticed, to repair a fallback that may well be good enough for the
households we actually have. It waits until paying users confirm that the direct
fallback is useless for them.

## Privacy

Collected: byte counters and the time of the last WireGuard handshake, per device.
That is all.

Not collected: domains, destination addresses, DNS queries, ports, content.
Xray access logs are off on both machines (`"log": {"access": "none"}`).
The panel listens only on the VPN's internal address and localhost — it does not
exist from the outside.
