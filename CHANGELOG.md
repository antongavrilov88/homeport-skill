# Changelog

## Unreleased

- docs(repo): the maintainer's personal Telegram channel is no longer a support or security contact. `SECURITY.md` sends vulnerabilities to GitHub's private vulnerability reporting (Security → Report a vulnerability) and non-sensitive bugs to issues; it had pointed private reports at a channel, which can't take private messages. The issue chooser's contact links go to existing issues and to the private report page instead of Telegram, and the README's "Stuck?" line points to issues. The About section keeps LinkedIn only. The waitlist bot link is unchanged.
- docs(skill): the README's "Privacy, stated plainly" now lists what leaves the server: device DNS to Cloudflare's 1.1.1.1; every alert's title and text to a random topic on public ntfy.sh with no login, always, alongside your own ntfy; iPhone wake-ups through ntfy.sh with a message ID only; the watchdog's probe, certificate renewal and install-time downloads, which carry no user data. "Nothing phones home to anyone but your own ntfy" and "public ntfy.sh as fallback" are gone — both were wrong since 0.1.0. `references/human-steps.md` §9 and `references/troubleshooting.md` describe the public topic as always on, not a backup. Nothing the server sends has changed.

Website changes live in the site repo's changelog: https://github.com/antongavrilov88/homeport/blob/main/CHANGELOG.md

## 0.5.1 — 2026-09-27

- docs(skill): the "Upgrading from Burrow" note names the error an old install shows after an update (`Plugin burrow not found in marketplace burrow`), so people recognise it. Checked on a real Burrow 0.4.0 install: `marketplace update burrow` leads to exactly that error, and the three upgrade commands install `homeport@homeport` 0.5.0.

## 0.5.0 — 2026-09-27

- feat(skill): renamed to Homeport. The skill `name` is `homeport` and the plugin wrapper moved to `skills/homeport/SKILL.md`; the plugin and the marketplace are both `homeport`, so the install is `/plugin marketplace add antongavrilov88/homeport-skill` → `/plugin install homeport@homeport` and the command is `/homeport` (`/homeport:homeport` as a plugin). Copy installs go to `~/.claude/skills/homeport`; the release asset is `homeport-skill.zip` containing `homeport/`. Existing installs are not migrated automatically: they follow the README's "Upgrading from Burrow" note (remove the old marketplace or folder, install the new one). The description says "formerly Burrow" and `plugin.json` keeps `burrow` as a keyword for one release so existing users still find it. Homepage and repository links point at `antongavrilov88.github.io/homeport/` and `antongavrilov88/homeport-skill`. The wording guard now also fails on the old name outside the changelog and the rename notes. Server paths (`/opt/vpn-kit`, `/root/vpn-kit`) and the installers are unchanged.

## 0.4.0 — 2026-09-26

- fix(installer): on the default one-server layout (`single`) the web panel no longer shows two-server-only route UI — the "Маршрут" column with a "напрямую" badge on every client, and the route wording in the traffic-chart and clients hints. They are hidden with the existing `.only-multipath` mechanism; the hints get a single-mode variant without the route part. The two-server (`relay`) panel is unchanged. This changes a file the installer puts on the server (`scripts/payload/common/dashboard.html`); no other script changes.
- docs(installer): the relay's split-tunnel list (`direct-domains.txt`) ships seeded with payment and card networks that commonly refuse or step up verification from a data-centre address, and every source now says so: the file's own header no longer claims the list is empty, and `SKILL.md` no longer calls it a one-country list. The 0.3.0 entry saying the default list "ships empty" was wrong — the seeded domains were never removed. No domain was added or removed; comment lines only.

## 0.3.2 — 2026-09-26

- fix(skill): the skill, plugin and marketplace descriptions no longer promise automatic failover unconditionally. On the default `single` layout the watchdog restarts Xray and alerts, with nothing to fail over to; failover (and, in the `SKILL.md` body, re-routing) is now stated as two-server (`relay`) only, matching the README. No script or installer change.
- docs(skill): README makes only the claims the code backs, matching the landing. "Five minutes" is replaced by the landing's timing (about 10 minutes of install, 15 minutes to a few hours for a new domain, a possible few-hour account review); "survives 2026-grade blocking" and "no company to block" are gone from the README, and the blocking claim from the `SKILL.md` body; the paid tier no longer promises "ready in about an hour" and states the landing's terms instead (opens in November, $29 once, refund condition). The watchdog probes every 30 s, not every minute; failover, the monthly drill, `vpn-split` and split routing are stated as two-server (`relay`) only; the panel's buttons are named as Russian for now. No script or installer change.

## 0.3.1 — 2026-09-25

- docs(skill): README quick start leads with the plugin install, one command per block, and states the update correctly: `claude plugin marketplace update burrow` only refreshes the catalog, `claude plugin update burrow@burrow` plus a restart upgrades. Says that `/plugin` is typed in Claude Code, not a shell. The `git clone` path stays as the alternative.

