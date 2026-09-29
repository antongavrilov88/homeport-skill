#!/usr/bin/env python3
"""Creates and maintains machines in DigitalOcean through the API.

The token is read from the DO_TOKEN environment variable.

    python3 provision-do.py check
    python3 provision-do.py keys
    python3 provision-do.py price [--size s-1vcpu-1gb]
    python3 provision-do.py new-key --name vpn-kit --out ~/.ssh/vpn-kit
    python3 provision-do.py create --name vpn-exit --user-data setup-exit.sh --tag vpn-exit \
                                   --ssh-key 12345678 [--region fra1] [--size s-1vcpu-1gb]
    python3 provision-do.py list --tag vpn-exit
    python3 provision-do.py dns --domain example.com --ip 1.2.3.4 --names @ www push
    python3 provision-do.py wait-ssh --ip 1.2.3.4
    python3 provision-do.py dns-check --domain example.com --ip 1.2.3.4 --names @ www push
    python3 provision-do.py ns-check --domain example.com
    python3 provision-do.py destroy --id 123456789 --tag vpn-exit

Careful: destroy needs both the id and the tag, and deletes the machine only if
it really carries that tag. This protects someone else's droplet from being torn down.
"""
import argparse, json, os, shutil, socket, subprocess, sys, time
import urllib.error, urllib.parse, urllib.request

API = "https://api.digitalocean.com/v2"


def token():
    t = os.environ.get("DO_TOKEN", "").strip()
    if not t:
        sys.exit("no DO_TOKEN in the environment")
    return t


def call(method, path, body=None, quiet=False):
    req = urllib.request.Request(API + path, method=method,
                                 data=json.dumps(body).encode() if body is not None else None)
    req.add_header("Authorization", "Bearer " + token())
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:400]
        if quiet:
            return {"_error": e.code, "_detail": detail}
        sys.exit(f"DigitalOcean returned {e.code}: {detail}")
    except urllib.error.URLError as e:
        sys.exit(f"could not reach api.digitalocean.com: {e.reason}. "
                 "If the network is closed, the same steps can be done by hand: see references/provisioning.md")


def cmd_keys(a):
    for k in call("GET", "/account/keys?per_page=200").get("ssh_keys", []):
        print(f'{k["id"]}\t{k["name"]}\t{k["fingerprint"]}')


def cmd_list(a):
    q = f"?tag_name={a.tag}" if a.tag else "?per_page=200"
    for d in call("GET", "/droplets" + q).get("droplets", []):
        ip = next((n["ip_address"] for n in d["networks"]["v4"] if n["type"] == "public"), "")
        print(f'{d["id"]}\t{d["name"]}\t{d["status"]}\t{ip}\t{d["size_slug"]}\t{",".join(d.get("tags", []))}')


def cmd_price(a):
    """Print DigitalOcean's listed monthly price for a droplet size, before tax.

    The number the person hears at the cost step comes from here, not from the docs:
    hosts change prices. The API lists sizes only with a token.
    """
    if not os.environ.get("DO_TOKEN", "").strip():
        sys.exit("price needs a DigitalOcean token in DO_TOKEN: the API lists sizes only with one. "
                 "Until the person has a token, read the price off "
                 "https://www.digitalocean.com/pricing/droplets instead.")
    path = "/sizes?per_page=200"
    while path:
        page = call("GET", path)
        for s in page.get("sizes", []):
            if s.get("slug") == a.size:
                print(f'${float(s["price_monthly"]):.2f}')
                return
        nxt = page.get("links", {}).get("pages", {}).get("next", "")
        # Follow only links back to the API: the token must not go anywhere else.
        path = nxt[len(API):] if nxt.startswith(API + "/") else ""
    sys.exit(f"DigitalOcean does not list the size {a.size}")


def cmd_create(a):
    existing = call("GET", f"/droplets?tag_name={a.tag}").get("droplets", [])
    if existing and not a.force:
        print("Machines with this tag already exist; deal with them before creating a new one:")
        for d in existing:
            ip = next((n["ip_address"] for n in d["networks"]["v4"] if n["type"] == "public"), "")
            print(f'  {d["id"]}  {d["name"]}  {d["status"]}  {ip}')
        sys.exit("stopped on purpose (--force to create anyway)")
    if not a.ssh_key:
        sys.exit("--ssh-key is required: without it DigitalOcean enables password login and refuses key login")
    user_data = open(a.user_data, encoding="utf-8").read() if a.user_data else None
    if user_data and len(user_data.encode()) > 63 * 1024:
        sys.exit("user-data is over 63 KB; DigitalOcean will not accept it. Install the script over SSH by hand.")
    body = {"name": a.name, "region": a.region, "size": a.size, "image": a.image,
            "ssh_keys": [int(k) if k.isdigit() else k for k in a.ssh_key],
            "tags": [a.tag], "monitoring": True, "backups": False, "ipv6": True}
    if user_data:
        body["user_data"] = user_data
    d = call("POST", "/droplets", body)["droplet"]
    print(f'created id={d["id"]}, waiting for the address', file=sys.stderr)
    for _ in range(60):
        time.sleep(10)
        cur = call("GET", f'/droplets/{d["id"]}')["droplet"]
        ip = next((n["ip_address"] for n in cur["networks"]["v4"] if n["type"] == "public"), "")
        if cur["status"] == "active" and ip:
            print(json.dumps({"id": cur["id"], "ip": ip, "name": cur["name"]}))
            return
    sys.exit("the machine did not come up within 10 minutes")


