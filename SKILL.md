---
name: homeport
description: 'Use when someone wants a personal VPN on a server they rent themselves — "set up my own VPN", "VPN for my parents", "get around the blocking", "deploy an Xray / REALITY / WireGuard server", "подними мне впн", "нужен впн родителям", "хочу свой ВПН", homeport (formerly Burrow). Built for a person with no technical background: it asks in plain words, does the work itself and walks the few manual steps button by button. Delivers VLESS + XHTTP + REALITY plus WireGuard, a web panel that issues devices by QR, a watchdog that restarts what fails (automatic failover on the two-server layout), and push alerts to the phone.'
---

# A personal VPN, done for the person

You are setting up a personal VPN on a server the person rents, and you hand over a working thing, not "a server with settings": a panel where the person adds devices by QR, a watchdog that repairs (and, on two servers, re-routes) without them, and a notification on their phone when something is wrong.

## Language

- These instructions are English. **Everything the person reads or hears is in their language** — the one they write to you in.
- Ready-made wording for every human-facing moment is in `references/lang/en.md` and `references/lang/ru.md`, keyed by the same section numbers as `references/human-steps.md`. The Russian file is the wording tested with real families: use it verbatim. For any other language, translate from the English file as you go — the meaning and the warnings, never new steps.
- The handout at the end: Russian → `scripts/make-handout.py` (its built-in text is the tested one). Any other language → fill `references/lang/handout-<xx>.md` yourself from `params.json` (`en` exists; the variables and the rules are at the top of the template).
- The scripts print their console messages in Russian too (same reason). Where a line matters, it is quoted below; otherwise the exit code is your signal.
- **The web panel and the watchdog's push notifications are in English**, whatever language the person speaks; name the buttons in English and explain them in the person's language. Two exceptions: the monthly drill's notifications (`relay` only) are still in Russian — the handout lists what they mean — and a server installed before 0.6.0 keeps the Russian panel until it is switched (`references/operations.md`, "Switch an existing server's panel to English"). The panel is opened a few times a year; the VPN itself needs no panel.

## Where you are running

