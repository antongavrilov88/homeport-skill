# Homeport

**Your own VPN on a server you rent: your own address, not one shared with thousands of strangers.**

Homeport is a free, open-source skill for AI coding agents: plain instructions plus standard-library Python and bash scripts that an agent follows to turn a small server you rent into a personal VPN. You open a hosting account and buy a domain; the agent creates the server on DigitalOcean, installs everything, hands you a web panel in English, and you add devices by scanning a QR code. Tested with Claude Code; other agents that load the open Agent Skills format haven't been tested yet.

How long it takes: your clicks, then about 10 minutes while it installs. A new domain takes 15 minutes to a few hours to go live, and a new hosting account is sometimes reviewed for a few hours.

The server is yours. The domain is yours. The REALITY keys, the panel's admin code and the ntfy password are made on your machine; the WireGuard keys, the server's and every device's, are made on your server. The first device's code passes through the chat with your agent, and you can replace it from the panel; your keys and passwords never pass through Homeport. There is no Homeport account, no Homeport backend, and nothing for anyone to shut down except your own server — which you can rebuild.

> Made for one situation: people you care about live where the internet is filtered, and every "install our app" VPN keeps dying. Works in both directions — reaching services back home from abroad, or reaching the world from behind a filter. Reaching home needs the server *in* the home country: the automated path creates servers only in DigitalOcean's regions (listed in [`references/providers/digitalocean.md`](references/providers/digitalocean.md)); anywhere else you create the server yourself at a provider there — any Ubuntu 24.04 VPS, a few more clicks on your side.

---

## What you get

