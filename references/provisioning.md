# Where machines come from and how the installer gets there

Technical notes for you. What to say to the person is in `lang/<xx>.md`; what the person does is in `human-steps.md`; this file is the mechanics.

## Providers

Provider is a parameter of each layer, not of the profile: any Ubuntu 24.04 host with a public IPv4 can be the exit, and any such host inside the users' country can be the relay. The files below say what is automated, how it is paid for and what to watch. Every file is dated; re-check anything older than a few months before promising it to the person.

| File | Layer | Automation | Pays with | Date |
|---|---|---|---|---|
| [`providers/digitalocean.md`](providers/digitalocean.md) | exit | **full** (`provision-do.py`) | international card, PayPal | written 2026-09-24, tested |
| [`providers/hetzner.md`](providers/hetzner.md) | exit | manual (console + SSH) | card, PayPal, SEPA; identity check | written 2026-09-24 |
| [`providers/vultr.md`](providers/vultr.md) | exit | manual | card, PayPal, Alipay, WeChat Pay, crypto | written 2026-09-24 |
| [`providers/yandex-cloud.md`](providers/yandex-cloud.md) | relay | manual | local cards | written 2026-09-24 |
| [`providers/alibaba-cloud.md`](providers/alibaba-cloud.md) | relay or exit | manual | international and local cards, Alipay, PayPal | written 2026-09-24 |
| [`providers/arvancloud.md`](providers/arvancloud.md) | relay or exit | manual | local cards, crypto via partners | written 2026-09-24 |
| [`providers/generic-ubuntu.md`](providers/generic-ubuntu.md) | exit or relay | manual | whatever the host takes | — |

**Requirements for either layer:** Ubuntu 24.04, 1 vCPU, 1 GB of memory, a real public IPv4, a sensible traffic quota. That is enough for a gigabit — the bottleneck is always traffic, never the CPU. The installers open what each layer needs: the exit `22/80/443` tcp (plus `443` and `51821` udp in the `single` profile), the relay `22` tcp and `443` + `51821` udp — the provider's own firewall, if any, must not block those. **The relay additionally wants** cheap or free inbound traffic (everything the users do passes through it twice) and, obviously, a different provider from the exit's.

**The relay layer.** Provider is a parameter: any Ubuntu 24.04 VPS in the users' home country. The only reason to choose the relay layout is that their network restricts direct foreign connections or only allows listed IP ranges.

> **Before picking a home-country provider, say this to the person:** a provider in your home country knows who you are and can see that you run a tunnel; choose accordingly.

**Relay-capable hosts** (written 2026-09-24, not re-verified live): flat-rate VPS plans are the better fit for a household. Documented in `providers/`: Yandex Cloud, Alibaba Cloud, ArvanCloud (each bills egress per gigabyte or per plan — count before promising a price); any other local flat-rate VPS through `providers/generic-ubuntu.md`. Aeza is excluded (see below). Requirements as above plus a traffic quota of 1 TB or unlimited.

## No card that works?

*Written 2026-09-24 from the providers' public pages as known at that date, not re-verified live that day. Not partners, no referral links, conditions change by country and by month — check the provider's own billing page before promising anything, and say to the person that you checked, not that you know.*

In the order worth trying:

1. **Someone abroad pays.** A friend or relative with a working card rents the exit in *their* account, at the host's listed monthly price. Then it is the standard flow with their token, and they revoke it at the end like anyone else. Never register an account in someone else's name; this is their account, used with their knowledge.
2. **Providers that take crypto or regional payment methods.** All exit-only; none tested by this skill yet.
   - **Vultr** — cards, PayPal, Alipay, WeChat Pay, cryptocurrency. Mainstream, many locations.
   - **Hostinger (VPS)** — cards, PayPal, cryptocurrency through a payment processor; locations in Europe, the US and Asia.
   - **PQ.Hosting** — cryptocurrency and cards of many regional banks; European locations; registered in Moldova.
   - **Njalla** — cryptocurrency, privacy-first, pricier; sells domains too.
   - **Timeweb Cloud, RuVDS** — companies registered inside a filtered country that also sell servers in the Netherlands, Germany, Kazakhstan and elsewhere, payable with domestic cards. Practical, and worth one honest sentence to the person: the company answers to that country's law, so the exit is abroad but its landlord is not.
   - **Removed from earlier versions of this list:** Aeza — designated by the US Treasury (OFAC) in July 2025. Do not recommend it.
