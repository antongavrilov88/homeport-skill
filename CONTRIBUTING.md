# Contributing

## Branches

| Branch | What it is | Who pushes |
|---|---|---|
| `main` | Released code only. Every commit here is a release (or a hotfix that becomes one). Deploys the landing. | merges from `dev` via PR |
| `dev` | Integration branch. Always installable, may be ahead of the last release. | merges from feature branches via PR |
| `feat/<name>`, `fix/<name>`, `docs/<name>` | One change each, branched from `dev`. | you |
| `hotfix/<name>` | Urgent fix branched from `main`; merged to `main` **and** back into `dev`. | you |

## Release flow

1. Work on `feat/...`, open a PR into `dev`. CI runs syntax checks, a secrets scan and the wording guard.
2. When `dev` is ready for a release, tag a candidate on it: `git tag v0.2.0-rc.1 && git push --tags`. The release workflow publishes a **pre-release** with `homeport-skill.zip` — test-install that zip in Claude.
3. Fix on `dev`, tag `-rc.2` if needed.
4. Open a PR `dev → main`, merge (merge commit, not squash — keep history). Tag `v0.2.0` on `main`, push the tag. The workflow publishes the release; Pages redeploys the landing if `docs/` changed.
5. Add the version to `CHANGELOG.md` before tagging, and bump `version` in `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` (CI checks they match).

`rc` is a tag, not a branch: with one maintainer a long-lived `release/*` branch adds ceremony without safety. If a second maintainer joins, add `release/x.y` branches then.

## Versioning

Semantic. The skill's user-facing behaviour is the API: a change to what the installers put on a server, or to the manual steps a person has to do, is at least a minor bump.

## Commit messages

`type(scope): summary` — types `feat`, `fix`, `docs`, `chore`, `refactor`, `ci`. Scope is `skill`, `installer`, `landing`, `repo`.

## Language and wording

`SKILL.md` and `references/*.md` are English instructions. Everything said to the person lives in `references/lang/<xx>.md`; the Russian file and the Russian handout are wording tested with real families — change them only after testing the new wording on a real person, and say so in the PR. New languages: translate `lang/en.md` and `lang/handout-en.md`, keep the section numbers. `skills/homeport/SKILL.md` is generated from the root `SKILL.md` frontmatter; if you change the description, regenerate it (CI fails otherwise).

## Wording rules

Homeport is a world-wide product. The public surface — `SKILL.md`, `references/`, `scripts/` comments and printed strings, `README.md`, `CHANGELOG.md`, this file, `SECURITY.md`, `.github/`, `docs/` — names no country as the reason the product exists. CI runs `.github/wording-guard.sh` on every PR and fails on any of the terms below, case-insensitive, in Latin and Cyrillic.

**Banned:** `RKN`, `Roskomnadzor` / `Роскомнадзор`, `Sberbank` / `Сбер` / `Сбербанк`, `обход блокировок`, `белые списки` / `белый список`, `whitelist` / `whitelists` (when it means a carrier's allow-list in one country), `Russian sites`, `works in Russia`, `in Russia`, `VPN for Russians`, `Russian` + exit / bank / IP / address / card / hosting / provider / law / carrier / network / user / household, `Россия` / `в России` / `российский` / `РФ`.

**Approved instead:**

| Say | Not |
|---|---|
| home-country relay | relay in Russia, Russian relay |
| carrier-restricted networks | networks with whitelists, mobile internet in Russia |
| allowlisted IP ranges | whitelist, белые списки |
| apps that refuse VPN connections keep working | Sberbank works, banks work without toggling |
| local sites stay reachable, foreign sites are unavailable | internet works without обход блокировок |
| your network restricts direct foreign connections or only allows listed IP ranges | the one and only reason to choose the `relay` profile |

The Cyrillic terms are matched as stems: every case form fails, not only the dictionary form (`обхода блокировок`, `белых списков`, `Сбером`, `Россией`), while unrelated words such as `сбережения` pass.

**Circumvention framing** is banned as well, case-insensitive, by the guard's second check: `bypass(es|ing)? (the )?(block|censor|filter)`, `evad(e|es|ing) (block|censor|detect|filter)`, `circumvent`, `get around (the )?block`, `when (it'?s |you'?re )?blocked`, `unblock`, `keeps? working when`. The patterns are narrow on purpose, so "bypassing the relay" and "apps that refuse VPN connections keep working" pass. Say instead: "carrier-restricted networks", "local sites stay reachable, foreign sites are unavailable", "networks that detect or slow down plain WireGuard", "the tunnel is down".

What stays allowed: the *language* sense — "the panel is in Russian", `lang/ru.md`, `handout-ru.md` — because the server-side UI has a language and it has to be named. Provider files describe signup facts neutrally ("cards issued in some sanctioned countries are refused"), never by naming the country the user is in. Script logic and server paths (`/opt/vpn-kit`) are out of scope of the guard and of this section.

**Product name.** The product is **Homeport**, spelled exactly that way: one word, only the H capitalised. It used to be called Burrow. The same guard fails on the whole word `burrow`, case-insensitive, anywhere except `CHANGELOG.md` (history), this file and the guard itself, and lines that tell the rename story: `formerly Burrow` in the skill description, the README's "Upgrading from Burrow" note with its `marketplace remove burrow` and `~/.claude/skills/burrow` commands, and the `"burrow"` keyword in `.claude-plugin/`. To allow a new line, add a narrow pattern to `OLD_NAME_ALLOWED` in `.github/wording-guard.sh` and say why in the PR. The server-side working name `vpn-kit` is not affected.

## Rules the skill itself follows (keep them when you change it)

The list under "Hard rules" in `README.md`. A PR that weakens one of them needs a written reason.