## 0.3.0 — 2026-09-25

- docs(skill): global positioning — every country-specific term removed from the public surface (skill, references, README, landing strings, script comments and printed strings); the `relay` profile is described only as "your network restricts direct foreign connections or only allows listed IP ranges", with a home-country relay at any Ubuntu 24.04 provider. `references/providers/` gets Alibaba Cloud and ArvanCloud, and every provider file the same rows: signup requirements, machine/region/image, firewall, quirks, last-verified date; a neutral warning about home-country providers at the top of the relay section. Default split-tunnel list (`direct-domains.txt`) ships empty — fill it per household from the panel (`home_geoip` still routes home-country addresses directly). `CONTRIBUTING.md` "Wording rules" + `.github/wording-guard.sh` in CI. Printed strings in `make-handout.py` and the panel hint changed accordingly; no script logic changed.

- `fix(installer)` — **iPhones get push notifications again.** `/etc/ntfy/server.yml` now
  carries `upstream-base-url: "https://ntfy.sh"`: iOS keeps no background connection to a
  self-hosted ntfy, so only ntfy.sh can wake the phone. Just the bare fact that a message
  exists goes upstream — no text, no topic; the phone fetches the text from your own
  server. A server built before this release needs the line added by hand plus
  `systemctl restart ntfy`, and the subscription in the app deleted and re-created —
  otherwise the phone never re-registers (`references/troubleshooting.md`).
- `fix(installer)` — **a drill no longer takes the operator down with it.**
  `vpn-drill.sh` postpones itself while people are using the channel (more than 5 MB in
  the last five minutes, from `stats.db`, or a WireGuard handshake in the last 180 s when
  that database is missing): it notifies, logs `skip: clients active` and exits 3 without
  touching the route. A plain run now detaches into the transient unit
  `vpn-drill-manual` and returns at once, so an SSH session dying with the channel can no
  longer kill the run and leave the block standing. New flags `--force` (run anyway) and
  `--fg` (run in this process); unknown flags exit 2; running under systemd implies
  `--fg`, so `vpn-drill.service` and `vpn-drill-check.service` are unchanged, and
  `--check` still exits before any of this and breaks nothing.
- `docs(skill)` — the first device is now checked **on mobile data, Wi-Fi off**, before
  any QR codes go out; if Wi-Fi works and mobile data does not, `alt_port` 443 first and
  only then a different provider in the users' country — the relay's IP is written into
  every config the panel issues, so moving the relay afterwards means re-issuing every
  device (`SKILL.md` step 7, `lang/en.md`, `lang/ru.md`, `references/human-steps.md`).
- `docs(skill)` — `references/architecture.md` gains "A standby exit instead of the direct
  fallback": why the direct fallback is weakest on carrier-restricted networks, the shape
  of an exit B, the files it would touch, and why it is not built until paying users
  confirm the direct fallback is useless for them.

## 0.2.0 — 2026-09-24

- Skill rewritten in English. One routing question ("where are the people, and does their network restrict direct foreign connections?") selects a profile: `single` (one server abroad, default) or `relay` (relay in the users' country + exit). Both end at the same installers; `SKILL.md` has the parameter table.
- Human-facing wording separated from instructions: `references/lang/en.md` and `lang/ru.md` (the Russian keeps the tested wording), plus handout templates `lang/handout-en.md` / `handout-ru.md`. The handout comes in the user's language; the Russian one is still generated by `scripts/make-handout.py`.
- Provider facts moved into `references/providers/` (DigitalOcean, Hetzner, Vultr, Yandex Cloud, generic Ubuntu), dated. `references/provisioning.md` is now the index plus the "No card that works?" list. Aeza removed from suggestions (OFAC designation, July 2025).
- The skill states up front where it runs: full automation from Claude Code, guidance-only from claude.ai's sandbox (no network to the user's server), and it says so to the person at the start.
- Plugin marketplace: `/plugin marketplace add antongavrilov88/burrow-skill` → `/plugin install burrow@burrow` (`.claude-plugin/`, `skills/burrow/SKILL.md` wrapper; CI keeps it in sync with the root `SKILL.md`).
- README: requirements and quick start rewritten with the honest capability split (Claude Code / claude.ai / Cowork untested / hosted agent).
- `scripts/` and every installer payload are byte-identical to 0.1.0. The web panel and push notifications therefore stay in Russian; the skill discloses this and the handout carries a glossary.

- Landing v1: light/dark themes, language dropdown (EN/RU), one-click "where are you?" price calculator, Telegram hand-over form.
- Repo flow: `main` / `dev` / feature branches, CI, release workflow that packs `burrow-skill.zip`, Pages deploy from `docs/`.

## 0.1.0 — 2026-09-23

- First public release of the skill (formerly `vpn-kit`), MIT.
- README in English; SECURITY.md; `.gitignore` for installation secrets.
