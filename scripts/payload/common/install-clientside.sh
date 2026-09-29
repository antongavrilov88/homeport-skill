#!/bin/bash
# Client side: WireGuard for devices, the panel, the watchdog.
# Used both on the relay (ROLE=relay) and on the only machine (ROLE=single).
set -euo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$KIT/vars.sh"
log() { echo "[$(date +%H:%M:%S)] $*"; }
GW="$WG_SUBNET.1"
WAN=$(ip -o -4 route show to default | awk '{for(i=1;i<NF;i++) if($i=="dev"){print $(i+1); exit}}')
[ -n "$WAN" ] || { echo "no external interface found" >&2; exit 1; }

# The address clients put into Endpoint. If the build ran before the machine's IP
# was known, detect it here; otherwise every issued config is dead.
if [ -z "${CLIENT_ENDPOINT:-}" ]; then
  CLIENT_ENDPOINT=$(curl -s -m 10 https://api.ipify.org 2>/dev/null || true)
  [ -n "$CLIENT_ENDPOINT" ] || CLIENT_ENDPOINT=$(ip -o -4 addr show dev "$WAN" scope global | awk '{print $4}' | cut -d/ -f1 | head -1)
  log "client endpoint address detected automatically: $CLIENT_ENDPOINT"
fi
[ -n "$CLIENT_ENDPOINT" ] || { echo "could not detect the public address: put client_endpoint into params.json" >&2; exit 1; }

command -v wg >/dev/null || { export DEBIAN_FRONTEND=noninteractive; apt-get install -y -qq wireguard-tools qrencode; }

# ---------------------------------------------------------------- WireGuard
install -d -m700 /etc/wireguard
if [ ! -f /etc/wireguard/wg-clients.conf ]; then
  log "creating wg-clients"
  SRV_PRIV=$(wg genkey)
  umask 077
  printf '%s\n' "$SRV_PRIV" > /etc/wireguard/wg-clients.private
  printf '%s\n' "$SRV_PRIV" | wg pubkey > /etc/wireguard/wg-clients.public
  cat > /etc/wireguard/wg-clients.conf <<EOF
[Interface]
Address = $GW/24
ListenPort = $WG_PORT
PrivateKey = $SRV_PRIV
MTU = 1280
PostUp   = sysctl -qw net.ipv4.ip_forward=1
PostUp   = nft add table ip vpnnat 2>/dev/null || true
PostUp   = nft 'add chain ip vpnnat post { type nat hook postrouting priority srcnat; }' 2>/dev/null || true
PostUp   = nft add rule ip vpnnat post ip saddr $WG_SUBNET.0/24 oifname "$WAN" masquerade
PostDown = nft delete table ip vpnnat 2>/dev/null || true
EOF
  chmod 600 /etc/wireguard/wg-clients.conf
else
  log "wg-clients already exists, leaving it alone"
fi
systemctl enable --now wg-quick@wg-clients >/dev/null 2>&1 || systemctl restart wg-quick@wg-clients

# ---------------------------------------------------------------- udp/443 for strict networks
install -d -m755 /etc/xray
cat > /etc/xray/wgports.nft <<EOF
#!/usr/sbin/nft -f
# Accept WireGuard clients on udp/443 as well: some networks (hotels, mobile
# carriers) let only 443 through and drop high UDP ports.
table ip wgports
delete table ip wgports
table ip wgports {
    chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        iifname "$WAN" udp dport $ALT_PORT redirect to :$WG_PORT
    }
}
EOF
nft -f /etc/xray/wgports.nft
install -m644 "$KIT/common/systemd/vpn-wgports.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable vpn-wgports >/dev/null 2>&1 || true

# ---------------------------------------------------------------- monitor files
log "installing the monitor, the panel and the watchdog"
install -d -m755 /usr/local/sbin /usr/local/share/vpn-monitor /etc/vpn-monitor
install -d -m750 /var/lib/vpn-monitor
install -m755 "$KIT/common/vpn-monitor.py"  /usr/local/sbin/vpn-monitor.py
install -m755 "$KIT/common/vpn-watchdog.py" /usr/local/sbin/vpn-watchdog.py
install -m755 "$KIT/common/vpn-diag.sh"     /usr/local/sbin/vpn-diag.sh
install -m644 "$KIT/common/dashboard.html"  /usr/local/share/vpn-monitor/index.html
install -m755 "$KIT/common/verify.sh"       /usr/local/sbin/vpn-verify.sh
if [ "$ROLE" != "single" ]; then
  install -m755 "$KIT/common/vpn-split.py" /usr/local/sbin/vpn-split.py
  install -m755 "$KIT/common/vpn-drill.sh" /usr/local/sbin/vpn-drill.sh
fi

cat > /etc/vpn-monitor/config.json <<EOF
{
  "mode": "$([ "$ROLE" = single ] && echo single || echo relay)",
  "server_host": "$CLIENT_ENDPOINT",
  "wg_subnet": "$WG_SUBNET",
  "wg_port": $WG_PORT,
  "alt_port": $ALT_PORT,
  "client_dns": "$CLIENT_DNS",
  "client_mtu": 1280,
  "dashboard_port": $DASH_PORT,
  "home_geoip": "$HOME_GEOIP"
}
EOF
cat > /etc/vpn-monitor/config.sh <<EOF
VPN_MODE=$([ "$ROLE" = single ] && echo single || echo relay)
VPN_GW=$GW
VPN_SUBNET=$WG_SUBNET
VPN_WAN=$WAN
VPN_DASH_PORT=$DASH_PORT
EOF

[ -f /etc/vpn-monitor/admin-token ] || printf '%s\n' "$DASH_TOKEN" > /etc/vpn-monitor/admin-token
chmod 600 /etc/vpn-monitor/admin-token
[ -f /etc/vpn-monitor/names.json ] || echo '{}' > /etc/vpn-monitor/names.json

if [ ! -f /etc/vpn-monitor/alerts.json ]; then
  python3 - <<PY
import json
targets = []
if "$NTFY_SERVER" and "$NTFY_TOPIC" and "$NTFY_ALERT_TOKEN":
    targets.append({"server": "$NTFY_SERVER", "topic": "$NTFY_TOPIC", "token": "$NTFY_ALERT_TOKEN"})
if "$NTFY_PUBLIC_TOPIC":
    targets.append({"server": "https://ntfy.sh", "topic": "$NTFY_PUBLIC_TOPIC"})
json.dump({"ntfy_targets": targets, "telegram": {"token": "", "chat_id": ""}},
          open("/etc/vpn-monitor/alerts.json", "w"), indent=2)
PY
  chmod 600 /etc/vpn-monitor/alerts.json
fi

if [ "$ROLE" != "single" ] && [ ! -f /etc/vpn-monitor/direct-domains.txt ]; then
  install -m644 "$KIT/relay/direct-domains.txt" /etc/vpn-monitor/direct-domains.txt
fi

# ---------------------------------------------------------------- units
install -m644 "$KIT/common/systemd/vpn-monitor.service"  /etc/systemd/system/
install -m644 "$KIT/common/systemd/vpn-watchdog.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable vpn-monitor vpn-watchdog >/dev/null 2>&1
systemctl restart vpn-monitor
# the calling installer starts the watchdog, after Xray is up; otherwise the
# very first probe raises a false alarm in the middle of the install
log "client side ready: panel http://$GW:$DASH_PORT"
