#!/usr/bin/env python3
"""Privacy-preserving VPN monitor + control panel.

Collects ONLY per-peer byte counters and handshake times from WireGuard.
Never records destinations, domains, ports or packet contents.
Serves the dashboard on the VPN-internal address, and lets the operator
switch a client between routes and edit the direct-domain list.
"""
import json, os, re, shutil, sqlite3, subprocess, threading, time, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DB = "/var/lib/vpn-monitor/stats.db"
HEALTH = "/var/lib/vpn-monitor/health.json"
HTML = "/usr/local/share/vpn-monitor/index.html"
NAMES = "/etc/vpn-monitor/names.json"
DIRECT = "/etc/vpn-monitor/direct-domains.txt"
SPLIT = "/usr/local/sbin/vpn-split.py"
WG_IF = "wg-clients"
INTERVAL = 60
KEEP_DAYS = 14
IPRE = re.compile(r"^\d{1,3}(\.\d{1,3}){3}$")
DOMRE = re.compile(r"^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$")
NAMERE = re.compile(r"^[^\W_][\w \-.()]{0,39}$", re.UNICODE)
TRANSLIT = {"а":"a","б":"b","в":"v","г":"g","д":"d","е":"e","ё":"e","ж":"zh","з":"z","и":"i","й":"y",
            "к":"k","л":"l","м":"m","н":"n","о":"o","п":"p","р":"r","с":"s","т":"t","у":"u","ф":"f",
            "х":"h","ц":"c","ч":"ch","ш":"sh","щ":"sch","ъ":"","ы":"y","ь":"","э":"e","ю":"yu","я":"ya"}
WGDIR = "/etc/wireguard"
WGCONF = WGDIR + "/wg-clients.conf"
TOKEN_FILE = "/etc/vpn-monitor/admin-token"
CONFIG = "/etc/vpn-monitor/config.json"


def conf():
    try:
        return json.load(open(CONFIG))
    except Exception:
        return {}


C = conf()
MODE = C.get("mode", "relay")                 # "relay" (two hops) or "single" (one machine)
SERVER_HOST = C.get("server_host", "")        # what clients put in Endpoint
SUBNET = C.get("wg_subnet", "10.67.0")        # first three octets of the client network
GW = SUBNET + ".1"                            # the server's own address inside the tunnel
WG_PORT = int(C.get("wg_port", 51821))
ALT_PORT = int(C.get("alt_port", 443))
CLIENT_DNS = C.get("client_dns", "1.1.1.1")
CLIENT_MTU = int(C.get("client_mtu", 1280))
DASH_PORT = int(C.get("dashboard_port", 8088))
BIND = [(GW, DASH_PORT), ("127.0.0.1", DASH_PORT)]


def sh(cmd, t=20):
    try:
        return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=t).stdout
    except Exception:
        return ""


def db():
    os.makedirs(os.path.dirname(DB), exist_ok=True)
    c = sqlite3.connect(DB, timeout=15)
    c.execute("CREATE TABLE IF NOT EXISTS samples(ts INT, ip TEXT, rx INT, tx INT)")
    c.execute("CREATE INDEX IF NOT EXISTS i_ts ON samples(ts)")
    c.execute("CREATE TABLE IF NOT EXISTS last(ip TEXT PRIMARY KEY, rx INT, tx INT)")
    return c


def peers():
    out, res = sh(f"wg show {WG_IF} dump"), []
    for line in out.strip().splitlines()[1:]:
        f = line.split("\t")
        if len(f) < 8:
            continue
        res.append({"pub": f[0], "ip": f[3].split("/")[0], "hs": int(f[4]),
                    "rx": int(f[5]), "tx": int(f[6])})
    return res


def proxied():
    out = sh("nft list set ip xray_tproxy proxied_src")
    m = re.search(r"elements = \{([^}]*)\}", out, re.S)
    return set(re.findall(r"\d+\.\d+\.\d+\.\d+", m.group(1))) if m else set()


def names():
    n = {}
    try:
        for f in os.listdir("/etc/wireguard"):
            if f.endswith(".public"):
                try:
                    n[open("/etc/wireguard/" + f).read().strip()] = f[:-7]
                except Exception:
                    pass
    except Exception:
        pass
    try:
        n.update(json.load(open(NAMES)))
    except Exception:
        pass
    return n


def health():
    try:
        h = json.load(open(HEALTH))
    except Exception:
        h = {}
    h["watchdog"] = "active" in sh("systemctl is-active vpn-watchdog")
    return h


def domains():
    out = []
    try:
        for raw in open(DIRECT, encoding="utf-8"):
            d = raw.split("#")[0].strip().lower()
            if d:
                out.append(d)
    except Exception:
        pass
    return out


