#!/usr/bin/env python3
"""The handout for the person: one page, everything needed, no jargon.

    python3 make-handout.py --params params.json --out handout.md --price-exit '<price>'

The text is English and mirrors references/lang/handout-en.md section by
section (same sections, same variables, same rules); change the two together.
For any other language the agent translates the generated file.

Hand it over as a file (SendUserFile). Do NOT publish it: it holds the panel
code and the notification password.
"""
import argparse, json


T = """# Your VPN — the handout

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

The buttons you may need: **Download .conf** — the config file for a computer; **Online** — show only online devices.{route_buttons}

---

## Notifications on your phone

{notify}

---

## What it costs

{money}

**The traffic is enough for roughly 10–15 devices in ordinary use, or 4–5 people watching video.** If it starts running short, nothing needs redoing — moving to a server twice the price is enough.

---

## If it stops working

First wait 2–3 minutes. Everything inside is built so that when something breaks, {failover}

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

| | |
|---|---|
| Domain | `{domain}` |
| Server address{exit_label} | `{exit_ip}` |{relay_row}
| Panel | `{dash}`, code `{token}` |
| Layout | {scheme} |

The keys and passwords are in a separate file, `params.json`. **It must not be lost and must not be forwarded to anyone.** Put it in a cloud drive or a password manager.
{meaning}"""

# The alert titles as vpn-watchdog.py and vpn-drill.sh send them.
MEANING = """
## What the notifications mean

| Title | Meaning |
|---|---|
| VPN: server not responding | the server isn't responding |
| VPN: server responding again | the server is responding again |
| VPN: server still not responding | the server is still not responding |
"""
MEANING_RELAY = """| VPN: tunnel down, everyone moved to the fallback route | the tunnel is down, everyone moved to the fallback route |
| VPN: tunnel restored | the tunnel is back |
| VPN: fallback route not responding | the fallback route isn't responding — worth a look |
| VPN: tunnel still down | the tunnel is still down |
| VPN: drill passed / VPN: drill needs a look | the monthly self-test: all good / needs a look |
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--params", required=True)
    ap.add_argument("--out", default="handout.md")
    ap.add_argument("--price-exit", required=True,
                    help="the exit's monthly price quoted at setup (the host's listed price); no default: hosts change prices")
    ap.add_argument("--price-relay", default="")
    a = ap.parse_args()
    p = json.load(open(a.params, encoding="utf-8"))
    single = p.get("mode") == "single"
    gw = p.get("wg_subnet", "10.67.0") + ".1"
    dash = f'http://{gw}:{p.get("dashboard_port", 8088)}'
    notifications = bool(p.get("ntfy_alert_token") or p.get("push_domain"))

    if notifications:
        notify = f"""
Install the **ntfy** app (App Store / Google Play). In it:

1. Tap **+** → **Subscribe to topic**
2. Turn on **Use another server** and enter: `https://{p["push_domain"]}`
3. Topic name: `{p["ntfy_topic"]}`
4. Login `{p["ntfy_user"]}`, password `{p["ntfy_pass"]}`

It only writes when it matters: when something broke and when it fixed itself. The titles are listed at the end of this file.
"""
        if not single:
            notify += "\nOnce a month, at night, the system tests itself — that test also sends a short report, which is normal.\n"
        meaning = MEANING + ("" if single else MEANING_RELAY)
    else:
        notify = "\nNotifications were not set up.\n"
        meaning = ""

    money = f"- the server abroad — **{a.price_exit} a month**\n- the domain — **once a year, what the registrar charges**"
    if not single:
        money += f"\n- the server in your country — **{a.price_relay or 'what its host charges a month'}**"

    if single:
        failover = ("the system restarts what got stuck by itself and writes to you. "
                    "Quite often everything comes back on its own within those couple of minutes.")
        scheme = "one server abroad"
        relay_row = ""
        exit_label = ""
        route_buttons = ""
    else:
        failover = ("people are moved to the fallback route automatically within about a minute — "
                    "local sites stay reachable, foreign sites are unavailable for that time. "
                    "When the main channel is repaired, everyone is moved back, also by itself.")
        scheme = "two servers: a relay in your country + an exit abroad"
        relay_row = f'\n| Relay server | `{p.get("relay_ip", "—")}` |'
        exit_label = " abroad"
        route_buttons = "\n**All → tunnel** / **All → direct** — everyone through the tunnel / everyone direct."

    text = T.format(dash=dash, token=p.get("dashboard_token", ""), notify=notify.strip(),
                    money=money, failover=failover,
                    site=f'https://{p["domain"]}', domain=p["domain"],
                    exit_ip=p.get("exit_ip", "—"), exit_label=exit_label,
                    relay_row=relay_row, scheme=scheme, route_buttons=route_buttons,
                    meaning=meaning)
    open(a.out, "w", encoding="utf-8").write(text)
    print(a.out)


if __name__ == "__main__":
    main()
