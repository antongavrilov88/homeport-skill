---
name: homeport
description: 'Use when someone wants a personal VPN on a server they rent themselves — "set up my own VPN", "VPN for my parents", "my VPN keeps getting blocked", "deploy an Xray / REALITY / WireGuard server", homeport (formerly Burrow). Built for a person with no technical background: it asks in plain words, does the work itself and walks the few manual steps button by button. Delivers VLESS + XHTTP + REALITY plus WireGuard, a web panel that issues devices by QR, a watchdog that restarts what fails (automatic failover on the two-server layout), and push alerts to the phone.'
compatibility: 'Needs a shell with network access to the hosting API and SSH to the server, plus Python 3 (standard library only). Tested with Claude Code; other agents that load the Agent Skills format are untested. In a sandbox with no outside network (claude.ai with code execution) it only generates keys and installers and the person runs the commands.'
---

# Homeport — plugin entry point

This file exists only so that the plugin loader finds the skill. **The complete skill is the `SKILL.md` at the plugin root, one level above `skills/`.** Read it in full right now and follow it; every path it names (`scripts/…`, `references/…`) is relative to that root.

- Root of this plugin: `${CLAUDE_PLUGIN_ROOT}` — so the skill is `${CLAUDE_PLUGIN_ROOT}/SKILL.md` and the scripts are under `${CLAUDE_PLUGIN_ROOT}/scripts/`.
- If the placeholder above was not replaced with a real path (you are not running as a plugin), the root is the directory that contains `skills/`: `../../SKILL.md` relative to this file.

Do not answer the person from this stub. Load the root `SKILL.md` first.
