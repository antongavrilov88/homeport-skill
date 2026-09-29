#!/bin/bash
# Exit machine install: VLESS + XHTTP + REALITY on 443, a real site under the
# same domain (self-steal), certificates, ntfy for notifications.
# With ROLE=single this also brings up WireGuard for clients, the panel and the watchdog.
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
PKGS="curl ca-certificates nginx certbot python3-certbot-nginx nftables jq unzip"
[ "$ROLE" = "single" ] && PKGS="$PKGS wireguard-tools qrencode python3 iproute2"
$APT install $PKGS

# ---------------------------------------------------------------- Xray
if ! command -v xray >/dev/null || ! xray version 2>/dev/null | grep -q "${XRAY_VERSION#v}"; then
  log "installing Xray $XRAY_VERSION"
  bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" \
    @ install --version "${XRAY_VERSION#v}" >/dev/null
fi
command -v xray >/dev/null || die "Xray did not install"

# ---------------------------------------------------------------- cover site
log "laying out the site for $DOMAIN"
install -d -m755 "/var/www/$DOMAIN"
sed -e "s|__SITE_TITLE__|$SITE_TITLE|g" \
    -e "s|__SITE_TAGLINE__|$SITE_TAGLINE|g" \
    -e "s|__DOMAIN__|$DOMAIN|g" \
    -e "s|__DATE_1__|$(date -d '-8 days' +%d.%m.%Y 2>/dev/null || date +%d.%m.%Y)|g" \
    -e "s|__DATE_2__|$(date -d '-31 days' +%d.%m.%Y 2>/dev/null || date +%d.%m.%Y)|g" \
    -e "s|__DATE_3__|$(date -d '-74 days' +%d.%m.%Y 2>/dev/null || date +%d.%m.%Y)|g" \
    "$KIT/site/index.html" > "/var/www/$DOMAIN/index.html"

# ---------------------------------------------------------------- nginx :80 + certificates
log "nginx on 80 and certificates"
rm -f /etc/nginx/sites-enabled/default
cat > "/etc/nginx/sites-available/$DOMAIN-http" <<EOF
server {
    listen 80; listen [::]:80;
    server_name $DOMAIN${PUSH_DOMAIN:+ $PUSH_DOMAIN};
    root /var/www/$DOMAIN;
    location /.well-known/acme-challenge/ { allow all; }
    location / { return 301 https://\$host\$request_uri; }
}
EOF
ln -sf "/etc/nginx/sites-available/$DOMAIN-http" "/etc/nginx/sites-enabled/$DOMAIN-http"
nginx -t || die "nginx config fails its check"
systemctl reload nginx

certbot_for() {
  local d="$1"
  [ -d "/etc/letsencrypt/live/$d" ] && { log "certificate for $d already exists"; return 0; }
  for attempt in 1 2 3 4 5 6; do
    if certbot certonly --webroot -w "/var/www/$DOMAIN" -d "$d" \
         --non-interactive --agree-tos -m "$ACME_EMAIL" >/dev/null 2>&1; then
      log "certificate for $d obtained"; return 0
    fi
    log "certificate for $d failed (attempt $attempt), waiting for DNS, 60 s"
    sleep 60
  done
  return 1
}
certbot_for "$DOMAIN" || die "could not obtain a certificate for $DOMAIN. Check that the A record of $DOMAIN points at this server and run the script again."
PUSH_OK=0
# The public ntfy.sh topic is not a fallback: every alert goes there in any case,
# alongside the own ntfy. Without a certificate the own ntfy is simply not set up.
if [ -n "${PUSH_DOMAIN:-}" ]; then certbot_for "$PUSH_DOMAIN" && PUSH_OK=1 || log "no certificate for the ntfy domain, no own ntfy server: alerts go to the public ntfy.sh topic only"; fi

# ---------------------------------------------------------------- nginx :8443 (self-steal target)
cat > "/etc/nginx/sites-available/$DOMAIN-https" <<EOF
server {
    # only active probing through REALITY and local requests land here
    listen 127.0.0.1:8443 ssl;
    http2 on;
    server_name $DOMAIN;
    ssl_certificate     /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_tickets off;
    root /var/www/$DOMAIN;
    index index.html;
}
EOF
ln -sf "/etc/nginx/sites-available/$DOMAIN-https" "/etc/nginx/sites-enabled/$DOMAIN-https"

# ---------------------------------------------------------------- ntfy
NTFY_OK=0
if [ "$PUSH_OK" = 1 ] && [ -n "${NTFY_VERSION:-}" ]; then
  log "installing ntfy $NTFY_VERSION"
  ARCH=$(dpkg --print-architecture)
  if curl -fsSL -o /tmp/ntfy.deb \
      "https://github.com/binwiederhier/ntfy/releases/download/${NTFY_VERSION}/ntfy_${NTFY_VERSION#v}_linux_${ARCH}.deb"; then
    apt-get install -y -qq /tmp/ntfy.deb >/dev/null && rm -f /tmp/ntfy.deb
    install -d -m755 /etc/ntfy /var/lib/ntfy
    cat > /etc/ntfy/server.yml <<EOF
base-url: "https://$PUSH_DOMAIN"
listen-http: "127.0.0.1:2586"
cache-file: "/var/lib/ntfy/cache.db"
auth-file: "/var/lib/ntfy/user.db"
auth-default-access: "deny-all"
behind-proxy: true
# iOS keeps no background connection; only ntfy.sh can wake the phone. The wake-up
# goes upstream as a message ID under a hashed topic name, no title, no text; the
# phone then fetches the alert from this server.
upstream-base-url: "https://ntfy.sh"
EOF
    chown -R ntfy:ntfy /var/lib/ntfy 2>/dev/null || true
    systemctl enable ntfy >/dev/null 2>&1 || true
    systemctl restart ntfy >/dev/null 2>&1 || true
    sleep 3
    NTFY_PASSWORD="$NTFY_PASS" ntfy user add --role=user "$NTFY_USER" >/dev/null 2>&1 || true
    ntfy access "$NTFY_USER" "$NTFY_TOPIC" rw >/dev/null 2>&1 || true
    NTFY_PASSWORD="$(openssl rand -base64 18)" ntfy user add --role=user alerts >/dev/null 2>&1 || true
    ntfy access alerts "$NTFY_TOPIC" write-only >/dev/null 2>&1 || true
    ALERT_TOKEN=$(ntfy token add alerts 2>/dev/null | grep -o 'tk_[a-z0-9]*' | head -1 || true)
    chown -R ntfy:ntfy /var/lib/ntfy 2>/dev/null || true
    systemctl restart ntfy >/dev/null 2>&1 || true
    if [ -n "$ALERT_TOKEN" ]; then
      sed -i "s|^NTFY_ALERT_TOKEN=.*|NTFY_ALERT_TOKEN='$ALERT_TOKEN'|" "$KIT/vars.sh"
      NTFY_ALERT_TOKEN="$ALERT_TOKEN"
    fi
    cat > "/etc/nginx/sites-available/$PUSH_DOMAIN-https" <<EOF
server {
    listen 127.0.0.1:8443 ssl;
    http2 on;
    server_name $PUSH_DOMAIN;
    ssl_certificate     /etc/letsencrypt/live/$PUSH_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$PUSH_DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    client_max_body_size 20M;
    location / {
        proxy_pass http://127.0.0.1:2586;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_connect_timeout 3m; proxy_send_timeout 3m; proxy_read_timeout 3m;
        proxy_buffering off;
    }
}
EOF
    ln -sf "/etc/nginx/sites-available/$PUSH_DOMAIN-https" "/etc/nginx/sites-enabled/$PUSH_DOMAIN-https"
    NTFY_OK=1
  else
    log "could not download ntfy, no own ntfy server: alerts go to the public ntfy.sh topic only"
  fi
fi
nginx -t || die "nginx config fails its check"
systemctl reload nginx

# ---------------------------------------------------------------- Xray: inbound REALITY
log "configuring Xray"
install -d -m755 /usr/local/etc/xray
python3 - <<PY
import json
clients = [{"id": "$UUID_RELAY", "email": "relay"}]
if "$UUID_DIRECT":
    clients.append({"id": "$UUID_DIRECT", "email": "direct"})
short = [s for s in ["$SHORT_RELAY", "$SHORT_DIRECT"] if s]
cfg = {
  "log": {"loglevel": "warning", "access": "none", "error": "", "dnsLog": False},
  "inbounds": [{
    "tag": "vless-xhttp-reality", "listen": "0.0.0.0", "port": 443, "protocol": "vless",
    "settings": {"clients": clients, "decryption": "none"},
    "streamSettings": {
      "network": "xhttp", "security": "reality",
      "realitySettings": {"show": False, "target": "127.0.0.1:8443",
                          "serverNames": ["$DOMAIN"],
                          "privateKey": "$REALITY_PRIVATE", "shortIds": short},
      "xhttpSettings": {"path": "$XHTTP_PATH", "mode": "auto"}},
    "sniffing": {"enabled": True, "destOverride": ["http", "tls", "quic"]}}],
  "outbounds": [{"tag": "direct", "protocol": "freedom"},
                {"tag": "block", "protocol": "blackhole"}],
  "routing": {"domainStrategy": "AsIs",
              "rules": [{"type": "field", "ip": ["geoip:private"], "outboundTag": "block"}]}
}
if "$ROLE" == "single":
    # local socks: through it the watchdog probes that the machine is online at all
    cfg["inbounds"].append({"tag": "socks-test", "listen": "127.0.0.1", "port": 1080,
                            "protocol": "socks", "settings": {"udp": True}})
    cfg["routing"]["rules"].append({"type": "field", "inboundTag": ["socks-test"],
                                    "outboundTag": "direct"})
json.dump(cfg, open("/usr/local/etc/xray/config.json", "w"), indent=2)
PY
# The config holds the REALITY private key. Xray runs as nobody, hence 640 with
# the group rather than 644: other local processes must not be able to read it.
chgrp nogroup /usr/local/etc/xray/config.json 2>/dev/null || true
chmod 640 /usr/local/etc/xray/config.json
xray run -test -c /usr/local/etc/xray/config.json >/dev/null || die "Xray config fails its check"
systemctl enable --now xray >/dev/null 2>&1
systemctl restart xray

# ---------------------------------------------------------------- certificate renewal
install -d -m755 /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/reload.sh <<'EOF'
#!/bin/sh
systemctl reload nginx || true
EOF
chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload.sh
systemctl enable --now certbot.timer >/dev/null 2>&1 || true

# ---------------------------------------------------------------- firewall
log "firewall"
# Own table, no flush ruleset: the vpnnat and wgports tables live separately
# and must not vanish when the firewall is reloaded.
cat > /etc/nftables.conf <<EOF
#!/usr/sbin/nft -f
table inet filter
delete table inet filter
table inet filter {
    chain input {
        type filter hook input priority filter; policy drop;
        ct state established,related accept
        iif lo accept
$([ "$ROLE" = "single" ] && echo '        iifname "wg-clients" accept')
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept
        tcp dport { 22, 80, 443 } accept
$([ "$ROLE" = "single" ] && echo "        udp dport { 443, $WG_PORT } accept")
    }
    chain forward { type filter hook forward priority filter; policy accept; }
    chain output  { type filter hook output  priority filter; policy accept; }
}
EOF
nft -f /etc/nftables.conf
systemctl enable --now nftables >/dev/null 2>&1 || true

# ---------------------------------------------------------------- verify script
install -d -m755 /etc/vpn-monitor /usr/local/sbin
install -m755 "$KIT/common/verify.sh" /usr/local/sbin/vpn-verify.sh
[ -f /etc/vpn-monitor/config.sh ] || printf 'VPN_MODE=exit\n' > /etc/vpn-monitor/config.sh

# ---------------------------------------------------------------- one machine: client side
if [ "$ROLE" = "single" ]; then
  log "bringing up WireGuard for clients"
  bash "$KIT/common/install-clientside.sh"
  systemctl restart vpn-watchdog
fi

# ---------------------------------------------------------------- summary
install -d -m700 /root/vpn-kit
cat > /root/vpn-kit/exit-summary.txt <<EOF
domain           $DOMAIN
push domain      ${PUSH_DOMAIN:-(none)}  ntfy: $([ "$NTFY_OK" = 1 ] && echo "own server, topic $NTFY_TOPIC" || echo "public ntfy.sh only")
ntfy alerts token ${ALERT_TOKEN:-(none)}
uuid relay       $UUID_RELAY
uuid direct      ${UUID_DIRECT:-(none)}
reality pubkey   $REALITY_PUBLIC
shortId relay    $SHORT_RELAY
shortId direct   ${SHORT_DIRECT:-(none)}
xhttp path       $XHTTP_PATH
EOF
chmod 600 /root/vpn-kit/exit-summary.txt
echo
echo "=== EXIT MACHINE READY ==="
systemctl is-active xray nginx 2>/dev/null | tr '\n' ' ' || true; echo
echo "ntfy-alerts-token: ${ALERT_TOKEN:-none}"
echo "summary: /root/vpn-kit/exit-summary.txt"