def save_domains(lst):
    keep = []
    if os.path.exists(DIRECT):
        for raw in open(DIRECT, encoding="utf-8"):
            if raw.strip().startswith("#") and not keep:
                keep.append(raw.rstrip("\n"))
            elif keep and (raw.strip().startswith("#") or not raw.strip()):
                keep.append(raw.rstrip("\n"))
            elif raw.strip() and not raw.strip().startswith("#"):
                break
    body = "\n".join(keep + [""] + sorted(set(lst))) + "\n"
    tmp = DIRECT + ".tmp"
    open(tmp, "w", encoding="utf-8").write(body)
    shutil.move(tmp, DIRECT)
    return sh(f"python3 {SPLIT}", 90)


def collect():
    while True:
        try:
            c = db()
            prev = dict((r[0], (r[1], r[2])) for r in c.execute("SELECT ip,rx,tx FROM last"))
            now = int(time.time())
            for p in peers():
                orx, otx = prev.get(p["ip"], (p["rx"], p["tx"]))
                drx = p["rx"] - orx if p["rx"] >= orx else p["rx"]
                dtx = p["tx"] - otx if p["tx"] >= otx else p["tx"]
                if drx or dtx:
                    c.execute("INSERT INTO samples VALUES(?,?,?,?)", (now, p["ip"], drx, dtx))
                c.execute("INSERT OR REPLACE INTO last VALUES(?,?,?)", (p["ip"], p["rx"], p["tx"]))
            c.execute("DELETE FROM samples WHERE ts < ?", (now - KEEP_DAYS * 86400,))
            c.commit()
            c.close()
        except Exception as e:
            print("collect error:", e, flush=True)
        time.sleep(INTERVAL)


def payload(hours=24):
    c, now = db(), int(time.time())
    since = now - hours * 3600
    bucket = 300 if hours <= 24 else 3600
    prox, nm = proxied(), names()
    per = {}
    for ip, rx, tx in c.execute(
            "SELECT ip,SUM(rx),SUM(tx) FROM samples WHERE ts>=? GROUP BY ip", (since,)):
        per[ip] = {"rx": rx or 0, "tx": tx or 0}
    series = {}
    for ts, ip, rx, tx in c.execute("SELECT ts,ip,rx,tx FROM samples WHERE ts>=?", (since,)):
        b = ts - ts % bucket
        s = series.setdefault(b, {"reality": 0, "wg": 0})
        s["reality" if ip in prox else "wg"] += (rx or 0) + (tx or 0)
    tot_all = dict((r[0], (r[1], r[2])) for r in c.execute("SELECT ip,rx,tx FROM last"))
    c.close()
    cl = []
    for p in peers():
        d = per.get(p["ip"], {"rx": 0, "tx": 0})
        t = tot_all.get(p["ip"], (0, 0))
        cl.append({"ip": p["ip"], "name": nm.get(p["pub"], p["ip"]),
                   "path": "reality" if p["ip"] in prox else "wg",
                   "hs": p["hs"], "online": bool(p["hs"] and now - p["hs"] < 300),
                   "rx": d["rx"], "tx": d["tx"], "total": t[0] + t[1]})
    cl.sort(key=lambda x: -(x["rx"] + x["tx"]))
    return {"now": now, "hours": hours, "bucket": bucket, "clients": cl, "mode": MODE,
            "health": health(), "direct": domains(), "auth": bool(admin_token()),
            "series": [{"t": t, "reality": v["reality"], "wg": v["wg"]}
                       for t, v in sorted(series.items())]}


