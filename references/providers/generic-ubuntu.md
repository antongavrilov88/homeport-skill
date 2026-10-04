# Any Ubuntu 24.04 server

*For providers that have no file of their own. Tested by this skill: the installers are provider-agnostic; the delivery path over SSH is the one verified on every machine so far.*

| | |
|---|---|
| **Layer** | **exit or relay**, whichever side of the border the machine is on. A relay must be inside the users' country; an exit must be outside it. Never the same provider for both. |
| **Last verified** | — (no dated facts in this file; the static-address row, added 2026-09-29, is a generic checklist, not a provider fact). |
| **Automation** | Manual: the person orders the machine, you install over SSH (or the person pastes two lines — `human-steps.md` §7). |
| **Machine** | Ubuntu **24.04 LTS** (not 22.04, not Debian), 1 vCPU, 1 GB RAM, 10 GB disk, a **dedicated public IPv4** (not behind CGNAT, not "shared IP"), root or a user with passwordless `sudo`, and a traffic quota of 1 TB or more — for a relay count everything twice. That is enough for a gigabit; the ceiling is always traffic, not CPU. |
| **Static address** | For a relay, required (`provisioning.md`, "The relay's address"). In the console, look for the provider's static, reserved, elastic or floating IP section; reserve one in the same region (or zone) as the machine and attach it — or, where the provider can make the address the machine got at creation static, do that once it has passed the phone check (`human-steps.md` §6). Ask the provider before paying: is the public address static, or can it be made static? Does it survive a stop and start, and a re-creation of the machine? What does a reserved address cost, attached and unattached? If the address can change and cannot be reserved, prefer another host for the relay: every device config carries it. |
| **Signup** | Whatever the provider asks — email is the minimum; local hosts commonly want a local phone number and sometimes an ID. Ask the person to read the signup page before paying. |
| **Payment** | Whatever the provider takes. The "No card that works?" list in `references/provisioning.md` names hosts known to accept crypto or regional cards, dated. |
| **Known blocked ranges** | Unknown by definition — check reachability from the users' side before you build anything on it: the phone check in `human-steps.md` §6, a one-page web server on port 80 opened from a phone on the users' mobile data, Wi-Fi off. |
| **Firewall** | Unknown: check the provider's panel for a security group or "firewall" tab and allow the ports of the layer (`provisioning.md`, requirements); on the machine the installer handles nftables. |
| **Quirks** | Some providers ship Ubuntu images with a pre-enabled firewall (`ufw`) or with `unattended-upgrades` running at first boot; the installer waits up to 10 minutes for apt's lock (if the package install still fails, it stops — `troubleshooting.md`) and configures nftables itself. If the provider's console offers a cloud-init field, it is acceptable for the exit installer only, and only if it fits the size limit. |

## Before installing, from the machine

```bash
lsb_release -a                       # Ubuntu 24.04
curl -4 -s https://api.ipify.org     # equals the address the provider shows
ss -lntp | grep -E ':80 |:443 '      # nothing else may be listening there (exit)
```

## Then

`references/provisioning.md`, "Delivering the installer": SSH from your session if you have it, otherwise the two lines through the person. Exit: `setup-exit.sh`, then the DNS records and `vpn-verify.sh`. Relay: rebuild once the exit is verified, `setup-relay.sh`, `vpn-verify.sh`, `relay_ip` into `params.json`.
