# Hetzner Cloud

*Written 2026-09-24 from public pricing and signup pages as known at that date, not re-verified live. Tested by this skill: not yet — issue #7 tracks API parity.*

| | |
|---|---|
| **Layer** | **exit**. Not a relay: locations are Germany (Falkenstein, Nuremberg), Finland (Helsinki), the USA (Ashburn, Hillsboro) and Singapore. |
| **Automation** | Manual. The person creates the server in the console; you install over SSH. |
| **Last verified** | 2026-09-24 (pages read, not tested). |
| **Machine** | The smallest shared plan (`CX22` / `CX23` class: 2 vCPU, 4 GB) from about €4–5/month including 20 TB of traffic at European locations; US and Singapore plans cost more and include less traffic. A primary IPv4 carries a small monthly surcharge. Ubuntu 24.04 is a stock image. |
| **Signup** | Email, a postal address and a payment method; often a **photo of an ID document** for new accounts (manual check, hours to a day). No phone number required. |
| **Payment** | Cards, PayPal, SEPA direct debit. New accounts are frequently put through a manual identity check (a photo of an ID document) that takes hours to a day — tell the person up front. Cards issued in some sanctioned countries are refused, and so are signups with addresses in some countries. |
| **Known blocked ranges** | Hetzner's ranges have been blocked in bulk in several countries (large sweeps in 2024–2025) and are partly unreachable from carrier-restricted networks. Same remedy as anywhere: replace the machine, move the DNS records, fifteen minutes. |
| **Firewall** | Off by default; the installer configures nftables on the machine. If a Hetzner Firewall is attached, allow `22/80/443` tcp and `443/51821` udp inbound. |
| **Quirks** | The console's **Cloud config** field is cloud-init user data, but it has a size limit (32 KiB at last check) that the ~49 KB exit installer exceeds — so install over SSH, not through the field. Hetzner's firewall is off by default; the installer configures nftables on the machine itself. |

## Click paths

**Account** — `accounts.hetzner.com` → sign up → confirm the email → complete the identity check if asked → add a payment method.

**Server** — `console.hetzner.cloud` → **New project** → **Add Server** → Location (nearest to the users or to the relay; for services from home, in the home country) → Image **Ubuntu 24.04** → Type **Shared vCPU**, the cheapest → Networking: keep **Public IPv4** on → SSH keys: **Add SSH key** and paste the contents of `~/.ssh/vpn-kit.pub` (or the person's own key) → Name `vpn-exit` → **Create & Buy now**. The IP is shown on the server page.

**Then** — DNS at the registrar or in **Hetzner DNS** (three A records `@`, `www`, `push`, TTL 300), `dns-check`, and `setup-exit.sh` over SSH as root (`references/provisioning.md`, "Delivering the installer").
