<!--
English handout template. scripts/make-handout.py writes this same text in English;
the two change together, so any language translated from either stays in step.
Render it yourself from params.json (never paste params.json into the chat).

Variables:
  {dash}       http://<wg_subnet>.1:<dashboard_port>        e.g. http://10.67.0.1:8088
  {token}      dashboard_token
  {domain}     domain
  {site}       https://<domain>
  {exit_ip}    exit_ip
  {relay_ip}   relay_ip                                       relay profile only
  {push_domain} {ntfy_topic} {ntfy_user} {ntfy_pass}          from params.json
  {price_exit}  the monthly price quoted at setup (the host's listed price, before tax); no default
  {price_relay} the relay's monthly price quoted at setup

Rules (the same ones the script applies):
  1. NOTIFICATIONS: use the full block only if ntfy_alert_token or push_domain is set;
     otherwise the one-line "not set up" version.
  2. MONEY: the first two lines always; the third line only in the relay profile.
  3. IF IT STOPS WORKING, the "Technical details" table and the layout row:
     pick the `single` or the `relay` variant, marked below; a variant ends at the
     next marker, heading or rule. Lines marked "relay only" are dropped in the
     single profile (it has no tunnel and no drill).
  4. Output file: handout.md. Send it as a file, with your environment's way of handing over a file.
     Never publish it as a page: it contains the panel code and the alert password.
-->
# Your VPN — the handout

Keep this file. It has everything you need to use the VPN and not call for help over small things.

---

## How to add a device

1. Connect to the VPN from any device that is already set up.
2. Open **{dash}** in a browser.
3. If it asks for a code, enter **{token}**.
4. Press **+ New client**, type a name (for example "Mum phone"), press **Create and show QR**.
5. On the new device open the **WireGuard** app and scan the QR code.

The WireGuard app is free and available everywhere: App Store, Google Play, and wireguard.com for computers.

**If the device is on a network where the VPN won't connect** (a hotel, the underground, office Wi-Fi), pick port **443 (strict networks)** instead of the usual one when creating the device. That kind of connection gets through almost everywhere.

---

## The panel: what it shows

- who is online right now and how much traffic they used;
- a usage graph;
- the list of devices; a spare one can be removed with the cross.

The panel opens **only while you are connected to the VPN**. From outside it does not exist — on purpose, so that no stranger gets in.

**What is NOT collected and stored anywhere:** which sites people open, what they search for, what they watch. Only a megabyte counter per device. That is not "we promise" — it is how the thing is built: logging is off.

The buttons you may need: **Download .conf** — the config file for a computer; **Online** — show only online devices.
<!-- relay only: -->
**All → tunnel** / **All → direct** — everyone through the tunnel / everyone direct.

---

## Notifications on your phone

<!-- NOTIFICATIONS, full version -->
Install the **ntfy** app (App Store / Google Play). In it:

1. Tap **+** → **Subscribe to topic**
2. Turn on **Use another server** and enter: `https://{push_domain}`
3. Topic name: `{ntfy_topic}`
4. Login `{ntfy_user}`, password `{ntfy_pass}`

It only writes when it matters: when something broke and when it fixed itself. The titles are listed at the end of this file.
<!-- relay only: -->
Once a month, at night, the system tests itself — that test also sends a short report, which is normal.

<!-- NOTIFICATIONS, not set up -->
Notifications were not set up.

---

## What it costs

- the server abroad — **{price_exit} a month**
- the domain — **once a year, what the registrar charges**
<!-- MONEY: relay only — add this third line; single stops at two -->
- the server in your country — **{price_relay}**

**The traffic is enough for roughly 10–15 devices in ordinary use, or 4–5 people watching video.** If it starts running short, nothing needs redoing — moving to a server twice the price is enough.

---

## If it stops working

First wait 2–3 minutes.
<!-- FAILOVER: single -->
Everything inside is built so that when something breaks, the system restarts what got stuck by itself and writes to you. Quite often everything comes back on its own within those couple of minutes.
<!-- FAILOVER: relay -->
Everything inside is built so that when something breaks, people are moved to the fallback route automatically within about a minute — local sites stay reachable, foreign sites are unavailable for that time. When the main channel is repaired, everyone is moved back, also by itself.
<!-- both profiles from here -->

What you can check yourself:

1. **Is there internet at all?** Turn the VPN off on the phone and open any site. If it doesn't open, the VPN isn't the problem.
2. **Open {site} in a browser** — it is an ordinary page that should open from any device, even without the VPN. If it opens, the server is alive.
3. Still nothing — write to whoever set this up and show them this handout. Everything needed to sort it out is in here.

---

## Once a year

The domain **{domain}** has a renewal date. If it isn't renewed, everything stops working. Put a reminder in your calendar a month ahead.

---

## Technical details (not needed while everything works)

Let them sit here — whoever does the repairs will need them.

<!-- TABLE: single -->
| | |
|---|---|
| Domain | `{domain}` |
| Server address | `{exit_ip}` |
| Panel | `{dash}`, code `{token}` |
| Layout | one server abroad |

<!-- TABLE: relay -->
| | |
|---|---|
| Domain | `{domain}` |
| Server address abroad | `{exit_ip}` |
| Relay server | `{relay_ip}` |
| Panel | `{dash}`, code `{token}` |
| Layout | two servers: a relay in your country + an exit abroad |

The keys and passwords are in a separate file, `params.json`. **It must not be lost and must not be forwarded to anyone.** Put it in a cloud drive or a password manager.

<!-- Include only when notifications are set up -->
## What the notifications mean

| Title | Meaning |
|---|---|
| VPN: server not responding | the server isn't responding |
| VPN: server responding again | the server is responding again |
| VPN: server still not responding | the server is still not responding |
<!-- relay only: the rows below -->
| VPN: tunnel down, everyone moved to the fallback route | the tunnel is down, everyone moved to the fallback route |
| VPN: tunnel restored | the tunnel is back |
| VPN: fallback route not responding | the fallback route isn't responding — worth a look |
| VPN: tunnel still down | the tunnel is still down |
| VPN: drill passed / VPN: drill needs a look | the monthly self-test: all good / needs a look |