class H(BaseHTTPRequestHandler):
    server_version = "vpn-monitor"

    def log_message(self, *a):
        pass

    def _send(self, code, body, ctype="application/json"):
        if self.command == "POST":
            print(f"api {self.path.split('?')[0]} -> {code}", flush=True)
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.startswith("/api/data"):
            h = 24
            m = re.search(r"hours=(\d+)", self.path)
            if m:
                h = max(1, min(336, int(m.group(1))))
            self._send(200, json.dumps(payload(h)).encode())
        else:
            try:
                body = open(HTML, "rb").read()
            except Exception:
                body = b"dashboard file missing"
            self._send(200, body, "text/html; charset=utf-8")

    def _auth(self):
        tok = admin_token()
        if not tok:
            return True
        if self.headers.get("X-Admin-Token", "") == tok:
            return True
        self._send(403, json.dumps({"error": "admin code required"}, ensure_ascii=False).encode())
        return False

    def do_POST(self):
        if not self._auth():
            return
        n = int(self.headers.get("Content-Length") or 0)
        try:
            req = json.loads(self.rfile.read(n) or b"{}")
        except Exception:
            return self._send(400, b'{"error":"bad json"}')

        if self.path.startswith("/api/client-path"):
            ip, path = str(req.get("ip", "")), req.get("path")
            if not IPRE.match(ip) or not ip.startswith(SUBNET + ".") or path not in ("reality", "wg"):
                return self._send(400, b'{"error":"bad request"}')
            verb = "add" if path == "reality" else "delete"
            sh(f"nft {verb} element ip xray_tproxy proxied_src {{ {ip} }}")
            persist_set()
            return self._send(200, json.dumps({"ok": True, "proxied": sorted(proxied())}).encode())

        if self.path.startswith("/api/client-new"):
            name = safe_name(str(req.get("name", "")))
            port = ALT_PORT if str(req.get("port")) == str(ALT_PORT) else WG_PORT
            route = "reality" if req.get("route") == "reality" else "wg"
            if not name:
                return self._send(400, json.dumps({"error": "name: letters, digits, spaces, hyphens (up to 40)"},
                                                  ensure_ascii=False).encode())
            return self._send(200, json.dumps(create_client(name, port, route), ensure_ascii=False).encode())

        if self.path.startswith("/api/client-config"):
            ip = str(req.get("ip", ""))
            port = ALT_PORT if str(req.get("port")) == str(ALT_PORT) else WG_PORT
            if not IPRE.match(ip):
                return self._send(400, b'{"error":"bad ip"}')
            return self._send(200, json.dumps(get_config(ip, port), ensure_ascii=False).encode())

        if self.path.startswith("/api/client-delete"):
            ip = str(req.get("ip", ""))
            if not IPRE.match(ip) or ip == GW:
                return self._send(400, b'{"error":"bad ip"}')
            return self._send(200, json.dumps(delete_client(ip), ensure_ascii=False).encode())

        if self.path.startswith("/api/direct"):
            act, dom = req.get("action"), str(req.get("domain", "")).strip().lower().lstrip(".")
            cur = domains()
            if act == "add":
                if not DOMRE.match(dom) or len(dom) > 100:
                    return self._send(400, b'{"error":"bad domain"}')
                if dom not in cur:
                    cur.append(dom)
            elif act == "del":
                cur = [d for d in cur if d != dom]
            else:
                return self._send(400, b'{"error":"bad action"}')
            out = save_domains(cur)
            return self._send(200, json.dumps({"ok": True, "direct": domains(), "log": out.strip()}).encode())

        self._send(404, b'{"error":"not found"}')



def admin_token():
    try:
        return open(TOKEN_FILE).read().strip()
    except Exception:
        return ""


def server_pubkey():
    return sh(f"wg show {WG_IF} public-key").strip()


def free_ip():
    used = {p["ip"] for p in peers()} | {GW}
    for i in range(2, 251):
        cand = f"{SUBNET}.{i}"
        if cand not in used:
            return cand
    return None


def safe_name(name):
    name = name.strip()
    return name if NAMERE.match(name) else None


def slug(name):
    out = "".join(TRANSLIT.get(ch, ch) for ch in name.lower())
    return re.sub(r"[^a-z0-9_-]+", "-", out).strip("-") or "client"


def client_config(priv, ip, port):
    return (f"[Interface]\nPrivateKey = {priv}\nAddress = {ip}/32\nDNS = {CLIENT_DNS}\n"
            f"MTU = {CLIENT_MTU}\n\n[Peer]\nPublicKey = {server_pubkey()}\n"
            f"AllowedIPs = 0.0.0.0/0\nEndpoint = {SERVER_HOST}:{port}\nPersistentKeepalive = 25\n")


def qr_png(text):
    try:
        r = subprocess.run(["qrencode", "-t", "PNG", "-m", "1", "-s", "6", "-o", "-"],
                           input=text.encode(), capture_output=True, timeout=20)
        if r.returncode == 0:
            import base64
            return base64.b64encode(r.stdout).decode()
    except Exception:
        pass
    return ""


def existing_names():
    out = {}
    try:
        nm = json.load(open(NAMES))
    except Exception:
        nm = {}
    live = {p["pub"] for p in peers()}
    for pub, n in nm.items():
        if pub in live:
            out[n.strip().lower()] = n
    for f in os.listdir(WGDIR):
        if f.endswith(".public"):
            try:
                if open(os.path.join(WGDIR, f)).read().strip() in live:
                    out.setdefault(f[:-7].strip().lower(), f[:-7])
            except Exception:
                pass
    return out


