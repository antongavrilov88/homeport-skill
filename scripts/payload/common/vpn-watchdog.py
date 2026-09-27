#!/usr/bin/env python3
"""Watchdog for the REALITY tunnel.

Order of operations, deliberately: get users working first, repair second.

  healthy            probe every 30 s
  first failure      switch to fast probes every 5 s to confirm quickly
  3 fast failures    FAIL OVER to WireGuard immediately (~45-60 s from breakage),
                     then restart Xray and keep trying to repair
  5 clean probes     switch back, unless the tunnel has been flapping
  every 10 min       check the fallback path itself and shout if it is dead

Alerts go to ntfy (own server first, public as backup) and Telegram if configured,
over whichever network path is still alive.
"""
import json, os, shutil, subprocess, time

CONFIG = "/etc/vpn-monitor/config.json"
try:
    _C = json.load(open(CONFIG))
except Exception:
    _C = {}
MODE = _C.get("mode", "relay")          # "relay": two paths, can fail over. "single": one machine.
GW = _C.get("wg_subnet", "10.67.0") + ".1"

STATE = "/var/lib/vpn-monitor/health.json"
SAVED = "/var/lib/vpn-monitor/failover-set.json"
ALERTS = "/etc/vpn-monitor/alerts.json"
SOCKS = "socks5h://127.0.0.1:1080"
PROBE_URLS = ["https://www.gstatic.com/generate_204", "https://cloudflare.com/cdn-cgi/trace"]
PROBE_TIMEOUT = 5

PERIOD_OK = 30          # seconds between probes while healthy
PERIOD_FAST = 5         # while confirming a suspected failure
PERIOD_DOWN = 20        # while failed over and waiting for recovery
FAIL_TO_FAILOVER = 3    # consecutive fast failures before switching users over
OK_TO_RESTORE = 5       # consecutive successes before switching back
FLAP_WINDOW = 3600      # anti-flap: failovers counted within this window
FLAP_LIMIT = 3          # after this many, demand a longer proof of stability
FALLBACK_EVERY = 600    # how often to verify the backup path
REPAIR_EVERY = 15       # restart Xray every N probes while down


def sh(cmd, t=30):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=t)
        return r.returncode, r.stdout.strip()
    except Exception:
        return 1, ""


def curl(extra, data=None, t=25):
    try:
        r = subprocess.run(["curl", "-s", "-m", "15"] + extra,
                           input=(data.encode("utf-8") if data else None),
                           capture_output=True, timeout=t)
        return r.returncode, r.stdout.decode("utf-8", "replace")
    except Exception:
        return 1, ""


PATHS = [["-x", SOCKS], [], ["--interface", GW]]


def probe_tunnel():
    for u in PROBE_URLS:
        rc, out = sh(f'curl -s -m {PROBE_TIMEOUT} -x {SOCKS} -o /dev/null -w "%{{http_code}}" {u}',
                     PROBE_TIMEOUT + 5)
        if rc == 0 and out in ("200", "204"):
            return True
    return False


def probe_fallback():
    """The WireGuard path we fail over to — is it actually alive?"""
    rc, out = sh('curl -s -m 8 --interface %s -o /dev/null -w "%%{http_code}" '
                 'https://www.gstatic.com/generate_204' % GW, 15)
    return rc == 0 and out in ("200", "204")


def nft_members():
    rc, out = sh("nft -j list set ip xray_tproxy proxied_src")
    if rc != 0:
        return []
    try:
        for item in json.loads(out).get("nftables", []):
            s = item.get("set")
            if s and s.get("name") == "proxied_src":
                res = []
                for e in s.get("elem", []):
                    if isinstance(e, str):
                        res.append(e)
                    elif isinstance(e, dict) and "prefix" in e:
                        p = e["prefix"]
                        res.append(f'{p["addr"]}/{p["len"]}')
                return res
    except Exception:
        pass
    return []


def nft_set(members):
    sh("nft flush set ip xray_tproxy proxied_src")
    if members:
        sh("nft add element ip xray_tproxy proxied_src { %s }" % ", ".join(members))


def persist_set(members=None):
    """Mirror the set into the file so it survives a reboot.

    During a failover the file deliberately keeps the pre-outage members:
    otherwise a reboot at that moment would wipe them for good and the clients
    would never return to the tunnel.
    """
    path = "/etc/xray/xray-tproxy.nft"
    try:
        src = open(path).read()
        i = src.index("set proxied_src {")
        j = src.index("\n    }", i)
        members = sorted(members if members is not None else nft_members())
        block = "set proxied_src {\n        type ipv4_addr\n        flags interval"
        if members:
            block += "\n        elements = { %s }" % ", ".join(members)
        tmp = path + ".tmp"
        open(tmp, "w").write(src[:i] + block + src[j:])
        shutil.move(tmp, path)
    except Exception as e:
        print("persist error:", e, flush=True)


