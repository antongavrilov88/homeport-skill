#!/bin/bash
# Install check. Run on the server as root: bash verify.sh
. /etc/vpn-monitor/config.sh 2>/dev/null || true
MODE="${VPN_MODE:-unknown}"
GW="${VPN_GW:-10.67.0.1}"
# What the checks read. The overrides VPN_VERIFY_XRAY_CONFIG, VPN_VERIFY_KIT_VARS and
# VPN_VERIFY_COVER exist only to test this script off a server; on a server they
# are not set and these are the real paths.
XRAY_CONFIG="${VPN_VERIFY_XRAY_CONFIG:-/usr/local/etc/xray/config.json}"
KIT_VARS="${VPN_VERIFY_KIT_VARS:-/opt/vpn-kit/vars.sh}"
COVER="${VPN_VERIFY_COVER:-127.0.0.1:8443}"     # the local cover site, REALITY's target on the exit
ok(){ printf '  \033[32m✓\033[0m %s\n' "$1"; }
no(){ printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=1; }
warn(){ printf '  \033[33m!\033[0m %s\n' "$1"; }    # worth a look, but does not fail the check
FAIL=0
echo "mode: $MODE"

echo "services:"
for u in xray nginx ntfy vpn-monitor vpn-watchdog xray-tproxy-route wg-quick@wg-clients; do
  systemctl cat "$u" >/dev/null 2>&1 || continue      # no such unit: this role does not have it
  if systemctl is-active --quiet "$u"; then ok "$u"; else no "$u is not running"; fi
done

if [ -f "$XRAY_CONFIG" ]; then
  xray run -test -c "$XRAY_CONFIG" >/dev/null 2>&1 && ok "Xray config is valid" || no "Xray config fails its check"
fi