- **A protocol that looks like ordinary web traffic — on the relay link and for VLESS apps.** VLESS + XHTTP + REALITY on Xray, on port 443, with a real website under your own domain as the cover. To a probe your server *is* a normal HTTPS site, because it is one. It carries the relay → exit hop of the `relay` profile and the `vless://` link for people who use a VLESS app (Hiddify, v2rayNG). On the default one-server layout your devices don't use it: they connect with plain WireGuard, straight to the server abroad. Some networks detect or slow down plain WireGuard; on those, the `relay` profile or a VLESS app is the better choice.
- **WireGuard for the devices.** Phones, laptops, TVs and routers connect with the official free WireGuard app. Scan a QR, flip a switch, done. A second port on UDP/443 for hotel and mobile networks that cut everything else.
- **A web panel** (reachable only from inside the VPN): who is online, how much they used, add or remove a device with a QR code, and on two servers manage the exceptions, the domains that go direct from the relay instead of through the tunnel.
- **A watchdog** that checks the tunnel every 30 seconds, restarts what it can and pushes a notification to your phone. On two servers (the `relay` profile) it also moves everyone to the direct route and back, and a monthly fire drill (a deliberate two-minute outage) proves that failover actually works, not just "is configured". One server has nothing to fail over to, so it has no failover and no drill.
- **Split routing, on two servers only** (the `relay` profile). Apps that refuse VPN connections — banks, government sites — go direct from the home-country relay; everything else goes through the tunnel. Optional per-country GeoIP rule. On one server everything goes through the server.
- **Push notifications** through your own [ntfy](https://ntfy.sh) instance on the same server, and every alert is also posted to a random topic on public ntfy.sh (see [Privacy, stated plainly](#privacy-stated-plainly)).
- **A one-page handout** for the person who will actually use it, in plain words and in their language, generated at the end.

### Two profiles, one question

Your agent asks one thing first: *"Where are the people who'll use this, and does their network restrict direct foreign connections or only allow listed IP ranges (typical on carrier-restricted mobile networks)?"* The answer picks the profile. You don't need to know what any of the below means.

**`single`** (the default) — one server abroad. You, or a few people, anywhere; devices connect straight to it. Simplest and cheapest.

```
devices ──WireGuard──▶ your server abroad ──▶ internet
devices ──VLESS+REALITY──┘   (for Hiddify / v2rayNG users)
```

**`relay`** — for people whose network restricts direct foreign connections or only allows listed IP ranges, or a household whose devices you can't keep reconfiguring. Devices talk WireGuard to a cheap server *inside* the country; that relay carries one disguised connection across the border. When the exit gets banned you replace it and nobody at home touches their phone.

```
devices ──WireGuard──▶ relay (home country) ──VLESS+XHTTP+REALITY──▶ exit (abroad) ──▶ internet
                              └──────▶ direct (automatic fallback)
```

Both profiles end at the same installers with different parameters; the table in [`SKILL.md`](SKILL.md) lists exactly what differs. The provider is a parameter of each server, not of the profile — [`references/providers/`](references/providers/) has one dated file per provider.

---

## Requirements

Whichever way you run it, two things are yours to bring: **a hosting account with a payment method the provider accepts**, and **a domain** — any cheap, neutral name. Python 3 must exist wherever your agent runs the scripts; they are standard library only, including the X25519 key generation.

*Where* you run the skill decides how much of the work your agent can do by itself:

| You run the skill in | What the agent does | What you do |
|---|---|---|
| **Claude Code** on a laptop with SSH — the recommended way | **Tested.** Everything: creates the server, sets DNS, installs, verifies, fixes, writes the handout. | Create the hosting account, add the card, buy the domain, paste one token. |
| **claude.ai** (a paid plan with code execution on; the skill uploaded as a zip) | **Untested** until [homeport-skill#4](https://github.com/antongavrilov88/homeport-skill/issues/4) confirms the release zip installs there. Guidance plus file generation: it makes the keys and the installers, explains every step, reads back the output you paste. **It cannot connect to your server or to the hosting API** — the sandbox has no network to them. It says so at the start; if it seems to hang waiting for a connection, that is the sandbox, not a bug. | Everything that needs a connection: create the server in the provider's console with the installer pasted in, run the two SSH lines it gives you, check DNS at dnschecker.org. |
| **Cowork** (the desktop app) | **Untested.** It should behave like Claude Code when it has a terminal with network access; nobody has run a full setup through it yet. If you do, open an issue and say how it went. | |
| **Other agents with a shell and network** — Codex CLI, Gemini CLI, Cursor | **Untested.** They load the same open Agent Skills format and should behave like Claude Code; nobody has run a full setup through them yet. Clone the skill into your agent's skills folder (see [Quick start](#quick-start)); if you try one, open an issue and say how it went. | |
| **None of the above** | Homeport's agent does the same setup in a chat, for one price — [Homeport site](https://antongavrilov88.github.io/homeport/). | Account, card, invite. |

---

## Quick start

**Claude Code — install it as a plugin.** Type these in Claude Code's prompt, one at a time:

```
/plugin marketplace add antongavrilov88/homeport-skill
```

```
/plugin install homeport@homeport
```

From a shell instead, the same thing is `claude plugin marketplace add antongavrilov88/homeport-skill` and then `claude plugin install homeport@homeport`. Pasting `/plugin …` into a shell fails with "no such file or directory".

To update later, refresh the catalog, update the plugin, and restart Claude Code. The first command alone only refreshes the catalog:

```bash
claude plugin marketplace update homeport
```

```bash
claude plugin update homeport@homeport
```

**Claude Code — or copy the skill** (update with `git -C ~/.claude/skills/homeport pull`):

```bash
git clone https://github.com/antongavrilov88/homeport-skill ~/.claude/skills/homeport
```

Then, in any session: *"set up my own VPN"*, *"VPN for my parents"*, or `/homeport` (`/homeport:homeport` when installed as a plugin).

**claude.ai:** download `homeport-skill.zip` from the [latest release](https://github.com/antongavrilov88/homeport-skill/releases), then Settings → Capabilities → Skills → Upload skill. Start a chat and say what you want. Read the claude.ai row in the table above first: Claude will explain each step and you will run the commands.

**Other agents (untested):** Codex CLI, Gemini CLI, Cursor and anything else that loads the open Agent Skills format. Clone the skill into your agent's skills folder — for Codex CLI that is `~/.agents/skills/homeport`:

```bash
git clone https://github.com/antongavrilov88/homeport-skill <your agent's skills folder>/homeport
```

Nobody has run a full setup through them yet. If you do, [open an issue](https://github.com/antongavrilov88/homeport-skill/issues) and say how it went.

### Upgrading from Burrow

Homeport was formerly Burrow. If you installed it under the old name, remove that install and add the new one. You'll know you're on the old install if Claude Code shows `Plugin burrow not found in marketplace burrow` after an update — the old plugin name no longer exists.

**Plugin install.** Type these in Claude Code's prompt, one at a time:

```
/plugin marketplace remove burrow
```

```
/plugin marketplace add antongavrilov88/homeport-skill
```

```
/plugin install homeport@homeport
```

From a shell instead, the same three steps are:

```bash
claude plugin marketplace remove burrow
```

```bash
claude plugin marketplace add antongavrilov88/homeport-skill
```

```bash
claude plugin install homeport@homeport
```

Then restart Claude Code.

**Copied skill:**

```bash
rm -rf ~/.claude/skills/burrow
```

```bash
git clone https://github.com/antongavrilov88/homeport-skill ~/.claude/skills/homeport
```

The old repository URL keeps redirecting, but the old plugin and folder names no longer receive updates.

---

## What you will do yourself

The skill does everything it technically can. These four things it can't, because they need your card, your email or your phone in hand — and by design Homeport never does them for you:

1. **Create a hosting account** and attach a payment method. DigitalOcean (the s-1vcpu-1gb droplet, 1 TB traffic a month) is the automated path; any Ubuntu 24.04 VPS works with a few more clicks on your side — [Hetzner](references/providers/hetzner.md), [Vultr](references/providers/vultr.md), [anything else](references/providers/generic-ubuntu.md). No card that works? [`references/provisioning.md`](references/provisioning.md) has a dated list of hosts that take crypto or regional cards.
2. **Give your agent an API token** for that account (so it can create the server instead of dictating twenty clicks), and revoke it afterwards. The skill reminds you.
3. **Buy a domain** — any cheap, neutral name you don't care about. It is the cover story, and a domain can get banned along with the IP.
4. **Point the domain** at the server: either delegate it to DigitalOcean nameservers or add three A-records by hand. Step-by-step instructions for the common registrars are built in.

For the `relay` profile you also rent a small VPS in the home country and paste one command into a terminal; the skill walks you through that too, including "the password won't show while you type".

Budget: a small server (DigitalOcean listed the size the skill creates at $6/month before tax on 27 Sep 2026) plus a domain; `relay` adds a small VPS in the home country. Your host and registrar set the prices; the skill tells you the host's listed price before it creates anything.

---

## What the skill puts on your server

Everything is installed by a self-contained `setup-exit.sh` / `setup-relay.sh` that your agent builds locally and delivers via cloud-init or SSH. The installers are idempotent — run them again to fix a half-finished install; existing clients, certificates and tokens are never overwritten.

**Exit server (abroad)**

| Component | Purpose |
|---|---|
| `xray` (pinned version) | VLESS + XHTTP + REALITY inbound on `:443/tcp`, access logging **off** |
| `nginx` on `:80` and `127.0.0.1:8443` | Let's Encrypt challenges, HTTPS redirect, the cover site that REALITY hands to probes |
| `certbot` + renewal timer | Real certificates for your domain and the `push.` subdomain |
| `ntfy` (optional, own domain) | Self-hosted push notifications with per-user access control |
| `nftables` | Default-deny inbound; opens 22, 80, 443 (+ WireGuard ports in the `single` profile) |
| `/var/www/<domain>/` | A generic self-hosting-notes site as cover. **Rewrite it** — the same template on many domains becomes a fingerprint |
| `/root/vpn-kit/exit-summary.txt` | The connection parameters, mode 600 |

**Relay (home country) or the single server**

| Component | Purpose |
|---|---|
| WireGuard `wg-clients` | Device tunnel, `10.67.0.0/24`, port 51821 + redirect from UDP/443 |
| `xray` in TPROXY mode + `nftables` | Routes selected devices (`proxied_src` set) through the disguised tunnel; everyone else goes direct |
| `vpn-monitor` (`:8088`, VPN-only) | The web panel: status, traffic, QR issuing, direct-domain list |
| `vpn-watchdog` (systemd) | Probe every 30 s → repair → notify; fail over to the direct route only on two servers (`relay`) |
| `vpn-drill` (systemd timer, `relay` only) | Monthly failover rehearsal at night; postpones itself while clients are active and runs detached from your SSH session; `--check` mode never breaks anything |
| `vpn-split` (`relay` only) | Rebuilds routing rules from `/etc/vpn-monitor/direct-domains.txt` |
| `vpn-verify.sh`, `vpn-diag.sh` | Install verification and top-down diagnostics |

Config lives in `/etc/vpn-monitor/` and `/etc/wireguard/`; state in `/var/lib/vpn-monitor/`. What the server sends out is listed under [Privacy, stated plainly](#privacy-stated-plainly).

**Languages.** The skill talks to you in whatever language you write in, and the handout comes in that language. The web panel and all push notifications are in English. Still in Russian in this version: the cover-site template (a separate ticket). A server installed before 0.6.0 keeps its Russian panel and notifications until you switch it (`references/operations.md`).

### Privacy, stated plainly

Collected: byte counters and last-handshake time per device. That's it. Not collected: domains, destination IPs, DNS queries, content. Xray access logs are disabled on both machines; the panel listens only on the VPN interface and localhost. You'll see that your mother's phone used 2 GB and you will not see what she watched — even if you wanted to, the data isn't there.

What leaves the server:

- **Device DNS goes to Cloudflare's 1.1.1.1.** Device configs point DNS at `1.1.1.1` (`client_dns` in `params.json`), so Cloudflare sees the names your devices look up, arriving from your server.
- **Every alert's title and text go to public ntfy.sh, always.** The watchdog posts each alert to your own ntfy *and* to a random topic on `ntfy.sh` (`ntfy_public_topic`, `vpn-` plus 16 hex characters) — every time, not only when your own ntfy is down. That topic has no login: anyone who knows its name can read it. The alerts are status messages (tunnel down, back up, drill result); the "tunnel restored" one also lists the devices' VPN-internal addresses.
- **iPhone wake-ups go through ntfy.sh with a message ID only.** iOS can't be woken by your own ntfy, so your ntfy hands `ntfy.sh` a message ID under a hashed topic name — no title, no text. The phone then fetches the alert from your server.
- **Connections that carry none of your data.** The watchdog's reachability probe (`www.gstatic.com/generate_204`, `cloudflare.com/cdn-cgi/trace`, every 30 seconds), Let's Encrypt certificate renewal, and at install time Ubuntu packages, Xray and ntfy downloads from GitHub, and `api.ipify.org` to learn the server's own address.

Everything else stays on your server.

---

## Why REALITY and not plain WireGuard across the border

Where REALITY is used: on the link that crosses the border in the `relay` profile (relay → exit) and on the `vless://` link for people who use a VLESS app (Hiddify, v2rayNG). On the default one-server layout your devices don't use it: they talk plain WireGuard to the server abroad, with exactly the tells below. Some networks detect or slow down plain WireGuard; on those, the `relay` profile or a VLESS app is the better choice.

Modern DPI doesn't decrypt; it classifies. Bare WireGuard has a recognizable first packet, an odd TLS fingerprint (UDP on 443), no answer when probed, and a constant symmetric UDP stream to a foreign datacenter — four tells. REALITY + XHTTP answers each one: the wire looks like TLS 1.3, uTLS mimics Chrome, a probe gets a real site with a valid certificate, and XHTTP multiplexes everything into one or two long padded HTTP/2 connections. The residual tell is the destination itself — a foreign host — which is why the `relay` profile exists.

Why your **own** domain instead of borrowing a big-brand SNI: with a borrowed name the network owner, IP and SNI don't match, active probing sees that, and Xray's own docs warn that impersonating Apple or Microsoft gets your IP banned. With your domain on your server, the probe gets the real site, because it is the real site.

More in [`references/architecture.md`](references/architecture.md) — including what was considered and rejected, and the honest risk table.

---

## Repository layout

```
SKILL.md                     the skill itself — how the agent runs the setup, step by step
references/
  human-steps.md             every manual step: what has to happen and what the agent verifies
  lang/en.md                 the words for every human-facing moment; any other language is the agent's live translation
  lang/handout-en.md         the handout template: the text make-handout.py writes
  providers/*.md             one dated file per hosting provider: layer, automation, payment, click paths
  provisioning.md            provider index, "no card that works?", delivering installers, DNS
  architecture.md            how it works and why; alternatives rejected; risks
  operations.md              daily commands, replacing a banned exit, drills
  troubleshooting.md         top-down failure diagnosis
scripts/
  gen-secrets.py             keys, UUIDs, passwords → params.json (pure Python X25519)
  build-installers.py        packs payload + params into self-contained setup-*.sh
  provision-do.py            DigitalOcean: check, keys, create, DNS, list, destroy
  client-link.py             vless:// link for Hiddify / v2rayNG
  make-handout.py            the handout, in English
  payload/                   what actually lands on the servers (see table above)
skills/homeport/SKILL.md     the plugin entry point: points at the root SKILL.md
.claude-plugin/              marketplace.json and plugin.json for /plugin install
```

Internally the scripts still call themselves `vpn-kit` (`/opt/vpn-kit`, `/root/vpn-kit`) — that's the working name it shipped under; it's not being renamed on the server side to keep tested installers byte-identical.

---

## Hard rules the skill follows

- One server per tag at any time; never touches machines it didn't create; never deletes the old server before the new one is verified.
- The REALITY private key goes into no chat, no project and no relay installer. It exists in `params.json` on your machine, inside `out/setup-exit.sh` (and so in the server's cloud-init metadata when it is created that way) and on the exit server; the build step strips it from the relay installer and the skill checks that it did.
- The cover site is never a fake company, shop or review page. It's a real, boring, honest site — yours.
- Never helps anyone get around a card check, never suggests registering an account in someone else's name.
- Never starts creating servers from an unattended or scheduled session: it costs money and it's irreversible.

---

## Stuck? Want it done for you?

The skill and this guide are free and stay free. If you get stuck, [open an issue](https://github.com/antongavrilov88/homeport-skill/issues) — remove tokens, keys and server addresses from anything you paste. Security problems go through [private reporting](SECURITY.md), not an issue.

If you'd rather not do it at all: Homeport's agent does the setup in a chat for $29 once, paid to Homeport. It opens in January 2027 — [join the waitlist](https://t.me/burrow_vpn_bot); details on the [Homeport site](https://antongavrilov88.github.io/homeport/). Not included: the server and the domain, billed by your providers. Refund: automatic if the check fails; otherwise on request within 14 days. It covers the setup, not your network. At launch: DigitalOcean only. The server stays yours; I never hold your card or your account.

## Who's behind this

I'm Anton Gavrilov, a frontend engineer. I built this for my parents, then for a friend, then wrote it down so an AI coding agent could do it for anyone. Built in public: [LinkedIn](https://linkedin.com/in/agavrilov88).

## License

[MIT](LICENSE). Use it, fork it, sell setups with it — just keep the notice.