def notify(title, text, prio="default"):
    try:
        cfg = json.load(open(ALERTS))
    except Exception:
        return False
    sent = False
    targets = cfg.get("ntfy_targets")
    if not targets:
        nt = cfg.get("ntfy") or {}
        targets = [nt] if nt.get("topic") else []
    for t in targets:
        if not t.get("topic"):
            continue
        server = t.get("server", "https://ntfy.sh").rstrip("/")
        payload = json.dumps({"topic": t["topic"], "title": title, "message": text,
                              "priority": {"urgent": 5, "high": 4, "default": 3}.get(prio, 3),
                              "tags": ["satellite"]}, ensure_ascii=False)
        auth = ["-H", "Authorization: Bearer " + t["token"]] if t.get("token") else []
        if t.get("user"):
            auth = ["-u", f'{t["user"]}:{t.get("password", "")}']
        for pre in PATHS:
            rc, out = curl(pre + auth + ["-H", "Content-Type: application/json",
                                         "--data-binary", "@-", server + "/"], payload)
            if rc == 0 and '"id"' in out:
                sent = True
                break
    tg = cfg.get("telegram") or {}
    if tg.get("token") and tg.get("chat_id"):
        payload = json.dumps({"chat_id": tg["chat_id"], "text": f"{title}\n\n{text}"},
                             ensure_ascii=False)
        url = f"https://api.telegram.org/bot{tg['token']}/sendMessage"
        for pre in PATHS:
            rc, out = curl(pre + ["-H", "Content-Type: application/json",
                                  "--data-binary", "@-", url], payload)
            if rc == 0 and '"ok":true' in out:
                sent = True
                break
    return sent


def write_state(**kw):
    st = {}
    if os.path.exists(STATE):
        try:
            st = json.load(open(STATE))
        except Exception:
            st = {}
    st.update(kw)
    st["checked_at"] = int(time.time())
    tmp = STATE + ".tmp"
    json.dump(st, open(tmp, "w"))
    shutil.move(tmp, STATE)