if grep -q '"vnext"' "$XRAY_CONFIG" 2>/dev/null; then
  EXP=$(python3 -c "import json;print(json.load(open('$XRAY_CONFIG'))['outbounds'][0]['settings']['vnext'][0]['address'])")
  GOT=$(curl -s -m 20 -x socks5h://127.0.0.1:1080 https://api.ipify.org || true)
  [ "$GOT" = "$EXP" ] && ok "tunnel works, seen from outside as $GOT" || no "through the tunnel the outside sees '$GOT', expected '$EXP'"
  curl -s -m 8 --interface "$GW" -o /dev/null -w "" https://www.gstatic.com/generate_204 \
    && ok "fallback route (direct exit) works" || no "direct exit from the relay does not work"
else
  DOM=$(python3 -c "import json;print(json.load(open('$XRAY_CONFIG'))['inbounds'][0]['streamSettings']['realitySettings']['serverNames'][0])" 2>/dev/null)
  if [ -n "$DOM" ]; then
    # -verify_hostname: without it any trusted chain passes, whatever name it is for
    echo | timeout 10 openssl s_client -connect "$COVER" -servername "$DOM" -verify_hostname "$DOM" 2>/dev/null \
      | grep -q "Verify return code: 0" && ok "cover site serves a valid certificate for $DOM" \
      || no "no valid certificate for $DOM: REALITY will stand out"
    ss -lntp 2>/dev/null | grep -q ':443 ' && ok "443/tcp is listening" || no "nothing listens on 443/tcp"
  fi
fi

# REALITY stays on 443/tcp with the user's own domain as its target. Xray's release
# notes (v26.3.27) warn that a REALITY server on another port, or pointed at some
# third-party targets, gets its address noticed quickly; nothing else checks that
# this stays true after an edit or a version bump.
#   exit (both profiles): the inbound whose security is "reality" listens on port 443
#     on all addresses, its target (or the older key "dest") is the local cover site
#     127.0.0.1:8443, and its serverNames are exactly the domain;
#   relay: the outbound whose security is "reality" goes to port 443 and its
#     serverName is the domain.
# The domain comes from the DOMAIN= line of the kit's vars.sh, which the installer
# leaves on both machines: not from the Xray config, which would check the config
# against itself. Only that line is read (the file also holds keys) and never run.
# Without it, the server-name part prints "cannot check" instead of failing.
# On the exit this also prints the size of the certificate chain the cover site
# sends: the DER bytes of every certificate in it, summed. Above 8,192 bytes, a
# known REALITY limit (XTLS issue #6356), it prints a warning, not a failure.
reality_check() {
  python3 - "$XRAY_CONFIG" "$KIT_VARS" "$COVER" 2>/dev/null <<'PY'
import base64, ipaddress, json, re, shlex, subprocess, sys

config, kit_vars, cover = sys.argv[1:4]
LOCAL_COVER = ("127.0.0.1:8443", "localhost:8443")    # the target the installer writes


def say(kind, text):                    # one line per finding: ok / no / warn
    print(kind + "\t" + text)


def expected_domain():                 # (domain, "") or ("", why not)
    try:
        with open(kit_vars, encoding="utf-8") as f:
            line = next((ln for ln in f if ln.startswith("DOMAIN=")), "")
    except (OSError, ValueError):
        return "", f"cannot read {kit_vars}"
    try:
        words = shlex.split(line[len("DOMAIN="):])
    except ValueError:
        words = []
    if len(words) == 1 and words[0]:
        return words[0], ""
    return "", f"no DOMAIN in {kit_vars}"


def using_reality(entries):             # [(in- or outbound, its realitySettings)]
    found = []
    for e in entries if isinstance(entries, list) else []:
        stream = e.get("streamSettings") if isinstance(e, dict) else None
        if isinstance(stream, dict) and stream.get("security") == "reality":
            rs = stream.get("realitySettings")
            found.append((e, rs if isinstance(rs, dict) else {}))
    return found


def server_names(rs):
    names = rs.get("serverNames")
    return [str(n) for n in names] if isinstance(names, list) else []


def main():
    try:
        with open(config, encoding="utf-8") as f:
            cfg = json.load(f)
        if not isinstance(cfg, dict):
            raise ValueError
    except (OSError, ValueError):
        say("warn", f"cannot check REALITY: cannot read {config} as JSON")
        return
    domain, why = expected_domain()
    inbounds, outbounds = using_reality(cfg.get("inbounds")), using_reality(cfg.get("outbounds"))
    if not inbounds and not outbounds:
        say("no", "no REALITY inbound or outbound in the Xray config")

    for ib, rs in inbounds:             # the exit, in either profile
        bad = []
        port = ib.get("port")
        if str(port) != "443":
            bad.append(f"REALITY listens on port {'(none)' if port is None else port}, expected 443")
        listen = ib.get("listen") or "0.0.0.0"
        try:
            everywhere = ipaddress.ip_address(listen).is_unspecified
        except ValueError:
            everywhere = False
        if not everywhere:
            bad.append(f"REALITY listens on {listen}, expected all addresses (0.0.0.0)")
        keys = [k for k in ("target", "dest") if k in rs]
        if not keys:
            bad.append(f"REALITY has no target, expected the local cover site {LOCAL_COVER[0]}")
        for k in keys:
            if str(rs[k]) not in LOCAL_COVER:
                bad.append(f"REALITY {k} is {rs[k]}, expected the local cover site {LOCAL_COVER[0]}")
        names = server_names(rs)
        if domain and names != [domain]:
            bad.append(f"REALITY server names are {', '.join(names) or '(none)'}; expected {domain} only")
        for b in bad:
            say("no", b)
        if not bad:
            say("ok", "REALITY on 443/tcp, target the local cover site"
                + (f", server name {domain}" if domain else ""))

    for ob, rs in outbounds:            # the relay
        bad = []
        settings = ob.get("settings") if isinstance(ob.get("settings"), dict) else {}
        servers = settings.get("vnext") if isinstance(settings.get("vnext"), list) else []
        ports = [str(s.get("port")) for s in servers if isinstance(s, dict)]
        if not ports or set(ports) != {"443"}:
            bad.append(f"REALITY to the exit uses port {', '.join(ports) or '(none)'}, expected 443")
        name = str(rs.get("serverName") or "")
        if domain and name != domain:
            bad.append(f"REALITY to the exit uses server name {name or '(none)'}, expected {domain}")
        for b in bad:
            say("no", b)
        if not bad:
            say("ok", "REALITY to the exit on 443/tcp" + (f", server name {domain}" if domain else ""))

    if (inbounds or outbounds) and not domain:
        say("warn", f"cannot check the REALITY server name: {why}")

    if inbounds:                        # the exit: size of the chain the cover site sends
        sni = domain or (server_names(inbounds[0][1]) or [""])[0]
        cmd = ["openssl", "s_client", "-connect", cover, "-showcerts"] + (["-servername", sni] if sni else [])
        try:
            out = subprocess.run(cmd, input="", capture_output=True, text=True, errors="replace",
                                 timeout=10).stdout
            ders = [base64.b64decode("".join(b.split())) for b in
                    re.findall(r"-----BEGIN CERTIFICATE-----(.*?)-----END CERTIFICATE-----", out, re.S)]
        except (OSError, ValueError, subprocess.SubprocessError):
            ders = []
        size = sum(len(d) for d in ders)
        if not ders:
            say("warn", f"cannot check the cover site certificate chain: no certificate from {cover}")
        elif size > 8192:
            say("warn", f"cover site certificate chain: {size:,} bytes, above 8,192, "
                        "a known REALITY limit (XTLS issue #6356)")
        else:
            say("ok", f"cover site certificate chain: {size:,} bytes")


try:
    main()
except Exception as e:                  # an odd config must not silence the check
    say("warn", f"cannot check REALITY: {e!r}")
PY
}
while IFS=$'\t' read -r kind msg; do
  case "$kind" in ok) ok "$msg" ;; no) no "$msg" ;; *) warn "$msg" ;; esac
done < <(reality_check)

if command -v wg >/dev/null && wg show wg-clients >/dev/null 2>&1; then
  N=$(wg show wg-clients dump | tail -n +2 | wc -l)
  ok "WireGuard is up, peers: $N"
  curl -s -m 5 -o /dev/null "http://$GW:${VPN_DASH_PORT:-8088}/api/data?hours=1" \
    && ok "panel answers at http://$GW:8088" || no "panel does not answer"
fi

echo
[ "$FAIL" = 0 ] && echo "all good" || echo "there are findings: see /usr/local/sbin/vpn-diag.sh and journalctl"
exit $FAIL
