#!/bin/bash
# Install check. Run on the server as root: bash verify.sh
. /etc/vpn-monitor/config.sh 2>/dev/null || true
MODE="${VPN_MODE:-unknown}"
GW="${VPN_GW:-10.67.0.1}"
ok(){ printf '  \033[32m✓\033[0m %s\n' "$1"; }
no(){ printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=1; }
FAIL=0
echo "mode: $MODE"

echo "services:"
for u in xray nginx ntfy vpn-monitor vpn-watchdog xray-tproxy-route wg-quick@wg-clients; do
  systemctl cat "$u" >/dev/null 2>&1 || continue      # no such unit: this role does not have it
  if systemctl is-active --quiet "$u"; then ok "$u"; else no "$u is not running"; fi
done

if [ -f /usr/local/etc/xray/config.json ]; then
  xray run -test -c /usr/local/etc/xray/config.json >/dev/null 2>&1 && ok "Xray config is valid" || no "Xray config fails its check"
fi

if grep -q '"vnext"' /usr/local/etc/xray/config.json 2>/dev/null; then
  EXP=$(python3 -c "import json;print(json.load(open('/usr/local/etc/xray/config.json'))['outbounds'][0]['settings']['vnext'][0]['address'])")
  GOT=$(curl -s -m 20 -x socks5h://127.0.0.1:1080 https://api.ipify.org || true)
  [ "$GOT" = "$EXP" ] && ok "tunnel works, seen from outside as $GOT" || no "through the tunnel the outside sees '$GOT', expected '$EXP'"
  curl -s -m 8 --interface "$GW" -o /dev/null -w "" https://www.gstatic.com/generate_204 \
    && ok "fallback route (direct exit) works" || no "direct exit from the relay does not work"
else
  DOM=$(python3 -c "import json;print(json.load(open('/usr/local/etc/xray/config.json'))['inbounds'][0]['streamSettings']['realitySettings']['serverNames'][0])" 2>/dev/null)
  if [ -n "$DOM" ]; then
    echo | timeout 10 openssl s_client -connect 127.0.0.1:8443 -servername "$DOM" 2>/dev/null \
      | grep -q "Verify return code: 0" && ok "cover site serves a valid certificate" \
      || no "no certificate served for $DOM: REALITY will stand out"
    ss -lntp 2>/dev/null | grep -q ':443 ' && ok "443/tcp is listening" || no "nothing listens on 443/tcp"
  fi
fi

if command -v wg >/dev/null && wg show wg-clients >/dev/null 2>&1; then
  N=$(wg show wg-clients dump | tail -n +2 | wc -l)
  ok "WireGuard is up, peers: $N"
  curl -s -m 5 -o /dev/null "http://$GW:${VPN_DASH_PORT:-8088}/api/data?hours=1" \
    && ok "panel answers at http://$GW:8088" || no "panel does not answer"
fi

echo
[ "$FAIL" = 0 ] && echo "all good" || echo "there are findings: see /usr/local/sbin/vpn-diag.sh and journalctl"
exit $FAIL