| You have | What changes |
|---|---|
| A shell **and** network access to the hosting API and the servers (Claude Code on a laptop, a desktop session with a terminal) | Full automation: you create the server, set DNS, install over cloud-init or SSH, verify. The steps below assume this. |
| A shell but **no network to the outside** (claude.ai with code execution: a sandbox that cannot reach the person's server or the hosting API) | You still generate keys and installers — the scripts are pure Python. The person does the clicking: creates the server in the provider's console with `out/setup-exit.sh` pasted into the "user data" field, runs the two SSH lines for everything else, and reads command output back to you. **Say this at the very start, once**, so nobody waits for a connection you cannot make. `provision-do.py` is useless here; the console click paths are in `references/providers/`. The person needs their own SSH access to the machine (their own key at creation, or the provider's root-password reset); the first device then comes from the panel through their own port-forward or from a QR printed in their terminal (step 7). DNS checks: ask them to open dnschecker.org. |
| No shell at all | Stop. Keys cannot be generated in a chat. Point them to Claude Code or to the hosted agent (link in the README). |

## The person is not technical

Assume they know no technical word at all. They did not come to "deploy infrastructure"; they came because their mother's YouTube stopped working.

**How to talk:**

- **One action at a time.** Ask a question, wait for the answer. Give an instruction, wait for "done". Never a list of eight items: they will close the window and not come back.
- **Say why, every time.** People get stuck not on buttons but on "why am I doing this". One sentence before each step.
- **No jargon.** Not "generate an API token" but "we need a long password that lets me rent a server on your behalf". Not "delegate the domain" but "we need to tell them that this company is now in charge of your address". If a word is unavoidable, explain it right there, in brackets, once — and do not repeat the explanation.
- **Do not report technology.** "Brought up Xray 26.3.27 with a REALITY inbound" is not for them. "The server is ready, I checked, it works" is.
- **Say how long things take.** "This will install for about ten minutes, I'll tell you when it's done" — otherwise they decide it broke.
- **Do not ask what you can decide yourself.** Region, machine size, ports, subnet, file names are your problem, not theirs.
- **Mistakes are never their fault.** "That didn't go through, let's try another way", not "you entered it wrong".

For every manual step, `references/human-steps.md` says what has to happen and what you verify, and `references/lang/<xx>.md` gives the words. Take **one section at a time**, retell it in your own words in their language, wait for confirmation.

## Order of work

Do not skip steps and do not reorder them: each one relies on the check at the end of the previous one.

### 0. One question chooses the layout

Ask this first, in plain words (with AskUserQuestion if you have it; the questions of this step are the only place where you ask several things in one message):

> **Where are the people who'll use this, and does their network restrict direct foreign connections or only allow listed IP ranges (typical on carrier-restricted mobile networks)?**

| What they answer | Profile |
|---|---|
| Abroad, or somewhere the internet is not filtered: "just me, I travel", "friends in a few countries", "I live abroad and need services from home" | `single` |
| In a country with filtering, but on ordinary networks: a VPN app on their phone connects fine on mobile data, and you can reach their devices when something changes | `single` |
| Their network restricts direct foreign connections or only allows listed IP ranges — carrier-restricted mobile networks first of all; or it is a household whose phones you cannot keep reconfiguring | `relay` |
| They do not know | One follow-up, still in plain words: "On their phone, with Wi-Fi off, does any VPN app connect at all?" If nobody can check, take `single` and say that a relay can be added later, at the price of a new QR code on every device. |

Do not ask about "topology" or "relay" by name, and do not turn the one question above into a questionnaire about their networks. You choose; they describe their people. If their first message already answers it, say your reading in one sentence and ask only what is left.

- **`single`** (default) — one server abroad. Devices connect to it directly; the panel, the watchdog and WireGuard live on it. This is the path the landing page describes.
- **`relay`** — a small server in the users' home country in front of the same server abroad. Devices talk WireGuard to the relay, a home-country address that stays reachable on carrier-restricted networks where a foreign one does not; the relay carries one disguised connection across the border; when the exit gets blocked you replace it and nobody at home touches their phone. Everything specific to this profile is marked **[relay]** below.

In the same message ask, in their words (wording: `lang/<xx>.md` §0):

- **"Do you have your own address on the internet — a domain?"** Yes and they control it / no / no idea what that is. For "no": one sentence on what it is, what it costs and why it is needed (it is the disguise: from outside, someone just visits some website).
- **"Do you have an account with DigitalOcean or another hosting provider?"** DigitalOcean is the automated path. Another provider works too, with more clicking on their side. No account at all: **warn right now** that it needs a payment method the provider accepts — a card that works internationally, or PayPal. This is where most setups stall, and it is better to find out now than an hour in.
- **"Do you want your phone to tell you when something breaks?"** Yes / no.
- **[relay]** one more, after the answer that picked the profile: **"Can a small server be rented in the country where they live — by you, or by someone there with a local card?"** If not, the relay is impossible; fall back to `single` and say why in one sentence.

**Right after the answers, state the cost** — one paragraph, no request for confirmation (`lang/<xx>.md` §0, per profile): about $6 a month for the server abroad, about $10 a year for the domain, **[relay]** plus a small domestic server, typically $4–8 a month on a flat-rate plan (metered clouds can cost more for a household that watches video).

If the session runs on a schedule and there is nobody to ask — **do not start**. Creating servers costs money and cannot be undone.

### 1. Collect what is missing

Walk `references/human-steps.md` **one section at a time**, in this order: account (§1) → access key (§2) → domain (§3) → pointing the domain (§4 if they are willing to move the nameservers to DigitalOcean, §5 if they would rather keep them at the registrar). Provider-specific click paths are in `references/providers/<provider>.md`; the words are in `lang/<xx>.md`. Skip what they already have (an account with a card, a domain they own) — one sentence to say so. A domain they already own still gets the §3 warning, and one question: does anything live on it — a site, email? If yes, it is the wrong domain.

The moment you have the key, **check that it is alive** — do not postpone:

```bash
export DO_TOKEN=...
python3 scripts/provision-do.py check
```

The script answers in Russian: `статус: active` is what you want; `аккаунт не активен` means the card is not attached — say so in words and go back to §1; do not try to create a machine. The first line, `аккаунт: <email>`, is the address to use for `--email` in the next step.

**Say out loud, once and not in passing:** the key passes through this conversation, so at the end you will revoke it together. Remind them again when you say goodbye.

With a provider other than DigitalOcean there is no key: the person creates the machine themselves following the provider file, and you get SSH access instead (§7 has the words). §4 applies only when the domain's DNS will live at DigitalOcean; with another provider the records are set at the registrar (§5) or in that provider's DNS. Everything else is the same.

### 2. Keys and SSH

```bash
python3 scripts/gen-secrets.py --domain <domain> --mode <single|relay> \
    [--home-geoip <country code>] [--email <email>] \
    --site-title "<title>" --site-tagline "<tagline in the person's language>" > params.json
```

- `--home-geoip` — **[relay] only**: the users' home country (`ru`, `ir`, `cn`, … any code Xray's GeoIP knows). Its addresses — banks, government sites — then leave the relay directly instead of through the tunnel, and stop complaining about a foreign address.
- `--site-tagline` — the built-in default is Russian. Always pass one in the person's language; the cover site is rewritten in step 4 anyway.
- `--email` — the person's real address (the one `check` printed): certificate-expiry warnings go there. Without it they go to `admin@<domain>`, a mailbox that does not exist.

`params.json` is the single source of truth from here on. **Never show its contents in the chat and never put it in a project or a shared page**: it holds the private key.

Create and upload the SSH key yourself; do not burden the person with it:

```bash
python3 scripts/provision-do.py new-key --name vpn-kit --out ~/.ssh/vpn-kit
```

### 3. The server abroad (the exit)

```bash
python3 scripts/build-installers.py --params params.json --out ./out
python3 scripts/provision-do.py create --name vpn-exit --tag vpn-exit \
    --ssh-key <id from new-key> --user-data out/setup-exit.sh --region <region>
```

Pick the region yourself, nearest to the users (`single`) or to the relay (**[relay]**): `fra1` / `ams3` / `lon1` Europe, `sgp1` Asia, `blr1` India, `nyc3` / `tor1` / `sfo3` the Americas, `syd1` Australia. People spread over continents: nearest to the majority. Do not ask — they do not know what the codes mean. Building the installer before the machine's address exists is fine: the exit detects its own public address at install time.

As soon as you have the address — DNS, while the machine boots:

```bash
python3 scripts/provision-do.py ns-check --domain <domain>       # who answers for the domain
python3 scripts/provision-do.py dns --domain <domain> --ip <IP> --names @ www push
python3 scripts/provision-do.py dns-check --domain <domain> --ip <IP>
```

`ns-check` exit 2 ("not at DigitalOcean") means two different things: if the person changed the nameservers less than a day ago, it has simply not propagated yet — re-run it every few minutes and set the records the moment it returns 0; only if they kept their nameservers at the registrar walk them through §5 (three records by hand) and **run `dns-check` yourself** every few minutes. Do not ask "has it propagated?" — check, and tell them. The installer waits for DNS for about six minutes and then gives up on the certificate; if DNS was late, re-run it over SSH: `bash /opt/vpn-kit/exit/install.sh 2>&1 | tee -a /var/log/vpn-kit-install.log` (the kit stays unpacked there after cloud-init).

The install runs by itself from cloud-init, 5–10 minutes. Tell the person how long, and use the pause: explain what comes next, or do §8 (the app on the phone) ahead of time.

Note: the installer sits in the machine's metadata, readable by any local process. For the exit that is harmless — its secrets live there anyway. **Never deliver the relay installer through cloud-init or metadata.**

Write the address into `params.json` as `exit_ip`.

**If the server already exists** (they could not pay DigitalOcean and went to another provider, or they already run one): deliver `out/setup-exit.sh` and run it as root. Delivery options are in `references/provisioning.md`; the conversation is `human-steps.md` §7.

### 4. Verify the exit before going any further

```bash
bash /usr/local/sbin/vpn-verify.sh    # on the machine itself
curl -sI https://<domain> | head -3    # from outside: 200 and a real certificate
```

Do not continue until both agree. `curl` refuses a bad certificate, so `HTTP/2 200` there already proves the certificate is real. No certificate almost always means DNS — `references/troubleshooting.md`.

**Take the alert token** from `/root/vpn-kit/exit-summary.txt` (the line `ntfy alerts-токен tk_…`) and write it into `params.json` as `ntfy_alert_token`. The exit's own watchdog already has it from this run; the relay build and any later rebuild take it from `params.json`, and without it they only reach the public fallback topic.

**The cover site.** The template that landed in `/var/www/<domain>/` is a page of self-hosting notes, in Russian. Two things to do now, not "some day":

- If the person does not write in Russian, rewrite the page in their language before you hand anything over — three honest paragraphs about anything of theirs (a hobby, notes, a photo archive). A Russian page on a server on another continent for a user who does not read it is a mismatch a reviewer notices. How: over SSH, replace `/var/www/<domain>/index.html` with a plain static page in the same shape (title, a few dated notes, `<html lang="xx">` for their language; the Russian original in `scripts/payload/site/index.html` shows the structure), keep a copy at `/root/vpn-kit/index.html`, then `curl -s https://<domain> | grep -c <a word from the new text>`. **Every run of the installer regenerates that page from the Russian template**, so do the rewrite after the last installer run, and after any later re-run copy your version back and check again.
- Say to them, in their words (`lang/<xx>.md`, "Between the steps"): the page exists so that a check sees an ordinary website; the same template on a dozen addresses becomes a fingerprint, so the text should become their own. Offer to write it with them — thirty seconds of work that measurably improves the disguise.

### 5. [relay] The relay, in the users' country

The skill does not create this machine: domestic providers have no common API. Walk the person through §6 (`references/providers/yandex-cloud.md`, `generic-ubuntu.md`; the dated list of relay-capable hosts is in `references/provisioning.md` — prefer a flat-rate VPS over a metered cloud), then rebuild:

```bash
python3 scripts/build-installers.py --params params.json --out ./out
```

The rebuild is mandatory: the first `setup-relay.sh` had neither the exit's address nor the alert token.

Deliver and run it **over SSH only** (`references/provisioning.md`). If you have SSH access, do it yourself and the person need not hear about it. If not — §7: the terminal, the invisible password, the `yes` question, all spelled out in `lang/<xx>.md`.

Check: `bash /usr/local/sbin/vpn-verify.sh`. Write `relay_ip` into `params.json`.

**Tell the person in plain words** (`lang/<xx>.md`): right now everyone connects directly and the bypass is not on yet. That is deliberate: first make sure the connection works, then switch the bypass on one device at a time and watch that nothing fell over.

**What the relay does about allow-lists, and what you say about it.** The first hop is WireGuard to a domestic address, on `51821/udp` and also on `443/udp` for networks that cut everything else. A domestic address is *more likely* to stay reachable on an allow-list-only network than any foreign one — more likely, not guaranteed. That is why the first device is tested on mobile data before anyone else gets a QR code (step 7). If a network lets nothing through even on 443, say plainly that no protocol gets around an allow-list; the honest answer beats a week of "try again".

### 6. [relay] The drill

Mandatory: it is the only way to know the automation works rather than merely being configured.

```bash
sudo /usr/local/sbin/vpn-drill.sh --check    # safe, breaks nothing
```

A full run — a real two-minute outage — **only with the person's consent and when nobody is using the VPN**. Ask it the way `lang/<xx>.md` puts it: "Want me to test it for real? I'll break the main channel for two minutes and watch the system get itself out. If nobody is watching a film right now, this is the moment." After that it happens by itself once a month, at night.

**Your own session is part of the blast radius.** The drill breaks the relay's route out — if you reach this server *through* this VPN, your SSH session drops in the middle of the run. That is expected, and it is why a plain run detaches into its own systemd unit and hands the prompt straight back: start the drill, let the session go, come back in 3–5 minutes and read `tail -n 20 /var/lib/vpn-monitor/drill.log` (the verdict also arrives as a push).

If anyone is pushing traffic at that moment the drill postpones itself instead of running (`skip: clients active`, exit 3) — that is the design, not a failure. **Never pass `--force` unless the person has said, in so many words, that everyone can wait**: it runs a real outage on top of people who are using the connection.

(`single` has nothing to fail over to, so there is no drill. The watchdog still probes, restarts Xray and notifies.)

### 7. The first device

Add devices **with the person, in the panel** — not for them. They have to walk the path once with their own hands, or the second device brings them back to you anyway.

**The first device is the exception, in both profiles:** the panel is reachable only from inside the VPN, and nothing is inside it yet. Issue that one device yourself, from the server's shell (`references/operations.md`, "Issue a device from the shell"): it returns the config and a QR image — send the QR as a file, the person scans it from the screen. Say two things with it: that this one code passed through the chat and they can replace it from the panel later if they want, and the privacy sentence (`lang/<xx>.md`), because this is the first time the panel comes up.

Guidance-only mode (no shell to the server from where you run): the person runs that one-liner themselves over SSH, then `qrencode -t ansiutf8 < /root/device.conf` prints the QR in their terminal and the phone scans it from the screen; or they open the panel through their own port-forward, `ssh -L 8088:127.0.0.1:8088 root@<IP>` and `http://127.0.0.1:8088` in their browser, and create the device there like any later one.

From the second device on, by §8: the person opens the panel from the device that is already connected → **+ New client** → the new device scans the QR. Wait for "it works" before counting the step done. Ask directly: "Open youtube.com — does it open?" People who are not in the room get a screenshot of the QR or the `.conf` file over a messenger the person trusts — say that the file is a key and the message should be deleted once scanned.

**[relay]** The order matters here:

1. The first device is a phone **on mobile data, Wi-Fi off**, on the users' side. Connect; "does youtube open?" — that is the direct route through the relay.
2. Then switch the bypass on for that one device (the route switch on its row in the panel, or **Route: through the tunnel** when creating it) and ask the same question again.
3. **Only after that hand out QR codes to anyone else.** Verify from a phone on mobile data first — a relay that only works over home Wi-Fi is not verified.
4. **If Wi-Fi works and mobile data does not**, deal with it before anything else, in this order: re-issue that device on `alt_port` 443 (**443 (strict networks)**) and test on mobile data again; if it still will not connect, the relay's own address is not getting through that network, and the fix is a **different provider in the users' country**, not another setting. This is why the test comes before the QR codes: the relay's IP is written into every config the panel issues, so moving the relay later means re-issuing every device.
5. Two warnings the person needs now, not after the first incident (`lang/<xx>.md` §8): mobile operators sometimes cut UDP on high ports — issue phones on port 443 when in doubt; and if their operator starts dropping the tunnel, the watchdog moves everyone to the direct route within a minute or two — the internet keeps working, without the bypass — and moves them back when the tunnel returns. "The VPN is on but sites don't open" is that state, not a broken system.

A spare entrance past the relay for the operator, if they are technical and want one: `python3 scripts/client-link.py --params params.json --label home`. In `single` this link is the normal way for Hiddify / v2rayNG users; an ordinary person does not need it either way — do not load them with it.

### 8. Notifications and the handout

By §9 — subscribing to alerts. Check immediately that they arrive: send a test from the server and ask whether it came.

Build and hand over the handout, in the person's language:

```bash
python3 scripts/make-handout.py --params params.json --out pamyatka.md     # Russian: the tested wording
```

Any other language: render `references/lang/handout-<xx>.md` from `params.json` into `handout.md` (the English template exists; the rules are at the top of the file). Same content, same sections, same variables as the script.

Send it as a file (SendUserFile, or whatever file hand-over your environment has). **Never publish it as a page**: it contains the panel code and the alert password. The Russian text prices the domain in roubles, in `relay` calls the relay "the server in the home country", and in `single` still mentions the monthly self-test that only the relay has — the script's tested wording; if a line is wrong for this family, say so in one sentence or correct that line in the generated file, not in the script.

### 9. Say goodbye

A short message, no technical detail:

- what works now and how to add devices (one line — the rest is in the handout);
- **revoke the access key** — with the exact path from §2;
- `params.json` is theirs: if it is on your machine, send it as a file now; they keep it somewhere safe (a password manager, a cloud drive) and delete it from the conversation;
- set a reminder for the domain renewal.

A day later, write first and ask whether everything works. Small problems surface on the second day, and it is easier to sort them out while the person still remembers what happened.

## Profile → parameters

Both profiles end at the same scripts. What differs:

| | `single` | `relay` |
|---|---|---|
| `gen-secrets.py` | `--mode single` | `--mode relay --home-geoip <users' country code>` |
| `--site-title`, `--site-tagline` | in the person's language (the default tagline is Russian) | same |
| `build-installers.py` produces | `out/setup-exit.sh` — no rebuild needed, the exit detects its own address | `out/setup-exit.sh` + `out/setup-relay.sh`; rebuild once `exit_ip` and `ntfy_alert_token` are in `params.json` |
| Exit machine | `provision-do.py create --tag vpn-exit`, region nearest the users; or any Ubuntu 24.04 host by `references/providers/` | same, region nearest the relay |
| Relay machine | — | created by the person at a home-country provider (`providers/yandex-cloud.md`, `generic-ubuntu.md`); installer over SSH only, never cloud-init |
| `params.json` fields you fill in | `exit_ip`, `ntfy_alert_token` | + `relay_ip` |
| Devices connect to | the exit (`51821/udp`, `443/udp`) | the relay (`51821/udp`, `443/udp`) |
| Panel, watchdog, WireGuard live on | the exit | the relay |
| Split routing | none — everything goes through the server | `/etc/vpn-monitor/direct-domains.txt` on the relay (ships seeded with payment and card networks that commonly refuse or step up verification from a data-centre address; add the household's own banks and apps from the panel or the file) plus `home_geoip` |
| Drill (`vpn-drill.sh`) | not installed; nothing to fail over to | `--check` at once; full run with consent; monthly by timer |
| First device | any network | phone on mobile data first, then the bypass, then everyone else |
| `client-link.py` (`vless://`) | the normal path for Hiddify / v2rayNG users | the operator's spare entrance past the relay |
| Whose traffic quota | the exit's (1 TB on the $6 droplet) | the exit's **and** the relay's — everything passes twice |

## Iron rules

1. **One machine per tag at any time.** Before creating: `provision-do.py list --tag vpn-exit`. A forgotten running server is a bill every month, and the person pays it, not you.
2. **Never touch machines without the right tag.** The account may hold other projects. `destroy` demands both the id and the tag and refuses on its own if they do not match.
3. **Never delete the old machine before the new one works**, and never leave it "for a day, just in case". Verified the new one — remove the old one in the same operation.
4. **The WireGuard port on the relay must not change** once people are connected: any change means a visit to every device.
5. **The REALITY private key lives only on the exit.** It goes into no chat, no project, no relay installer — the build step strips it out together with the operator's spare entrance. Verify:
   `bash -c 'S=$(grep -n "^base64 -d" out/setup-relay.sh|cut -d: -f1); E=$(grep -n "^__VPNKIT_PAYLOAD__$" out/setup-relay.sh|cut -d: -f1); sed -n "$((S+1)),$((E-1))p" out/setup-relay.sh|base64 -d|tar xzO vars.sh|grep REALITY_PRIVATE'`
   The expected output is exactly `REALITY_PRIVATE=''` — an empty value. Anything after the `=` means the build is wrong; stop.
6. **The cover site never impersonates someone else's company, shop or review site.** The cover must be real and the person's own. The template in `scripts/payload/site/` is a stub to be rewritten, not something to pass off as somebody's business.
7. **Never help bypass card verification** and never suggest opening an account in someone else's name. If there is nothing to pay with, offer another provider (`references/provisioning.md`, "No card that works?").

## Privacy — say it yourself, before they ask

Collected: byte counters and the time of the last connection, per device. Not collected: sites, searches, addresses, content — logging is off on both machines. The panel is reachable only from inside the VPN.

For the person it sounds like this (`lang/<xx>.md`): "You'll see that your mother's phone used two gigabytes, and you won't see what she watched. Even if you wanted to — the data isn't there."

It is their question number one, even when they do not ask it. Especially when the VPN is for parents or children.

## Files

| | |
|---|---|
| `references/human-steps.md` | **what the person does by hand — what has to happen, what you check** |
| `references/lang/en.md`, `lang/ru.md` | the words for every human-facing moment, by section; `ru` is the tested wording |
| `references/lang/handout-en.md`, `handout-ru.md` | handout templates (the Russian one is generated by the script; the file is its reference copy) |
| `references/providers/<provider>.md` | per provider: layer, automation, payment, click paths, blocked ranges — dated |
| `references/provisioning.md` | provider index, "No card that works?", delivering installers, DNS |
| `references/architecture.md` | how it works and why; what was considered and rejected |
| `references/operations.md` | daily commands, replacing a machine, drills |
| `references/troubleshooting.md` | failure diagnosis, top down |
| `scripts/gen-secrets.py` | keys and passwords for a new install |
| `scripts/build-installers.py` | builds the self-contained `setup-*.sh` |
| `scripts/provision-do.py` | `check`, `new-key`, `create`, `dns`, `ns-check`, `dns-check`, `list`, `destroy` |
| `scripts/make-handout.py` | the Russian handout |
| `scripts/client-link.py` | `vless://` link for the apps |
| `scripts/payload/common/verify.sh` | install check; on the server it is `vpn-verify.sh` |
