#!/usr/bin/env bash
# Fails when a country-specific term is back in the public surface,
# or when the old product name "Burrow" is (second check below).
# The list and the approved vocabulary live in CONTRIBUTING.md ("Wording rules").
# Case-insensitive, Latin and Cyrillic. Language labels ("the panel is in Russian",
# lang/ru.md) are allowed on purpose: only geographic / positioning uses are banned.
# Excluded from the scan: this script and CONTRIBUTING.md (they quote the list),
# .git, images.
set -u
export LC_ALL=C.UTF-8
PATTERN='\bRKN\b|Roskomnadzor|Роскомнадзор|Sberbank|Сбербанк|\bСбер\b|обход блокировок|белы[йе] спис|whitelist|Russian (sites?|exit|banks?|IPs?|address(es)?|cards?|hosting|hosters?|providers?|laws?|carriers?|networks?|users?|households?)|VPN for Russians|works in Russia|\bin Russia\b|\bРосси[яию]|российск|\bРФ\b'
HITS=$(grep -rniE "$PATTERN" \
  --exclude-dir=.git --exclude='*.png' --exclude='*.jpg' --exclude='*.pyc' \
  --exclude='wording-guard.sh' --exclude='CONTRIBUTING.md' \
  "${1:-.}" || true)
if [ -n "$HITS" ]; then
  echo "banned wording found (see CONTRIBUTING.md, Wording rules):"
  echo "$HITS"
  exit 1
fi

# Old name. The product was renamed Burrow -> Homeport; the word may stay only
# where it tells the rename story. Whole word, case-insensitive. Also excluded:
# CHANGELOG.md (history). Each allowed line must contain one of the extended
# regexes below; everything else fails.
OLD_NAME_ALLOWED='formerly Burrow
Upgrading from Burrow
marketplace remove burrow
~/\.claude/skills/burrow
"burrow": "homeport"
\.claude-plugin/(plugin|marketplace)\.json:[0-9]+: *"burrow"$'
OLD_HITS=$(grep -rniw 'burrow' \
  --exclude-dir=.git --exclude='*.png' --exclude='*.jpg' --exclude='*.pyc' \
  --exclude='wording-guard.sh' --exclude='CONTRIBUTING.md' --exclude='CHANGELOG.md' \
  "${1:-.}" | grep -vE -e "$OLD_NAME_ALLOWED" || true)
if [ -n "$OLD_HITS" ]; then
  echo "old product name found; say Homeport (see CONTRIBUTING.md, Wording rules):"
  echo "$OLD_HITS"
  exit 1
fi
echo "wording guard: 0 hits"
