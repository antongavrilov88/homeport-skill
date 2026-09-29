#!/bin/bash
# Drill: a staged outage of the tunnel. Block the relay → exit path on 443, watch how the
# watchdog handles it, lift the block. A safety net lifts it in any case.
#
# Why a plain run goes to the background: the drill breaks exactly the path the operator is
# most often connected to the server through. Started from such an ssh session, the script
# would die with it mid-run — with the block still up, lifted only by the safety timer after
# SAFETY_MIN minutes. So a plain run re-launches itself as a separate systemd unit and returns
# at once; --fg runs in the current process (that is how systemd calls it).
#
#   vpn-drill.sh          — a run reported through notifications, in a background unit
#   vpn-drill.sh --check  — readiness check only, no outage
#   vpn-drill.sh --force  — do not postpone, even if people are using the tunnel right now
#   vpn-drill.sh --fg     — a run in the current process, no background unit
set -u
CHECK=""; FORCE=""; FG=""
for arg in "$@"; do
  case "$arg" in
    --check) CHECK=1 ;;
    --force) FORCE=1 ;;
    --fg)    FG=1 ;;
    *) echo "unknown option: $arg" >&2
       echo "usage: vpn-drill.sh [--check] [--force] [--fg]" >&2
       exit 2 ;;
  esac
done
# under systemd we already are a separate process — no need to detach twice
[ -n "${INVOCATION_ID:-}" ] && FG=1
. /etc/vpn-monitor/config.sh 2>/dev/null || true
GW="${VPN_GW:-10.67.0.1}"
if [ "${VPN_MODE:-relay}" = "single" ]; then
  echo "The drill only makes sense on the two-server layout: on one server there is nowhere to fail over to." >&2
  exit 1
fi
EXIT_IP=$(python3 -c "import json;print(json.load(open('/usr/local/etc/xray/config.json'))['outbounds'][0]['settings']['vnext'][0]['address'])" 2>/dev/null)
[ -n "$EXIT_IP" ] || { echo "could not read the exit server address from the Xray config" >&2; exit 1; }
STATE=/var/lib/vpn-monitor/health.json
LOG=/var/lib/vpn-monitor/drill.log
SAFETY_MIN=10
STATS_DB=/var/lib/vpn-monitor/stats.db
QUIET_SEC=300
QUIET_MB=5

