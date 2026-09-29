# What the person does by hand

Everything else the skill does itself. This file covers only what technically cannot be done for them: it needs their card, their email, their phone in their hand.

**How to use it:** one section at a time. What has to happen and what you verify is here. The words are in `lang/en.md` under the same section number; for any other language, translate from it as you go. The exact buttons of a hosting provider are in `providers/<provider>.md`. Never hand the person the whole file: someone who receives a wall of ten sections closes it and does not come back.

**Tone:** they owe you no technical vocabulary. Every step starts with why — `lang/en.md` has the sentence.

---

## 1. Hosting account

**Why:** the exit lives there — the computer abroad the internet will go through.

**What happens:** they register with the provider, confirm the email, attach a payment method. Click path and the ~$1 verification hold: `providers/digitalocean.md` (or the file of the provider they chose).

**Where it stalls:** the payment method. Providers refuse cards from some countries; the country list stays in the provider file — do not recite it. What usually works: a card from a bank in another country, PayPal on an account outside the country, a virtual card (Wise, Payoneer).

**No card that works at all:** say so plainly and pick a provider from "No card that works?" in `provisioning.md`. Then the person creates the machine themselves (Ubuntu 24.04) and gives you access; everything else is the same, minus the automatic creation.

**Never:** suggest an account in someone else's name, or any way around the card check.

**You verify:** nothing yet — the key check in §2 covers the account.

---

## 2. The access key (API token)

**Why:** so that you create the server instead of dictating twenty clicks.

**What happens:** they generate a token — full access, 30-day expiry — and paste it to you. It is shown once. Buttons: `providers/digitalocean.md`.

**Must be said aloud:** the key passes through the conversation; you revoke it together at the end (`lang/en.md` §2).

**You verify, immediately:** `python3 scripts/provision-do.py check`. "Not active" → the card is not attached → back to §1, in words, no machine creation.

**Revoking:** API → Tokens → three dots → Delete. Remind at goodbye and again in §10.

**Other providers:** there is no key. Skip to SSH access (§7) once they have created the machine.

---

## 3. Domain

**Why:** the main disguise — a real website really answers at the address.