def cmd_dns(a):
    have = call("GET", f"/domains/{a.domain}", quiet=True)
    if have.get("_error") == 404:
        call("POST", "/domains", {"name": a.domain, "ip_address": a.ip})
        print(f"domain {a.domain} added to DigitalOcean DNS", file=sys.stderr)
    recs = call("GET", f"/domains/{a.domain}/records?per_page=200").get("domain_records", [])
    for name in a.names:
        cur = [r for r in recs if r["type"] == "A" and r["name"] == name]
        if cur:
            for r in cur[1:]:
                call("DELETE", f'/domains/{a.domain}/records/{r["id"]}')
            call("PUT", f'/domains/{a.domain}/records/{cur[0]["id"]}', {"data": a.ip, "ttl": 300})
            print(f"updated A {name} -> {a.ip}")
        else:
            call("POST", f"/domains/{a.domain}/records",
                 {"type": "A", "name": name, "data": a.ip, "ttl": 300})
            print(f"created A {name} -> {a.ip}")




def cmd_check(a):
    """Does the token work? Is there money? Ask once, before creating anything."""
    acc = call("GET", "/account").get("account", {})
    print(f'account: {acc.get("email","?")}  status: {acc.get("status","?")}')
    if acc.get("status") != "active":
        print("WARNING: account not active, most likely no payment method attached")
    lim = acc.get("droplet_limit")
    if lim is not None:
        print(f"machine limit: {lim}")
    bal = call("GET", "/customers/my/balance", quiet=True)
    if "_error" not in bal:
        print(f'balance: {bal.get("account_balance","?")}  due this month: {bal.get("month_to_date_usage","?")}')
    n = len(call("GET", "/droplets?per_page=200").get("droplets", []))
    print(f"machines on the account now: {n}")


def cmd_new_key(a):
    """Generate an SSH key and upload the public part to DigitalOcean.

    Exists so the person never has to handle keys by hand: the private part
    stays on their disk, the public part goes to the account.
    """
    path = os.path.expanduser(a.out)
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    if not os.path.exists(path):
        r = subprocess.run(["ssh-keygen", "-t", "ed25519", "-N", "", "-C", a.name, "-f", path],
                           capture_output=True, text=True)
        if r.returncode != 0:
            sys.exit("could not create the key: " + (r.stderr or r.stdout)[:300])
        os.chmod(path, 0o600)
    pub = open(path + ".pub", encoding="utf-8").read().strip()
    have = call("GET", "/account/keys?per_page=200").get("ssh_keys", [])
    for k in have:
        if k["public_key"].split()[1] == pub.split()[1]:
            print(json.dumps({"id": k["id"], "path": path, "reused": True}))
            return
    k = call("POST", "/account/keys", {"name": a.name, "public_key": pub})["ssh_key"]
    print(json.dumps({"id": k["id"], "path": path, "reused": False}))


DOH = ["https://cloudflare-dns.com/dns-query", "https://dns.google/resolve"]


def _resolve(name, rtype="A"):
    """Ask DNS. First the local resolver, then over HTTPS.

    Returns (list of values, error text). An empty list with no error means
    the record really does not exist.
    """
    for tool, args in (("dig", ["+short", "+time=3", "+tries=2", rtype, name]),
                       ("nslookup", ["-type=" + rtype, name])):
        if not shutil.which(tool):
            continue
        try:
            r = subprocess.run([tool] + args, capture_output=True, text=True, timeout=20)
        except Exception:
            continue
        if r.returncode != 0:
            continue
        out = []
        for line in r.stdout.splitlines():
            line = line.strip()
            if tool == "dig":
                if line and not line.startswith(";"):
                    out.append(line.rstrip("."))
            elif "Address:" in line and "#" not in line:
                out.append(line.split("Address:")[1].strip())
            elif "nameserver =" in line:
                out.append(line.split("nameserver =")[1].strip().rstrip("."))
        return out, None

    last = ""
    for base in DOH:
        url = f"{base}?name={urllib.parse.quote(name)}&type={rtype}"
        req = urllib.request.Request(url, headers={"Accept": "application/dns-json"})
        try:
            with urllib.request.urlopen(req, timeout=15) as r:
                data = json.loads(r.read())
        except Exception as e:
            last = str(e)
            continue
        return [x.get("data", "").rstrip(".") for x in data.get("Answer", [])
                if x.get("type") in (1, 2)], None
    return None, last or "no access to DNS"


