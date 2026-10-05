#!/usr/bin/env bash
# Four checks on the public surface. Fails when a country-specific term is back,
# when a line frames the product as circumvention (second check), when the old
# product name "Burrow" is used (third check), or on the word "bypass" (fourth check).
# The lists and the approved vocabulary live in CONTRIBUTING.md ("Wording rules").
# Case-insensitive, Latin and Cyrillic; the Cyrillic terms are stems, so every case
# ending matches. Language labels ("the panel is in Russian", lang/ru.md) are
# allowed on purpose: only geographic / positioning uses are banned.
# Excluded from the scan: this script and CONTRIBUTING.md (they quote the lists),
# .git (the directory, or the pointer file in a worktree), images.
set -u
export LC_ALL=C.UTF-8
PATTERN='\bRKN\b|Roskomnadzor|Роскомнадзор|Sberbank|Сбербанк|\bСбер(а|у|ом|е)?\b|обход[а-яё]* блокиров[а-яё]*|бел[а-яё]+ спис|whitelist|Russian (sites?|exit|banks?|IPs?|address(es)?|cards?|hosting|hosters?|providers?|laws?|carriers?|networks?|users?|households?)|VPN for Russians|works in Russia|\bin Russia\b|\bРосси[яиюе]|российск|\bРФ\b'
HITS=$(grep -rniE "$PATTERN" \
  --exclude-dir=.git --exclude='.git' --exclude='*.png' --exclude='*.jpg' --exclude='*.pyc' \
  --exclude='wording-guard.sh' --exclude='CONTRIBUTING.md' \
  "${1:-.}" || true)
if [ -n "$HITS" ]; then
  echo "banned wording found (see CONTRIBUTING.md, Wording rules):"
  echo "$HITS"
  exit 1
fi

# Circumvention framing. Narrow patterns on purpose: "apps that refuse VPN connections
# keep working" passes; the six phrasings below fail. The word "bypass" fails in any
# form on its own, in the fourth check.
CIRCUMVENTION="evad(e|es|ing) (block|censor|detect|filter)|circumvent|get around (the )?block|when (it'?s |you'?re )?blocked|unblock|keeps? working when"
FRAMING_HITS=$(grep -rniE "$CIRCUMVENTION" \
  --exclude-dir=.git --exclude='.git' --exclude='*.png' --exclude='*.jpg' --exclude='*.pyc' \
  --exclude='wording-guard.sh' --exclude='CONTRIBUTING.md' \
  "${1:-.}" || true)
if [ -n "$FRAMING_HITS" ]; then
  echo "circumvention framing found (see CONTRIBUTING.md, Wording rules):"
  echo "$FRAMING_HITS"
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
\.claude-plugin/(plugin|marketplace)\.json:[0-9]+: *"burrow"$'
OLD_HITS=$(grep -rniw 'burrow' \
  --exclude-dir=.git --exclude='.git' --exclude='*.png' --exclude='*.jpg' --exclude='*.pyc' \
  --exclude='wording-guard.sh' --exclude='CONTRIBUTING.md' --exclude='CHANGELOG.md' \
  "${1:-.}" | grep -vE -e "$OLD_NAME_ALLOWED" || true)
if [ -n "$OLD_HITS" ]; then
  echo "old product name found; say Homeport (see CONTRIBUTING.md, Wording rules):"
  echo "$OLD_HITS"
  exit 1
fi

# The word "bypass" (bypasses, bypassed, bypassing), whole word, case-insensitive. The
# panel has a word for each thing the docs used it for: a device's route goes "through
# the tunnel" or "direct", and the domains that skip the tunnel are the "exceptions".
# One name stays: the relay's nftables set is called `bypass` on every installed relay.
# BYPASS_ALLOWED cuts that name out of a hit line where it is allowed, then the rest of
# the line is checked again, so the word anywhere else on the same line still fails.
# Allowed: the set's two lines in the relay installer, and the set named in backticks
# ("the `bypass` set", "`bypass` sets").
BYPASS='\bbypass(es|ed|ing)?\b'
BYPASS_ALLOWED='s#^((.*/)?scripts/payload/relay/install\.sh:[0-9]+:)[[:space:]]*(set bypass [{]|ip daddr @bypass return)$#\1#
s#`bypass` sets?([^[:alnum:]_]|$)#\1#g
s#^[^:]*:[0-9]+:##'
BYPASS_HITS=$(grep -rniE "$BYPASS" \
  --exclude-dir=.git --exclude='.git' --exclude='*.png' --exclude='*.jpg' --exclude='*.pyc' \
  --exclude='wording-guard.sh' --exclude='CONTRIBUTING.md' \
  "${1:-.}" | while IFS= read -r LINE; do
    if printf '%s\n' "$LINE" | sed -E "$BYPASS_ALLOWED" | grep -qiE "$BYPASS"; then
      printf '%s\n' "$LINE"
    fi
  done || true)
if [ -n "$BYPASS_HITS" ]; then
  echo '"bypass" found; say "through the tunnel" or "exceptions" (see CONTRIBUTING.md, Wording rules):'
  echo "$BYPASS_HITS"
  exit 1
fi
echo "wording guard: 0 hits"