**What happens:** they buy any free, neutral name at a registrar: Namecheap, Porkbun, Cloudflare, or one they already use (a registrar in their own country is fine — the domain's registrar does not have to be abroad). `.com` `.net` `.org` `.me` are fine; `.xyz` `.top` `.click` get blocked in bulk — steer away from them.

**If they already own one:** do not send them shopping. Ask one thing — does anything live on it, a website or email? — and deliver the warning below anyway. If something does live there, it is the wrong domain for this.

**The warning to deliver in full** (`lang/en.md` §3): not a domain they care about; not one that already carries their site or their email; the server's address gets blocked from time to time and the domain carries that history; a blocked domain takes everything on it down.

**You verify:** nothing until DNS (§4/§5).

---

## 4. Pointing the domain at the provider's DNS

**Why:** so that from then on you manage the records yourself, without them.

**What happens:** at the registrar they switch to custom nameservers: `ns1.digitalocean.com`, `ns2.digitalocean.com`, `ns3.digitalocean.com`. Where the setting hides: Namecheap — **Domain** tab → **Nameservers** → **Custom DNS**; Porkbun — **Authoritative Nameservers**; most others — a menu called **Nameservers** / **DNS servers**. A domain registered with Cloudflare cannot change nameservers at all — go to §5.

**What to expect:** fifteen minutes to a few hours, rarely a day. Nothing to re-click. Until then `ns-check` still answers "elsewhere" (exit 2) — that is not a reason to fall back to §5; re-run it.

**You verify:** `python3 scripts/provision-do.py ns-check --domain <domain>` — exit 0: at DigitalOcean, set the records yourself; 2: elsewhere → §5; 3: no DNS from where you run → ask them to look up the NS record at dnschecker.org and read it to you.

**If they would rather not move the nameservers** (email on the domain, say): do not insist. §5.

---

## 5. Three records by hand — only when the nameservers stay at the registrar

**What happens:** in the registrar's **DNS records** / **Zone** section they add three records:

| Type | Name (Host) | Value | TTL |
|---|---|---|---|
| A | `@` | `<exit IP>` | 300 |
| A | `www` | `<exit IP>` | 300 |
| A | `push` | `<exit IP>` | 300 |

**The pitfalls to pre-empt** (`lang/en.md` §5): `@` vs. an empty field vs. the full domain; TTL is optional; type A only — not AAAA, not CNAME.

**You verify:** `python3 scripts/provision-do.py dns-check --domain <domain> --ip <IP>` — yourself, every few minutes, and tell them when it is through. Certificates follow by themselves once the records resolve.

---

## 6. [relay] The server in the users' country

**Why:** their home ISP sees a dull connection to a domestic address instead of a round-the-clock link abroad; and a domestic address is the one that has a chance on an allow-list-only network.

**What happens:** they order the cheapest Ubuntu 24.04 VPS with a dedicated IPv4 at a provider in that country — `providers/yandex-cloud.md`, `providers/generic-ubuntu.md`, and the dated relay-capable list in `provisioning.md`; a flat-rate VPS beats a metered cloud for a household. Check the traffic quota (everything passes twice) and that it is a different provider from the exit's.

**What you need from them:** the address, the login (root, or a user with passwordless sudo) and the password or key — providers email these right after payment.

**If you have to move it, move it before the QR codes go out.** The relay's address is written into every device config, so a relay that turns out not to be reachable on the users' mobile networks has to be replaced *before* anyone has scanned a code — afterwards it means re-issuing every device. That is exactly what the mobile-data test on the first device is for (step 7; `lang/en.md` §8): first `alt_port` 443, and only then a different provider in the same country.

**Say it straight** (`lang/en.md` §6): the password passes through the chat; after the install you show them how to change it (`passwd`, one command).

**You verify:** `ssh` in; `lsb_release -a` says 24.04; `curl -4 https://api.ipify.org` prints the address they gave you.

---

## 7. Running one command on the server

Only when you have no SSH access from where you run.

**What happens:** you send `setup-exit.sh` or `setup-relay.sh` (with your environment's way of handing over a file) and two lines; they open a terminal and paste. The three things that confuse everyone — the invisible password, the `yes/no` question, the password asked twice — are scripted in `lang/en.md` §7, together with how to open a terminal on Mac, Windows and Linux and the PowerShell paste quirk.

**The lines** (substitute the real address; `sudo bash` instead of `bash` when the login is not root):

```bash
scp ~/Downloads/setup-relay.sh root@ADDRESS:/root/
ssh root@ADDRESS 'bash /root/setup-relay.sh'
```

**You verify:** ask for the last twenty lines. The installers print `=== EXIT MACHINE READY ===` or `=== RELAY READY ===` followed by the service list and, on the relay, `tunnel works` with the exit's IP. Anything else → `troubleshooting.md`. Then `bash /usr/local/sbin/vpn-verify.sh` through them or over SSH.

---

## 8. The app on the devices

**What happens:** the official WireGuard app — App Store / Google Play / Mac App Store / `wireguard.com/install` for Windows. In the app: **+** → **Create from QR code** → scan the code the panel shows → name → save → switch on. On a computer: download the `.conf` from the panel → **Import tunnel(s) from file**. The phone asks once whether to allow the VPN configuration: yes.

**The first device** cannot come from the panel — the panel is reachable only from inside the VPN. You issue it from the server's shell (`operations.md`, "Issue a device from the shell") and send the QR image as a file; the person scans it from the screen. When you have no shell to the server, the person runs that call themselves and `qrencode -t ansiutf8 < /root/device.conf` shows the QR in their terminal, or they reach the panel through `ssh -L 8088:127.0.0.1:8088 root@<IP>` and `http://127.0.0.1:8088`. Every later device: the person, in the panel, from a device that is already connected. People who are not in the room get a screenshot of the QR or the `.conf` over a messenger; the message is deleted once scanned.

**The panel:** opened from a device that is already on the VPN, at `http://<wg_subnet>.1:<dashboard_port>` (default `http://10.67.0.1:8088`); the admin code is asked once per browser. **Its labels are English** — the glossary is in `lang/en.md`; for a person who does not read English, say so once before this step and name each button as it is written.

**[relay] Order:** the first device is a phone on mobile data with Wi-Fi off → "does youtube open?" → switch the bypass on for that device → the same question → only then QR codes for everyone else. Phones on strict operators: port 443. The two warnings (high UDP ports; what failover looks like) are in `lang/en.md` §8.

**You verify:** "does youtube open?" from them; `sudo wg show wg-clients` on the server shows a fresh handshake for the new peer. [relay] After the bypass: the device's address is in the `proxied_src` set and the panel shows it as **tunnel**.

---

## 9. Notifications

**What happens:** the **ntfy** app → **+** → **Subscribe to topic** → **Use another server** on → `https://push.<domain>` → topic, login, password from `params.json` (`ntfy_topic`, `ntfy_user`, `ntfy_pass`).

**You verify:** send a test from the server (the one-liner in `operations.md`) and ask whether it arrived. Every alert goes to two places at once, always: the self-hosted ntfy and a public topic on ntfy.sh (`ntfy_public_topic`, no login). If the self-hosted ntfy did not come up, the public topic is the only one that works; say which one they are subscribed to.

---

## 10. Cleaning up

A day or two after the install, one message (`lang/en.md` §10): revoke the access key (§2); delete the server password and the key from the conversation; store `params.json` in a password manager or a cloud drive; a calendar reminder a month before the domain renewal.