def main_single():
    """One machine: nothing to fail over to. Probe, restart Xray, shout."""
    fails = 0
    warned = False
    while True:
        alive = probe_tunnel()
        if alive:
            if warned:
                warned = False
                notify("VPN: server responding again", "The probe through Xray passes, all good.")
            fails = 0
            write_state(tunnel="ok", failover=False, fallback_ok=True, single=True)
            time.sleep(PERIOD_OK)
            continue
        fails += 1
        write_state(tunnel="degraded" if fails < FAIL_TO_FAILOVER else "down",
                    fails=fails, failover=False, single=True)
        if fails == FAIL_TO_FAILOVER:
            sh("systemctl restart xray", 60)
            write_state(last_repair=int(time.time()))
        if fails == FAIL_TO_FAILOVER and not warned:
            warned = True
            notify("VPN: server not responding",
                   "The probe through Xray has failed for about a minute. Restarted Xray, still watching. "
                   "If it does not come back, the IP is most likely blocked and a new server is needed.", "urgent")
        if fails > FAIL_TO_FAILOVER and fails % (3600 // PERIOD_DOWN) == 0:
            notify("VPN: server still not responding",
                   "About an hour has passed. Automatic restarts are not helping.", "high")
        if fails % REPAIR_EVERY == 0:
            sh("systemctl restart xray", 60)
            write_state(last_repair=int(time.time()))
        time.sleep(PERIOD_FAST if fails < FAIL_TO_FAILOVER else PERIOD_DOWN)


def resume_after_reboot():
    """After a reboot during a failover, bring the clients back if the tunnel is alive."""
    try:
        saved = json.load(open(SAVED))
    except Exception:
        return
    if not saved or nft_members():
        return
    if probe_tunnel():
        nft_set(saved)
        persist_set()
        write_state(tunnel="ok", failover=False, restored_at=int(time.time()))
        notify("VPN: clients moved back to the tunnel",
               "After a reboot the set was empty while the tunnel works — "
               "restored it from the saved list (%s)." % ", ".join(saved))


def main():
    resume_after_reboot()
    status = "ok"                 # ok | confirming | failover
    fails = oks = 0
    down_probes = 0
    flaps = []                    # timestamps of recent failovers
    last_fallback_check = 0
    fallback_ok = True
    fallback_warned = False

    while True:
        now = int(time.time())

        # --- the backup path deserves its own heartbeat: a dead spare is the silent killer
        if now - last_fallback_check > FALLBACK_EVERY:
            last_fallback_check = now
            fallback_ok = probe_fallback()
            write_state(fallback_ok=fallback_ok, fallback_checked_at=now)
            if not fallback_ok and not fallback_warned:
                fallback_warned = True
                notify("VPN: fallback route not responding",
                       "The tunnel works right now, but the WireGuard fallback is dead — if the "
                       "tunnel fails, there is nowhere to switch to. Needs a manual look.", "high")
            elif fallback_ok and fallback_warned:
                fallback_warned = False
                notify("VPN: fallback route alive again",
                       "The WireGuard fallback responds, automatic failover is possible again.")

        alive = probe_tunnel()

        if status == "ok":
            if alive:
                fails = 0
                write_state(tunnel="ok", fails=0, failover=False)
                time.sleep(PERIOD_OK)
            else:
                status = "confirming"
                fails = 1
                write_state(tunnel="degraded", fails=fails)
                time.sleep(PERIOD_FAST)

        elif status == "confirming":
            if alive:
                status = "ok"
                fails = 0
                write_state(tunnel="ok", fails=0)
                time.sleep(PERIOD_OK)
            else:
                fails += 1
                write_state(tunnel="degraded", fails=fails)
                if fails >= FAIL_TO_FAILOVER:
                    # users first: move everyone to WireGuard before touching anything else
                    members = nft_members()
                    if members:                       # never overwrite the saved list with an empty one
                        json.dump(members, open(SAVED, "w"))
                    else:
                        try:
                            members = json.load(open(SAVED))
                        except Exception:
                            members = []
                    nft_set([])
                    persist_set(members)              # the file keeps the pre-outage members
                    status = "failover"
                    down_probes = 0
                    oks = 0
                    flaps = [t for t in flaps if now - t < FLAP_WINDOW] + [now]
                    fb = probe_fallback()
                    write_state(tunnel="down", failover=True, saved=members,
                                failover_at=now, fallback_ok=fb, flaps=len(flaps))
                    notify("VPN: tunnel down, everyone moved to the fallback route",
                           "REALITY to the exit server did not respond for about a minute. Clients are "
                           "already on WireGuard%s. Now repairing the tunnel; clients go back automatically."
                           % ("" if fb else " — but it is not responding either, which is bad"),
                           "urgent" if not fb else "high")
                    # only now start repairing
                    sh("systemctl restart xray", 60)
                    write_state(last_repair=int(time.time()))
                    time.sleep(PERIOD_DOWN)
                else:
                    time.sleep(PERIOD_FAST)

        else:  # failover
            if alive:
                oks += 1
                need = OK_TO_RESTORE if len(flaps) < FLAP_LIMIT else OK_TO_RESTORE * 4
                write_state(tunnel="recovering", oks=oks, need=need, failover=True)
                if oks >= need:
                    try:
                        members = json.load(open(SAVED))
                    except Exception:
                        members = []
                    nft_set(members)
                    persist_set()
                    status = "ok"
                    fails = 0
                    write_state(tunnel="ok", failover=False, restored_at=int(time.time()))
                    notify("VPN: tunnel restored",
                           "The link to the exit server is stable, clients are back on the fast route (%s)."
                           % (", ".join(members) or "the list was empty"))
                    time.sleep(PERIOD_OK)
                    continue
                time.sleep(PERIOD_DOWN)
            else:
                oks = 0
                down_probes += 1
                write_state(tunnel="down", failover=True, down_for=down_probes * PERIOD_DOWN)
                if down_probes % REPAIR_EVERY == 0:
                    sh("systemctl restart xray", 60)
                    write_state(last_repair=int(time.time()))
                # once per outage, after ~5 minutes down, collect evidence for the post-mortem
                if down_probes == REPAIR_EVERY:
                    rc, path = sh("/usr/local/sbin/vpn-diag.sh", 120)
                    write_state(diag=path.strip())
                    notify("VPN: diagnostic snapshot saved",
                           "The tunnel has been down for over five minutes and automatic repair is not helping. "
                           "Diagnostics saved to %s for a closer look." % path.strip(),
                           "high")
                mins = down_probes * PERIOD_DOWN // 60
                if mins and mins % 60 == 0 and down_probes % (3600 // PERIOD_DOWN) == 0:
                    notify("VPN: tunnel still down",
                           "%d h so far. Clients are on WireGuard, repair attempts continue."
                           % (mins // 60), "high")
                time.sleep(PERIOD_DOWN)


if __name__ == "__main__":
    (main_single if MODE == "single" else main)()
