#!/usr/bin/env python3
"""A vless:// link for apps (Hiddify, v2rayNG, Streisand, NekoBox).

    python3 client-link.py --params params.json [--label home] [--qr link.png]

Such a client goes straight to the exit machine, bypassing the relay. It is the
personal spare entry for whoever runs the system: it works even while the relay is down.
"""
import argparse, json, subprocess, sys, urllib.parse


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--params", required=True)
    ap.add_argument("--label", default="")
    ap.add_argument("--qr", default="")
    a = ap.parse_args()
    p = json.load(open(a.params, encoding="utf-8"))
    if not p.get("exit_ip"):
        sys.exit("params.json has no exit_ip yet: bring up the exit machine first")
    q = urllib.parse.urlencode({
        "encryption": "none", "security": "reality", "sni": p["domain"], "fp": "chrome",
        "pbk": p["reality_public"], "sid": p["short_direct"], "type": "xhttp",
        "path": p["xhttp_path"], "mode": "auto"})
    label = a.label or p["domain"]
    link = f'vless://{p["uuid_direct"]}@{p["exit_ip"]}:443?{q}#{urllib.parse.quote(label)}'
    print(link)
    if a.qr:
        try:
            subprocess.run(["qrencode", "-t", "PNG", "-m", "1", "-s", "6", "-o", a.qr],
                           input=link.encode(), check=True)
            print(f"QR: {a.qr}", file=sys.stderr)
        except (OSError, subprocess.CalledProcessError):
            print("qrencode is not installed; the link can be pasted by hand", file=sys.stderr)


if __name__ == "__main__":
    main()
