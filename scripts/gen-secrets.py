#!/usr/bin/env python3
"""Generates the secrets for a new install. No external dependencies.

    python3 gen-secrets.py --domain example.com [--push push.example.com] \
        [--email me@example.com] [--mode relay|single] > params.json
"""
import argparse, base64, json, os, secrets, string, uuid

P = 2 ** 255 - 19


def _mul(k: bytes, u: bytes) -> bytes:
    """X25519 per RFC 7748 in pure Python, so no dependencies are pulled in."""
    def dec(b):
        b = bytearray(b)
        b[31] &= 127
        return int.from_bytes(b, "little")

    kk = bytearray(k)
    kk[0] &= 248
    kk[31] &= 127
    kk[31] |= 64
    k_int = int.from_bytes(kk, "little")
    x1 = dec(u)
    x2, z2, x3, z3, swap = 1, 0, x1, 1, 0
    for t in range(254, -1, -1):
        kt = (k_int >> t) & 1
        swap ^= kt
        if swap:
            x2, x3 = x3, x2
            z2, z3 = z3, z2
        swap = kt
        a = (x2 + z2) % P
        aa = a * a % P
        b = (x2 - z2) % P
        bb = b * b % P
        e = (aa - bb) % P
        c = (x3 + z3) % P
        d = (x3 - z3) % P
        da = d * a % P
        cb = c * b % P
        x3 = (da + cb) % P
        x3 = x3 * x3 % P
        z3 = (da - cb) % P
        z3 = x1 * z3 % P * z3 % P
        x2 = aa * bb % P
        z2 = e * (aa + 121665 * e) % P
    if swap:
        x2, x3 = x3, x2
        z2, z3 = z3, z2
    return (x2 * pow(z2, P - 2, P) % P).to_bytes(32, "little")


def b64u(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).decode().rstrip("=")


def x25519_pair():
    priv = bytearray(secrets.token_bytes(32))
    priv[0] &= 248
    priv[31] &= 127
    priv[31] |= 64
    priv = bytes(priv)
    pub = _mul(priv, (9).to_bytes(32, "little"))
    return b64u(priv), b64u(pub)


def _selfcheck():
    """RFC 7748 §6.1 test vector: if it does not match, the keys must not be used."""
    a = bytes.fromhex("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a")
    apub = bytes.fromhex("8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a")
    b = bytes.fromhex("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb")
    k = bytes.fromhex("4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742")
    nine = (9).to_bytes(32, "little")
    assert _mul(a, nine) == apub, "x25519 self-check failed"
    assert _mul(b, apub) == k, "x25519 self-check failed"


def pw(n=18):
    al = string.ascii_letters + string.digits
    return "".join(secrets.choice(al) for _ in range(n))


def main():
    _selfcheck()
    ap = argparse.ArgumentParser()
    ap.add_argument("--domain", required=True)
    ap.add_argument("--push", default="")
    ap.add_argument("--email", default="")
    ap.add_argument("--mode", default="relay", choices=["relay", "single"])
    ap.add_argument("--wg-subnet", default="10.67.0")
    ap.add_argument("--wg-port", type=int, default=51821)
    ap.add_argument("--home-geoip", default="")
    ap.add_argument("--site-title", default="")
    ap.add_argument("--site-tagline", default="Notes on self-hosting")
    ap.add_argument("--xray-version", default="v26.3.27")
    ap.add_argument("--ntfy-version", default="v2.27.0")
    a = ap.parse_args()

    priv, pub = x25519_pair()
    dom = a.domain.strip().lower().lstrip(".")
    p = {
        "mode": a.mode,
        "domain": dom,
        "push_domain": a.push or ("push." + dom),
        "acme_email": a.email or ("admin@" + dom),
        "site_title": a.site_title or dom,
        "site_tagline": a.site_tagline,
        "uuid_relay": str(uuid.uuid4()),
        "uuid_direct": str(uuid.uuid4()),
        "reality_private": priv,
        "reality_public": pub,
        "short_relay": secrets.token_hex(8),
        "short_direct": secrets.token_hex(8),
        "xhttp_path": "/" + secrets.token_hex(6),
        "wg_subnet": a.wg_subnet,
        "wg_port": a.wg_port,
        "alt_port": 443,
        "client_dns": "1.1.1.1",
        "dashboard_port": 8088,
        "dashboard_token": pw(14),
        "home_geoip": a.home_geoip,
        "ntfy_topic": "vpn-" + secrets.token_hex(6),
        "ntfy_user": "phone",
        "ntfy_pass": pw(14),
        "ntfy_public_topic": "vpn-" + secrets.token_hex(8),
        "xray_version": a.xray_version,
        "ntfy_version": a.ntfy_version,
        "exit_ip": "",
        "relay_ip": "",
        "client_endpoint": "",
    }
    print(json.dumps(p, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