notify() {
  python3 - "$1" "$2" "${3:-default}" <<'PY'
import importlib.util, sys
s = importlib.util.spec_from_file_location("w", "/usr/local/sbin/vpn-watchdog.py")
m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
m.notify(sys.argv[1], sys.argv[2], sys.argv[3])
PY
}
read_set() {
  # nft wraps a long set over several lines, so parse it whole instead of grep
  python3 - <<'PYEOF'
import re, subprocess
try:
    out = subprocess.run(["nft", "list", "set", "ip", "xray_tproxy", "proxied_src"],
                         capture_output=True, text=True, timeout=20).stdout
    m = re.search(r"elements = \{([^}]*)\}", out, re.S)
    print(", ".join(sorted(re.findall(r"[\d]+\.[\d]+\.[\d]+\.[\d]+(?:/\d+)?", m.group(1)))) if m else "")
except Exception:
    print("")
PYEOF
}
tunnel_ok() { curl -s -m 8 -x socks5h://127.0.0.1:1080 -o /dev/null -w "%{http_code}" https://www.gstatic.com/generate_204 | grep -qE "20[04]"; }
fallback_ok() { curl -s -m 8 --interface "$GW" -o /dev/null -w "%{http_code}" https://www.gstatic.com/generate_204 | grep -qE "20[04]"; }

# Is anyone using the tunnel right now: the sum of traffic deltas over the last
# QUIET_SEC seconds. No database — look for recent WireGuard handshakes.
anyone_active() {
  if [ -f "$STATS_DB" ]; then
    python3 - "$STATS_DB" "$QUIET_SEC" "$QUIET_MB" <<'PY'
import sqlite3, sys, time
db, quiet_sec, quiet_mb = sys.argv[1], int(sys.argv[2]), float(sys.argv[3])
try:
    conn = sqlite3.connect("file:%s?mode=ro" % db, uri=True)
    row = conn.execute("SELECT COALESCE(SUM(rx+tx),0) FROM samples WHERE ts > ?",
                       (int(time.time()) - quiet_sec,)).fetchone()
except Exception:
    sys.exit(2)
sys.exit(0 if (row[0] or 0) > quiet_mb * 1024 * 1024 else 1)
PY
    rc=$?
    [ "$rc" -le 1 ] && return "$rc"
  fi
  wg show wg-clients latest-handshakes 2>/dev/null \
    | awk -v now="$(date +%s)" '$2 ~ /^[0-9]+$/ && $2 > 0 && now - $2 < 180 { active = 1 } END { exit active ? 0 : 1 }'
}

echo "=== $(date -Is) drill start" >> $LOG

# --- readiness check: no outage without it
tunnel_ok || { notify "VPN: drill cancelled" "The tunnel is already down — sort that out first." high; echo "abort: tunnel down" >> $LOG; exit 1; }
fallback_ok || { notify "VPN: drill cancelled" "The fallback route is not responding — there is nowhere to fail over to. That alone needs a look." urgent; echo "abort: fallback down" >> $LOG; exit 1; }
systemctl is-active --quiet vpn-watchdog || { notify "VPN: drill cancelled" "The watchdog is not running, nothing would react." high; echo "abort: watchdog down" >> $LOG; exit 1; }
notify "VPN: ready for the drill" "The tunnel works, the fallback route works, the watchdog is running." >/dev/null

if [ -n "$CHECK" ]; then echo "check ok" >> $LOG; exit 0; fi

# --- the drill must not cut off people who are using the tunnel right now
if [ -z "$FORCE" ] && anyone_active; then
  notify "VPN: drill postponed" "The tunnel is in use right now — no run this time. It will try again next time."
  echo "skip: clients active" >> $LOG
  echo "The tunnel is in use right now — drill postponed."
  echo "To run it anyway: /usr/local/sbin/vpn-drill.sh --force"
  exit 3
fi

# --- move to a separate unit: a dropped ssh session must not kill a run with the block up
if [ -z "$FG" ]; then
  systemctl stop vpn-drill-manual.service >/dev/null 2>&1 || true
  systemctl reset-failed vpn-drill-manual.service >/dev/null 2>&1 || true
  if systemd-run --unit=vpn-drill-manual --description="Drill on request" --quiet \
       /usr/local/sbin/vpn-drill.sh --fg ${FORCE:+--force} >/dev/null 2>&1; then
    echo "Drill started in the background: for a minute or two foreign sites will be unavailable, local sites stay reachable. If you are connected to the server through this VPN, your session will drop — that is expected."
    echo "The report arrives as a push notification. Log: tail -n 20 /var/lib/vpn-monitor/drill.log"
    exit 0
  fi
  echo "systemd-run failed — running the drill in the current process." >&2
fi

BEFORE=$(read_set); BEFORE="${BEFORE:-empty}"
echo "before: $BEFORE" >> $LOG

# --- safety net: lifts the block even if the script dies
systemctl stop drill-cleanup.timer drill-cleanup.service >/dev/null 2>&1 || true
systemctl reset-failed drill-cleanup.service >/dev/null 2>&1 || true
systemd-run --on-active=${SAFETY_MIN}min --unit=drill-cleanup --description="Lift the drill block" \
  /usr/sbin/nft delete table ip drill >/dev/null 2>&1

nft -f - <<EOF
table ip drill
delete table ip drill
table ip drill {
    chain output {
        type filter hook output priority filter; policy accept;
        ip daddr $EXIT_IP tcp dport 443 counter drop
    }
}
EOF
T0=$(date +%s); echo "blocked at $(date -Is)" >> $LOG

# --- wait for the failover (the watchdog should manage within ~90 seconds)
FAILOVER_AT=""
for i in $(seq 1 40); do
  sleep 5
  if python3 -c "import json,sys;sys.exit(0 if json.load(open('$STATE')).get('failover') else 1)" 2>/dev/null; then
    FAILOVER_AT=$(( $(date +%s) - T0 )); break
  fi
done

nft delete table ip drill 2>/dev/null
systemctl stop drill-cleanup.timer 2>/dev/null
echo "restored at $(date -Is)" >> $LOG

# --- wait for the restore
RESTORE_AT=""
for i in $(seq 1 60); do
  sleep 5
  if python3 -c "import json,sys;sys.exit(0 if not json.load(open('$STATE')).get('failover') else 1)" 2>/dev/null; then
    RESTORE_AT=$(( $(date +%s) - T0 )); break
  fi
done

AFTER=$(read_set); AFTER="${AFTER:-empty}"
echo "after: $AFTER | failover=${FAILOVER_AT:-none} restore=${RESTORE_AT:-none}" >> $LOG

if [ -n "$FAILOVER_AT" ] && [ -n "$RESTORE_AT" ] && [ "$BEFORE" = "$AFTER" ]; then
  notify "VPN: drill passed" "Failover to the fallback route ${FAILOVER_AT} s after the outage, restore after ${RESTORE_AT} s. The client set was restored exactly."
else
  notify "VPN: drill needs a look" "Failover: ${FAILOVER_AT:-DID NOT HAPPEN} s, restore: ${RESTORE_AT:-DID NOT HAPPEN} s. Before: $BEFORE / after: $AFTER. Needs a look." urgent
fi
echo "=== $(date -Is) drill end" >> $LOG
