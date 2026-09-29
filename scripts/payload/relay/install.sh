#!/bin/bash
# Relay install: WireGuard for clients, transparent interception of their traffic into
# Xray, from there VLESS + XHTTP + REALITY to the exit machine. Plus the panel, the watchdog and the drill.
set -euo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$KIT/vars.sh"
export DEBIAN_FRONTEND=noninteractive
log() { echo "[$(date +%H:%M:%S)] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || die "run as root"

log "installing packages"
APT="apt-get -o DPkg::Lock::Timeout=600 -y -qq"
for i in 1 2 3; do $APT update && break || { log "apt update failed ($i), waiting"; sleep 20; }; done
$APT install curl ca-certificates nftables wireguard-tools qrencode python3 iproute2 jq

# ---------------------------------------------------------------- Xray
if ! command -v xray >/dev/null || ! xray version 2>/dev/null | grep -q "${XRAY_VERSION#v}"; then
  log "installing Xray $XRAY_VERSION"
  bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" \
    @ install --version "${XRAY_VERSION#v}" >/dev/null
fi
command -v xray >/dev/null || die "Xray did not install"

# ---------------------------------------------------------------- REALITY client
[ -n "$EXIT_IP" ] || die "the installer has no exit machine address. Put exit_ip into params.json and rebuild: python3 scripts/build-installers.py --params params.json --out ./out"
log "configuring Xray (REALITY client → $EXIT_IP)"
install -d -m755 /usr/local/etc/xray
python3 - <<PY
import json
cfg = {
  "log": {"loglevel": "warning", "access": "none", "error": "", "dnsLog": False},
  "inbounds": [
    {"tag": "tproxy-in", "listen": "0.0.0.0", "port": 12345, "protocol": "dokodemo-door",
     "settings": {"network": "tcp,udp", "followRedirect": True},
     "streamSettings": {"sockopt": {"tproxy": "tproxy"}},
     "sniffing": {"enabled": True, "destOverride": ["http", "tls", "quic"], "routeOnly": True}},
    {"tag": "socks-test", "listen": "127.0.0.1", "port": 1080, "protocol": "socks",
     "settings": {"udp": True}}],
  "outbounds": [
    {"tag": "proxy", "protocol": "vless",
     "settings": {"vnext": [{"address": "$EXIT_IP", "port": 443,
                             "users": [{"id": "$UUID_RELAY", "encryption": "none"}]}]},
     "streamSettings": {
        "network": "xhttp", "security": "reality",
        "realitySettings": {"serverName": "$DOMAIN", "fingerprint": "chrome",
                            "password": "$REALITY_PUBLIC", "publicKey": "$REALITY_PUBLIC",
                            "shortId": "$SHORT_RELAY", "spiderX": "/"},
        "xhttpSettings": {"path": "$XHTTP_PATH", "mode": "auto"},
        "sockopt": {"mark": 255}}},
    {"tag": "direct", "protocol": "freedom", "streamSettings": {"sockopt": {"mark": 255}}},
    {"tag": "block", "protocol": "blackhole"}],
  "routing": {"domainStrategy": "IPIfNonMatch", "rules": [
    {"type": "field", "inboundTag": ["tproxy-in"], "network": "udp", "port": 443,
     "outboundTag": "block"},
    {"type": "field", "inboundTag": ["tproxy-in", "socks-test"], "outboundTag": "proxy"}]}
}
json.dump(cfg, open("/usr/local/etc/xray/config.json", "w"), indent=2)
PY
xray run -test -c /usr/local/etc/xray/config.json >/dev/null || die "Xray config fails its check"

# ---------------------------------------------------------------- traffic interception
log "interception rules"
install -d -m755 /etc/xray
MYIP=$(curl -s -m 10 https://api.ipify.org || ip -o -4 addr show scope global | awk '{print $4}' | cut -d/ -f1 | head -1)
# If the file already exists, keep the current proxied_src members: a re-run of
# the installer must not silently take every client off the tunnel.
KEEP=$(python3 - <<'PYEOF' || true
import re
try:
    src = open("/etc/xray/xray-tproxy.nft").read()
    m = re.search(r"set proxied_src \{[^}]*elements = \{([^}]*)\}", src, re.S)
    print(", ".join(re.findall(r"[\d./]+", m.group(1))) if m else "")
except Exception:
    print("")
PYEOF
)
ELEMENTS=""
[ -n "$KEEP" ] && ELEMENTS="
        elements = { $KEEP }"
[ -n "$KEEP" ] && log "keeping the current tunnel members: $KEEP"
cat > /etc/xray/xray-tproxy.nft <<EOF
#!/usr/sbin/nft -f
# Redirect the traffic of the selected wg-clients into Xray (dokodemo-door :12345).
# proxied_src lists who goes through the tunnel. Anyone not here leaves the relay directly.
table ip xray_tproxy
delete table ip xray_tproxy
table ip xray_tproxy {
    set proxied_src {
        type ipv4_addr
        flags interval$ELEMENTS
    }
    set bypass {
        type ipv4_addr
        flags interval
        elements = { 0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16,
                     172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 240.0.0.0/4,
                     $MYIP, $EXIT_IP }
    }
    chain prerouting {
        type filter hook prerouting priority mangle; policy accept;
        iifname != "wg-clients" return
        ip saddr != @proxied_src return
        ip daddr @bypass return
        meta l4proto { tcp, udp } tproxy to :12345 meta mark set 1 accept
    }
}
EOF

# ---------------------------------------------------------------- firewall
# Own table, no flush ruleset: xray_tproxy, wgports and vpnnat live separately.
cat > /etc/nftables.conf <<EOF
#!/usr/sbin/nft -f
table inet filter
delete table inet filter
table inet filter {
    chain input {
        type filter hook input priority filter; policy drop;
        ct state established,related accept
        iif lo accept
        iifname "wg-clients" accept
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept
        tcp dport 22 accept
        udp dport { $WG_PORT, $ALT_PORT } accept
    }
    chain forward { type filter hook forward priority filter; policy accept; }
    chain output  { type filter hook output  priority filter; policy accept; }
}
EOF
nft -f /etc/nftables.conf
systemctl enable --now nftables >/dev/null 2>&1 || true

# ---------------------------------------------------------------- client side
# (creates wg-clients and /etc/xray/wgports.nft, which the next unit needs)
bash "$KIT/common/install-clientside.sh"

# ---------------------------------------------------------------- units and start
install -m644 "$KIT/relay/systemd/"*.service "$KIT/relay/systemd/"*.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable xray xray-tproxy-route >/dev/null 2>&1
systemctl restart xray-tproxy-route
systemctl restart xray

# ---------------------------------------------------------------- route split
log "route split"
python3 /usr/local/sbin/vpn-split.py || die "vpn-split failed"

# the watchdog last, once the tunnel is up
systemctl restart vpn-watchdog
systemctl enable --now vpn-drill.timer vpn-drill-check.timer >/dev/null 2>&1 || true

# ---------------------------------------------------------------- check
log "checking the tunnel"
sleep 4
OUTIP=$(curl -s -m 20 -x socks5h://127.0.0.1:1080 https://api.ipify.org || true)
echo
echo "=== RELAY READY ==="
systemctl is-active xray vpn-monitor vpn-watchdog xray-tproxy-route wg-quick@wg-clients 2>/dev/null | tr '\n' ' ' || true; echo
if [ "$OUTIP" = "$EXIT_IP" ]; then
  echo "tunnel works: the exit is seen as $OUTIP"
else
  echo "WARNING: through the tunnel the outside sees '$OUTIP', expected '$EXIT_IP'."
  echo "See: journalctl -u xray -n 40  and  /usr/local/sbin/vpn-diag.sh"
fi
echo "panel: http://$WG_SUBNET.1:$DASH_PORT (from inside the VPN), code $DASH_TOKEN"