def cmd_dns_check(a):
    """Have the A records propagated. Check it yourself instead of asking the person."""
    bad = []
    for name in a.names:
        fqdn = a.domain if name in ("@", "") else f"{name}.{a.domain}"
        got, err = _resolve(fqdn, "A")
        if err:
            print(f"{fqdn}: could not ask DNS ({err}).")
            print("     To check by hand: open https://dnschecker.org and enter the name there.")
            bad.append(fqdn)
        elif not got:
            print(f"{fqdn}: no record yet")
            bad.append(fqdn)
        elif a.ip and a.ip not in got:
            print(f"{fqdn}: {', '.join(got)} — but {a.ip} is needed")
            bad.append(fqdn)
        else:
            print(f"{fqdn}: {', '.join(got)} — correct")
    sys.exit(1 if bad else 0)


def cmd_ns_check(a):
    """Where the domain is delegated: to DigitalOcean or to the registrar."""
    got, err = _resolve(a.domain, "NS")
    if err:
        print(f"could not ask DNS: {err}")
        print("To look by hand: https://dnschecker.org, record type NS.")
        sys.exit(3)
    if not got:
        print(f"{a.domain} has no NS servers set: the domain is not delegated anywhere yet")
        sys.exit(1)
    do = [g for g in got if "digitalocean" in g.lower()]
    print("NS: " + ", ".join(sorted(got)))
    if do:
        print("delegated to DigitalOcean: A records can be set from here")
        sys.exit(0)
    print("NOT delegated to DigitalOcean: A records have to be set at the registrar")
    sys.exit(2)


def cmd_wait_ssh(a):
    deadline = time.time() + a.timeout
    while time.time() < deadline:
        try:
            with socket.create_connection((a.ip, 22), timeout=5):
                print("ssh answers")
                return
        except OSError:
            time.sleep(5)
    sys.exit(f"{a.ip}:22 did not answer within {a.timeout} s")


def cmd_destroy(a):
    d = call("GET", f"/droplets/{a.id}")["droplet"]
    if a.tag not in d.get("tags", []):
        sys.exit(f'machine {a.id} ({d["name"]}) does not carry the tag {a.tag}; not deleting')
    call("DELETE", f"/droplets/{a.id}")
    print(f'deleted {a.id} ({d["name"]})')


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("check").set_defaults(fn=cmd_check)
    sub.add_parser("keys").set_defaults(fn=cmd_keys)

    pr = sub.add_parser("price", help="listed monthly price of a droplet size, before tax")
    pr.set_defaults(fn=cmd_price)
    pr.add_argument("--size", default="s-1vcpu-1gb")

    nk = sub.add_parser("new-key"); nk.set_defaults(fn=cmd_new_key)
    nk.add_argument("--name", default="vpn-kit")
    nk.add_argument("--out", default="~/.ssh/vpn-kit")

    c = sub.add_parser("create"); c.set_defaults(fn=cmd_create)
    c.add_argument("--name", required=True)
    c.add_argument("--tag", required=True)
    c.add_argument("--ssh-key", nargs="+", required=True)
    c.add_argument("--user-data")
    c.add_argument("--region", default="fra1")
    c.add_argument("--size", default="s-1vcpu-1gb")
    c.add_argument("--image", default="ubuntu-24-04-x64")
    c.add_argument("--force", action="store_true")

    l = sub.add_parser("list"); l.set_defaults(fn=cmd_list); l.add_argument("--tag", default="")

    d = sub.add_parser("dns"); d.set_defaults(fn=cmd_dns)
    d.add_argument("--domain", required=True); d.add_argument("--ip", required=True)
    d.add_argument("--names", nargs="+", default=["@", "www", "push"])

    w = sub.add_parser("wait-ssh"); w.set_defaults(fn=cmd_wait_ssh)
    w.add_argument("--ip", required=True); w.add_argument("--timeout", type=int, default=300)

    dc = sub.add_parser("dns-check"); dc.set_defaults(fn=cmd_dns_check)
    dc.add_argument("--domain", required=True); dc.add_argument("--ip", default="")
    dc.add_argument("--names", nargs="+", default=["@", "www", "push"])

    nc = sub.add_parser("ns-check"); nc.set_defaults(fn=cmd_ns_check)
    nc.add_argument("--domain", required=True)

    x = sub.add_parser("destroy"); x.set_defaults(fn=cmd_destroy)
    x.add_argument("--id", required=True); x.add_argument("--tag", required=True)

    a = ap.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