3. **Foreign-card services** — virtual cards and accounts of the Wise / Payoneer kind. They work, and they are last on purpose: fees, identity checks, and they come and go. The person checks one themselves; we do not partner with any of them.

**Domains** are the same problem in miniature: Namecheap, Porkbun and Cloudflare take cards; Njalla takes crypto; a registrar inside the person's own country takes local cards and is perfectly fine for a neutral domain — the registrar does not have to be abroad, only the exit does.

## Delivering the installer to a server that already exists

In order of preference.

**1. Over SSH from your session**, if you have a tool for it (`mcp-ssh`, a shell with network access):

```bash
scp out/setup-relay.sh root@<IP>:/root/
ssh root@<IP> 'bash /root/setup-relay.sh'
```

The install takes 5–10 minutes. If the tool cuts commands off at a timeout (many stop at 60 seconds), run it in the background and follow the log:

```bash
ssh root@<IP> 'setsid nohup bash /root/setup-relay.sh > /dev/null 2>&1 & disown'   # the installer writes /var/log/vpn-kit-install.log itself
ssh root@<IP> 'tail -20 /var/log/vpn-kit-install.log'
```

When the login is not root (Yandex Cloud, some others): `scp … <user>@<IP>:~/` and `ssh <user>@<IP> 'sudo bash ~/setup-relay.sh'`.

**2. Through cloud-init**, if the machine does not exist yet: the whole `setup-exit.sh` goes into the user-data field at creation. **Exit only, never the relay** — metadata is readable by any local process on the machine.

**3. Hand the file to the person.** Send `setup-*.sh` with SendUserFile and walk them through `human-steps.md` §7 with the words from `lang/<xx>.md` §7 — how to open a terminal on each system, that the password does not show while typing, what to answer to the `yes/no` question. The lines themselves:

```bash
scp ~/Downloads/setup-relay.sh root@<IP>:/root/
ssh root@<IP> 'bash /root/setup-relay.sh'
```

Ask for the last twenty lines of output — they show whether it worked.

## DNS

Three A records pointing at the exit's IP: `@`, `www`, `push`.

If the domain is in DigitalOcean's DNS, they are set by the script:

```bash
python3 scripts/provision-do.py dns --domain <domain> --ip <IP> --names @ www push
```

If not, the person sets them at their registrar (`human-steps.md` §5). TTL 300 seconds: when the machine is replaced after a block, that saves hours of waiting.

Check that they have propagated — yourself, not by asking the person:

```bash
python3 scripts/provision-do.py ns-check   --domain <domain>              # where it is delegated
python3 scripts/provision-do.py dns-check  --domain <domain> --ip <IP>    # have the records propagated
```

`ns-check` exits 0 when the domain is at DigitalOcean (set the records yourself), 2 when it is at a registrar (the person sets them, §5), 3 when DNS cannot be queried from your session at all — then ask the person to open dnschecker.org.

Certificates are issued by the installer automatically, but it waits for DNS — up to six attempts a minute apart. If the A records were set later, just run the installer again; it is idempotent.

## Running again

Every installer can be run any number of times. What is already configured is left alone: an existing `wg-clients.conf` is not overwritten, issued certificates are not reissued, `admin-token` and `alerts.json` are kept. This is the normal way to finish an install that did not complete the first time. The one exception: **the cover page `/var/www/<domain>/index.html` is regenerated from the Russian template on every run** — if it was rewritten, copy the rewritten version back afterwards (keep it at `/root/vpn-kit/index.html`).

Delivered through cloud-init, the kit stays unpacked in `/opt/vpn-kit`, so a re-run does not need the file again: `bash /opt/vpn-kit/exit/install.sh 2>&1 | tee -a /var/log/vpn-kit-install.log`. Delivered by `scp`, run the same `setup-*.sh` again.