def create_client(name, port, route):
    dup = existing_names().get(name.strip().lower())
    if dup:
        return {"error": f"client “{dup}” already exists — pick another name "
                         f"(or delete the old one if this replaces a device)"}
    ip = free_ip()
    if not ip:
        return {"error": "no free addresses left"}
    sl = slug(name)
    base = os.path.join(WGDIR, sl)
    if os.path.exists(base + ".conf"):
        sl = f"{sl}-{ip.split('.')[-1]}"
        base = os.path.join(WGDIR, sl)
    priv = sh("wg genkey").strip()
    pub = subprocess.run(["wg", "pubkey"], input=priv.encode(), capture_output=True, timeout=10).stdout.decode().strip()
    if not priv or not pub:
        return {"error": "could not generate keys"}
    cfg = client_config(priv, ip, port)
    old = os.umask(0o077)
    try:
        open(base + ".private", "w").write(priv + "\n")
        open(base + ".public", "w").write(pub + "\n")
        open(base + ".conf", "w").write(cfg)
    finally:
        os.umask(old)
    os.chmod(base + ".conf", 0o600)
    with open(WGCONF, "a") as f:
        f.write(f"\n[Peer]\n# {name}\nPublicKey = {pub}\nAllowedIPs = {ip}/32\n")
    sh(f"wg set {WG_IF} peer {pub} allowed-ips {ip}/32")
    try:
        nm = json.load(open(NAMES))
    except Exception:
        nm = {}
    nm[pub] = name
    json.dump(nm, open(NAMES, "w"), ensure_ascii=False, indent=2)
    if route == "reality":
        sh(f"nft add element ip xray_tproxy proxied_src {{ {ip} }}")
        persist_set()
    return {"ok": True, "name": name, "ip": ip, "file": sl + ".conf",
            "config": cfg, "qr": qr_png(cfg), "port": port, "route": route}


def get_config(ip, port=None):
    for p in peers():
        if p["ip"] != ip:
            continue
        for f in os.listdir(WGDIR):
            if not f.endswith(".public"):
                continue
            try:
                if open(os.path.join(WGDIR, f)).read().strip() != p["pub"]:
                    continue
            except Exception:
                continue
            base = os.path.join(WGDIR, f[:-7])
            if not os.path.exists(base + ".private"):
                return {"error": "this client's private key is not stored on the server — "
                                 "the config was made elsewhere. You can only issue a new one."}
            priv = open(base + ".private").read().strip()
            cfg = client_config(priv, ip, port or WG_PORT)
            return {"ok": True, "ip": ip, "file": f[:-7] + ".conf", "config": cfg, "qr": qr_png(cfg)}
        return {"error": "this client's private key is not stored on the server — "
                         "the config was made elsewhere. You can only issue a new one."}
    return {"error": "no such client"}


def delete_client(ip):
    for p in peers():
        if p["ip"] == ip:
            sh(f"wg set {WG_IF} peer {p['pub']} remove")
            sh(f"nft delete element ip xray_tproxy proxied_src {{ {ip} }}")
            persist_set()
            try:
                txt = open(WGCONF).read()
                blocks = txt.split("[Peer]")
                keep = [blocks[0]] + ["[Peer]" + b for b in blocks[1:] if p["pub"] not in b]
                open(WGCONF, "w").write("".join(keep))
            except Exception as e:
                print("wgconf clean:", e, flush=True)
            gone = os.path.join(WGDIR, "removed")
            os.makedirs(gone, exist_ok=True)
            for f in list(os.listdir(WGDIR)):
                b = os.path.join(WGDIR, f)
                if f.endswith(".public") and os.path.isfile(b):
                    try:
                        if open(b).read().strip() == p["pub"]:
                            stem = f[:-7]
                            for ext in (".conf", ".private", ".public", ".png"):
                                src = os.path.join(WGDIR, stem + ext)
                                if os.path.exists(src):
                                    shutil.move(src, os.path.join(gone, stem + ext))
                    except Exception:
                        pass
            return {"ok": True, "ip": ip}
    return {"error": "no such client"}


def persist_set():
    """Mirror the live nft set into the file so it survives a reboot."""
    path = "/etc/xray/xray-tproxy.nft"
    try:
        src = open(path).read()
        i = src.index("set proxied_src {")
        j = src.index("\n    }", i)          # closing brace of the set block
        members = sorted(proxied())
        block = "set proxied_src {\n        type ipv4_addr\n        flags interval"
        if members:
            block += "\n        elements = { %s }" % ", ".join(members)
        tmp = path + ".tmp"
        open(tmp, "w").write(src[:i] + block + src[j:])
        shutil.move(tmp, path)
    except Exception as e:
        print("persist error:", e, flush=True)


def serve(addr):
    try:
        ThreadingHTTPServer(addr, H).serve_forever()
    except Exception as e:
        print("bind", addr, "failed:", e, flush=True)


if __name__ == "__main__":
    threading.Thread(target=collect, daemon=True).start()
    for a in BIND[1:]:
        threading.Thread(target=serve, args=(a,), daemon=True).start()
    serve(BIND[0])
