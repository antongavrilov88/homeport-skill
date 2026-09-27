# Changelog

## Unreleased

- fix(landing): the comparison's free column is no longer half empty. The paid column had been carrying the chat mockup and five fine-print paragraphs — content that compares nothing — making it 1186px against the free column's 582px and leaving 739px of void inside the free card. Those now sit in their own row beneath the comparison; both columns are 691px.
- feat(landing): hero rebuilt. The two offers were living inside the hero's left column at 352px wide while a 348px panel floated vertically centred against a 935px column, anchored to nothing. The headline row is now a top-aligned pair and the offers are a full-width row of 530px cards below it.
- fix(landing): columns actually line up. The hero cards' label, amount, heading, body and button now share a baseline grid, and all four comparison rows align across both columns with the columns themselves equal height — previously the free column was 542px against the paid column's 1333px. The reservations are released below 760px, where the cards stack and alignment is meaningless.
- fix(landing): five-agent UI/UX review (conversion, copy, visual hierarchy, trust, mobile). Claims corrected to match the code — see the truth commit. The paid tier no longer reads as "the same skill, but you pay": it sells risk transfer, not a delivery format. Free path states its prerequisite (Claude Code) and offers the install command inline; the waitlist gives a reason before the button, not after. On phone the paid path leads, because a phone cannot run the install command, and the two aria-hidden mockups are hidden. Tap targets, hover gating for iOS, disclosure affordance, `aria-pressed` on the theme toggle, and ~15 lines of dead CSS.
- fix(landing): the free path now carries the visual emphasis instead of the paid one — accent border and fill, and a price line on both cards so "Free / forever" reads as a value next to "$29 / one time". The paid card is quieter, which also matches it not being live yet.
- feat(landing): refund terms stated under the guarantee — a failed verification is a full automatic refund, anything else inside 14 days on request. The guarantee wording itself is unchanged.
- perf(landing): first paint 2.8 s → 0.9 s (Lighthouse mobile, simulated throttling): the Google Fonts stylesheet no longer blocks render, an inline SVG favicon removes the /favicon.ico 404, `fonts.gstatic.com` is preconnected and the portrait is lazy with intrinsic size. 100/100/100/100 against a budget now recorded in `docs/UX-REVIEW.md`.
- feat(landing): a collapsed "What actually gets installed" disclosure under How it works — cover, devices, panel, watchdog, split routing, layouts — for readers who want the stack before the README.
- feat(landing): the offer is now legible from the hero. Two equally weighted paths side by side — free skill (developers are never charged) and the $29 agent, with "Opens in November" as a badge rather than a button subtitle; both the word "free" and the price are above the fold at 1280 and 390. Section 4 is a Yourself / With the agent comparison (what you do, what Burrow does, time, price, guarantee) with the chat mockup and price as its right column; nav reads "Free skill" and "Set it up for me"; a bridge line between the free and paid paths for people who started alone and got stuck.
- docs(landing): UX review in `docs/UX-REVIEW.md` — persona walkthroughs, IA, CTA audit, trust, copy, mobile, accessibility and performance. Fixes applied from it: WCAG AA contrast in both themes (axe-core 23 dark + 3 light violations → 0/0), three evidence links for the verified / privacy / provider claims, a footer link that promised releases but pointed at the waitlist bot, the hero lede's jargon stack, and 25 CSS rules orphaned by the restructure.
- feat(landing): English-only, global positioning. RU dictionary, `#ru` deep link and browser auto-detect removed; the dropdown architecture stays and hides itself while there is one language. Copy sweep: no region-specific wording anywhere (meta, OG, hero, why, agent tier, card section, bio); benefits lead with split tunneling, then privacy, then speed; "no foreign card?" became "card declined?"; bio is "developer, builds this in public".

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
