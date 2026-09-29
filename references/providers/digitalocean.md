# DigitalOcean

*Written 2026-09-24 from the console and billing pages as known at that date, not re-verified live. Tested by this skill: yes — this is the automated path.*

| | |
|---|---|
| **Layer** | **exit**, in either profile. Not a relay: no datacenters inside carrier-restricted countries. |
| **Last verified** | 2026-09-24 (tested end to end). |
| **Automation** | **Full.** `scripts/provision-do.py` creates the machine, uploads the SSH key, sets the DNS records, lists and destroys by tag. Needs an API token (full access, 30-day expiry) in `DO_TOKEN`. |
| **Machine** | `s-1vcpu-1gb`: $6/month, 1 TB transfer, Ubuntu 24.04 (`ubuntu-24-04-x64`). Regions: `fra1` `ams3` `lon1` (Europe), `sgp1` (Asia), `blr1` (India), `nyc1` `nyc3` `sfo3` `tor1` (Americas), `syd1` (Australia). |
| **Signup** | Email (or Google sign-in) and a payment method; no phone, no ID. Some new accounts get a manual review that takes a few hours. |
| **Payment** | International Visa / Mastercard / American Express, PayPal. About $1 is held to verify the card and refunded. Cards issued in some sanctioned countries are refused — check the provider's current list. Virtual cards from Wise, Payoneer or Revolut generally work; anonymous prepaid cards usually do not. New accounts are sometimes asked to prepay a small balance before the first droplet. |
| **Known blocked ranges** | DigitalOcean's address space has been blocked in bulk in several countries repeatedly since 2022 — whole /16s at a time, on and off — and large parts of it are unreachable from carrier-restricted networks. A fresh droplet's IP can already be on a list. In the `relay` profile this hits the relay → exit hop: before handing over, check from the relay that `curl -x socks5h://127.0.0.1:1080 https://api.ipify.org` returns the exit's IP; if the region is dead, destroy and recreate in another region (fifteen minutes, nobody reconfigures a phone). In `single` it hits the users directly and the remedy is the same: a new machine plus DNS. |
| **Firewall** | None by default — every port of the droplet is open until the installer sets up nftables. A **Cloud Firewall** is optional; if one is attached it must allow `22/80/443` tcp and `443/51821` udp inbound. |
| **Quirks** | `ssh_keys` is mandatory at creation: without it the droplet boots in "change your password on first login" mode and refuses key logins — the script refuses to create such a machine. `user_data` is limited to 64 KB (the exit installer is about 49 KB). The `vpn-exit` tag is how `list` and `destroy` find the machine; `destroy` refuses without it. Metadata (`user_data`) is readable by any local process: fine for the exit, never for the relay installer. |

## Click paths (the person clicks; the words are in `lang/en.md` §1–§4)

**Account (§1)** — `cloud.digitalocean.com/registrations/new` → sign up with email and password, or with Google → confirm the email → **Billing** → add a card or PayPal.

**API token (§2)** — `cloud.digitalocean.com` → left menu, at the bottom: **API** → tab **Tokens** → **Generate New Token** → Name: anything (`vpn`) → Expiration: **30 days** → Scopes: **Full Access** → **Generate Token** → the line starting `dop_v1_` is shown **once**: copy it whole and paste it into the chat.
Revoke: the same page → **Tokens** → the three dots next to the token → **Delete**.

**Nameservers (§4)** — at the registrar, custom nameservers: `ns1.digitalocean.com`, `ns2.digitalocean.com`, `ns3.digitalocean.com`.

**Console fallback** (you have no network from where you run, or the API refuses): **Create → Droplets** → region → image **Ubuntu 24.04 (LTS) x64** → **Basic** → CPU options **Regular**, the **$6** plan → Authentication: **SSH Key** (the person's own key — in guidance-only mode they need SSH access themselves; with no key at all, **Password** works too, or later **Access → Reset root password** on the droplet page emails one) → **Advanced Options → Add Initialization scripts (free)** → paste the whole `out/setup-exit.sh` → Tags: `vpn-exit` → **Create Droplet**. DNS in the console: **Networking → Domains** → add the domain → three **A** records `@`, `www`, `push` → the droplet's IP, TTL 300.

## Commands

```bash
export DO_TOKEN=...
python3 scripts/provision-do.py check                          # token alive? card attached? how many machines?
python3 scripts/provision-do.py new-key --out ~/.ssh/vpn-kit   # create a key and upload it to the account
python3 scripts/provision-do.py keys                           # SSH key ids on the account
python3 scripts/provision-do.py create --name vpn-exit --tag vpn-exit --ssh-key <id> \
    --user-data out/setup-exit.sh --region fra1
python3 scripts/provision-do.py dns --domain <domain> --ip <IP> --names @ www push
python3 scripts/provision-do.py ns-check --domain <domain>     # 0 = at DigitalOcean, 2 = elsewhere, 3 = no DNS from here
python3 scripts/provision-do.py dns-check --domain <domain> --ip <IP>
python3 scripts/provision-do.py list                           # all machines (check the bill)
python3 scripts/provision-do.py list --tag vpn-exit            # ours only
python3 scripts/provision-do.py wait-ssh --ip <IP>             # wait for boot
python3 scripts/provision-do.py destroy --id <id> --tag vpn-exit
```
