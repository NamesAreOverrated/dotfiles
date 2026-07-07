# cm-singbox.py — Sing-box manager for Windows

import os, sys, json, base64, hashlib, re, time, subprocess, urllib.request, urllib.error
import ctypes

# ═══════════════════════════════════════════════════════════
UP = os.environ.get("USERPROFILE", os.path.expanduser("~"))
CONFIG_DIR = os.path.join(UP, ".config", "cm-singbox")
CACHE_DIR  = os.path.join(CONFIG_DIR, "cache")
SB_CONFIG  = os.path.join(UP, ".config", "sing-box", "config.json")
SB_DIR     = os.path.dirname(SB_CONFIG)
LAN_FILE   = os.path.join(CONFIG_DIR, "lan")
SUBS_FILE  = os.path.join(CONFIG_DIR, "subs.json")
API_BASE   = "http://127.0.0.1:9090"
SELECTOR   = "Proxy"


os.makedirs(CONFIG_DIR, exist_ok=True)
os.makedirs(CACHE_DIR, exist_ok=True)
if not os.path.exists(LAN_FILE):
    with open(LAN_FILE, "w") as f: f.write("state=0\nport=1080\n")

def is_admin():
    try:
        return ctypes.windll.shell32.IsUserAnAdmin()
    except:
        return False

if not is_admin():
    print("Warning: not running as Administrator — TUN / auto_route may not work.")


# ═══════════════════════════════════════════════════════════
# Helpers
def e(*a): print(*a)

def b64d(s):
    s = s.replace("-", "+").replace("_", "/")
    s += "=" * ((4 - len(s) % 4) % 4)
    try: return base64.b64decode(s).decode()
    except: return None

def api_get(path):
    try:
        with urllib.request.urlopen(API_BASE + path, timeout=2) as r:
            return json.loads(r.read())
    except: return None

def api_put(path, body):
    try:
        data = json.dumps(body).encode()
        req = urllib.request.Request(API_BASE + path, data=data, method="PUT")
        req.add_header("Content-Type", "application/json")
        urllib.request.urlopen(req, timeout=2)
    except: pass

def sub_idx(name):
    return hashlib.md5(name.encode()).hexdigest()[:8]

def load_subs():
    try:
        with open(SUBS_FILE) as f: return json.load(f)
    except: return []

def save_subs(subs):
    with open(SUBS_FILE, "w") as f: json.dump(subs, f, indent=2)


# ═══════════════════════════════════════════════════════════
# Process management
FLAGS = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0

def sb_pid():
    r = subprocess.run(["tasklist", "/fi", "imagename eq sing-box.exe"], capture_output=True, text=True)
    for line in r.stdout.splitlines():
        if "sing-box.exe" in line:
            parts = line.split()
            if len(parts) > 1 and parts[1].isdigit():
                return int(parts[1])
    return None

def sb_start():
    if sb_pid(): e("Already running"); return
    singbox = os.environ.get("SING_BOX") or "sing-box.exe"
    try:
        p = subprocess.Popen([singbox, "run", "-c", SB_CONFIG, "-D", SB_DIR],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             creationflags=FLAGS)
    except FileNotFoundError:
        e(f"sing-box.exe not found (set SING_BOX env or add to PATH)"); return
    for _ in range(30):
        time.sleep(0.2)
        if sb_pid(): e("Started"); return
    e("Failed to start")

def sb_stop():
    if not sb_pid(): e("Not running"); return
    subprocess.run(["taskkill", "/f", "/im", "sing-box.exe"], capture_output=True)
    for _ in range(30):
        time.sleep(0.2)
        if not sb_pid(): e("Stopped"); return
    e("Failed to stop")

def sb_restart():
    sb_stop(); time.sleep(0.5); sb_start()


# ═══════════════════════════════════════════════════════════
# Parsers
def parse_vmess(raw, tag):
    s = raw.replace("vmess://", "", 1)
    if re.match(r"^[A-Za-z0-9+/=]+$", s):
        d = b64d(s)
        if not d: return None
        try: j = json.loads(d)
        except: return None
    else:
        try: j = json.loads(s)
        except: return None
    ps = j.get("ps") or f"vmess-{j.get('add', '')}"
    addr = j.get("add") or j.get("server")
    if not addr: return None
    port = int(j.get("port") or 443)
    uuid = j.get("id", "")
    aid = int(j.get("aid", 0))
    name = ps.split("@")[0]
    tag_out = f"{name}-{tag}@{addr}:{port}"
    return {"type": "vmess", "tag": tag_out, "server": addr, "server_port": port, "uuid": uuid, "alter_id": aid}

def parse_ss(raw, tag):
    s = raw.replace("ss://", "", 1)
    parts = s.split("#", 1)
    b64_info = parts[0]
    fragment = parts[1] if len(parts) > 1 else ""
    d = b64d(b64_info)
    if not d: return None
    info_parts = d.split("@", 1)
    if len(info_parts) < 2: return None
    auth, addr = info_parts
    auth_parts = auth.split(":", 1)
    if len(auth_parts) < 2: return None
    method, password = auth_parts
    addr_parts = addr.split(":", 1)
    if len(addr_parts) < 2: return None
    host = addr_parts[0]
    port_str = addr_parts[1]
    if not host or not port_str: return None
    port = int(port_str)
    name_num = fragment.split("@")[0]
    if not host or not port or not name_num: return None
    return {"type": "shadowsocks", "tag": fragment, "server": host, "server_port": port, "method": method, "password": password}

def parse_trojan(raw, tag):
    s = raw.replace("trojan://", "", 1)
    parts = s.split("@", 1)
    if len(parts) < 2: return None
    info, rest = parts
    password = info.split("#")[0]
    rest_parts = rest.split("#", 1)
    host_port = rest_parts[0]
    name_num = rest_parts[1] if len(rest_parts) > 1 else ""
    hp = host_port.split(":", 1)
    if len(hp) < 2: return None
    host = hp[0]; port_str = hp[1]
    if not host or not port_str: return None
    port = int(port_str)
    return {"type": "trojan", "tag": f"{name_num}@{host}:{port}", "server": host, "server_port": port, "password": password}

def parse_hy2(raw, tag):
    s = raw.replace("hysteria2://", "", 1)
    parts = s.split("@", 1)
    if len(parts) < 2: return None
    info, rest = parts
    password = info.split("#")[0]
    rest_parts = rest.split("#", 1)
    host_port = rest_parts[0]
    name_num = rest_parts[1] if len(rest_parts) > 1 else ""
    hp = host_port.split(":", 1)
    if len(hp) < 2: return None
    host = hp[0]; port_str = hp[1]
    if not host or not port_str: return None
    port = int(port_str)
    return {"type": "hysteria2", "tag": f"{name_num}@{host}:{port}", "server": host, "server_port": port, "password": password}


# ═══════════════════════════════════════════════════════════
# Subscription & Config
def fetch_sub(idx, name, url):
    req = urllib.request.Request(url, headers={
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                      "AppleWebKit/537.36 (KHTML, like Gecko) "
                      "Chrome/120.0.0.0 Safari/537.36"
    })
    try: raw = urllib.request.urlopen(req, timeout=10).read().decode()
    except: e(f"Failed to fetch {name}"); return None

    raw_file = os.path.join(CACHE_DIR, f"{idx}.raw")
    with open(raw_file, "w") as f: f.write(raw)

    if not re.search(r"^(vmess|ss|trojan|hysteria2)://", raw, re.MULTILINE):
        decoded = b64d(raw)
        if decoded:
            with open(raw_file, "w") as f: f.write(decoded)

    nodes = []
    with open(raw_file) as f:
        for line in f:
            line = line.strip()
            if not line: continue
            parsed = None
            if line.startswith("vmess://"):      parsed = parse_vmess(line, idx)
            elif line.startswith("ss://"):       parsed = parse_ss(line, idx)
            elif line.startswith("trojan://"):   parsed = parse_trojan(line, idx)
            elif line.startswith("hysteria2://"): parsed = parse_hy2(line, idx)
            if parsed: nodes.append(parsed)

    if not nodes: os.remove(raw_file); return None

    with open(os.path.join(CACHE_DIR, f"{idx}.nodes"), "w") as f:
        json.dump(nodes, f, indent=2)
    e(f"OK: {len(nodes)} nodes from {name}")
    return nodes

def build_outbounds(nodes):
    tags = [n["tag"] for n in nodes]
    selector = {"type": "selector", "tag": SELECTOR, "outbounds": tags}
    direct = {"type": "direct", "tag": "direct"}
    block  = {"type": "block",  "tag": "block"}
    return [selector] + nodes + [direct, block]

def apply_outbounds(obs):
    if not os.path.exists(SB_CONFIG): e(f"Config not found: {SB_CONFIG}"); return False
    with open(SB_CONFIG) as f: cfg = json.load(f)
    cfg["outbounds"] = obs
    with open(SB_CONFIG, "w") as f: json.dump(cfg, f, indent=2)
    return True

def apply_sub(idx, name):
    node_file = os.path.join(CACHE_DIR, f"{idx}.nodes")
    if not os.path.exists(node_file): e(f"No cached nodes for {name}"); return False
    with open(node_file) as f: nodes = json.load(f)
    obs = build_outbounds(nodes)
    if not apply_outbounds(obs): return False
    e(f"Applied {len(nodes)} nodes from {name}")
    return True

def refetch_all():
    subs = load_subs()
    if not subs: e("No subscriptions"); return
    c = 0
    for sub in subs:
        idx = sub_idx(sub["name"])
        nodes = fetch_sub(idx, sub["name"], sub["url"])
        if nodes and apply_sub(idx, sub["name"]): c += 1
    if c > 0: sb_restart()
    e(f"Refetched {c} subscriptions")

def sub_submenu(idx, name, url):
    while True:
        nf = os.path.join(CACHE_DIR, f"{idx}.nodes")
        count = len(json.load(open(nf))) if os.path.exists(nf) else 0
        print(f"\n── {name}  ({count} nodes) ──")
        print("  1. 󰓦  Fetch & apply nodes")
        print("  2. 󰏫  Edit URL")
        print("  3. 󰅖  Forget")
        print("  b. Back")
        sel = input("Select: ").strip()
        if sel == "b": return
        if sel == "1":
            nodes = fetch_sub(idx, name, url)
            if nodes and apply_sub(idx, name):
                if sb_pid() and is_admin(): sb_restart()
        elif sel == "2":
            new_url = input("URL: ").strip()
            if not new_url: continue
            subs = load_subs()
            for s in subs:
                if s["name"] == name: s["url"] = new_url; break
            save_subs(subs)
            url = new_url
            e("URL updated")
        elif sel == "3":
            if input(f"Forget {name}? (y/N): ").strip().lower() != "y": continue
            subs = load_subs()
            subs = [s for s in subs if s["name"] != name]
            save_subs(subs)
            for ext in ("raw", "nodes"):
                p = os.path.join(CACHE_DIR, f"{idx}.{ext}")
                if os.path.exists(p): os.remove(p)
            e(f"Forgot {name}")

def subs_submenu():
    while True:
        subs = load_subs()
        items = []
        items.append(("import", "󰐚  Import"))
        for s in subs:
            nf = os.path.join(CACHE_DIR, f"{sub_idx(s['name'])}.nodes")
            count = len(json.load(open(nf))) if os.path.exists(nf) else 0
            items.append((f"sub:{s['name']}", f"{s['name']}  ({count} nodes)"))
        print("\n── Subscriptions ──")
        for i, (act, label) in enumerate(items, 1):
            print(f"  {i}. {label}")
        print("  b. Back")
        sel = input("Select: ").strip()
        if sel == "b": return
        if not sel.isdigit(): continue
        i = int(sel) - 1
        if i < 0 or i >= len(items): continue
        act = items[i][0]
        if act == "import":
            name = input("Name: ").strip()
            if not name: continue
            url = input("URL: ").strip()
            if not url: continue
            subs = load_subs()
            subs.append({"name": name, "url": url})
            save_subs(subs)
            e(f"Imported {name}")
        elif act.startswith("sub:"):
            n = act[4:]
            for s in subs:
                if s["name"] == n:
                    sub_submenu(sub_idx(n), n, s["url"])
                    break


# ═══════════════════════════════════════════════════════════
# Node management
def current_node():
    d = api_get(f"/proxies/{SELECTOR}")
    return d.get("now", "Stopped") if d else "Stopped"

def node_count():
    d = api_get(f"/proxies/{SELECTOR}")
    return len(d.get("all") or []) if d else 0

def list_nodes():
    d = api_get(f"/proxies/{SELECTOR}")
    return d.get("all", []) if d else []

def test_node(tag):
    import urllib.parse
    enc = urllib.parse.quote(tag, safe='')
    d = api_get(f"/proxies/{enc}/delay?url=http://cp.cloudflare.com&timeout=5000")
    return d.get("delay") if d else None

def switch_node(tag):
    api_put(f"/proxies/{SELECTOR}", {"name": tag})
    e(f"Switched to {tag}")

def current_node_name():
    return current_node()


# ═══════════════════════════════════════════════════════════
# LAN
def lan_config():
    state, port = 0, 1080
    if os.path.exists(LAN_FILE):
        with open(LAN_FILE) as f:
            for line in f:
                kv = line.strip().split("=", 1)
                if len(kv) == 2:
                    if kv[0] == "state": state = int(kv[1])
                    elif kv[0] == "port": port = int(kv[1])
    return {"state": state, "port": port}

def lan_on(): return lan_config()["state"] == 1

def lan_apply():
    if not os.path.exists(SB_CONFIG): return
    with open(SB_CONFIG) as f: cfg = json.load(f)
    port = lan_config()["port"]
    listen = "0.0.0.0" if lan_on() else "127.0.0.1"
    inbounds = [i for i in (cfg.get("inbounds") or []) if i.get("tag") != "mixed"]
    inbounds.append({"type": "mixed", "tag": "mixed", "listen": listen, "listen_port": port})
    cfg["inbounds"] = inbounds
    with open(SB_CONFIG, "w") as f: json.dump(cfg, f, indent=2)

def lan_toggle():
    cfg = lan_config()
    new_state = 0 if cfg["state"] else 1
    with open(LAN_FILE, "w") as f: f.write(f"state={new_state}\nport={cfg['port']}\n")
    lan_apply()
    sb_restart()

def lan_submenu():
    while True:
        lan_str = "ON" if lan_on() else "OFF"
        lan_port = lan_config()["port"]
        print()
        print(f"  1. 󰒑  LAN [{lan_str}]")
        print(f"  2. 🔧  Port [{lan_port}]")
        print("  b. Back")
        sel = input("Select: ").strip()
        if sel == "b": return
        if sel == "1": lan_toggle()
        elif sel == "2":
            try:
                new_port = int(input("Port: ").strip())
                if new_port < 1 or new_port > 65535: raise ValueError
                cfg = lan_config()
                with open(LAN_FILE, "w") as f: f.write(f"state={cfg['state']}\nport={new_port}\n")
                lan_apply()
                sb_restart()
            except: e("Invalid port")


# ═══════════════════════════════════════════════════════════
# Service install
def install_service():
    singbox = os.environ.get("SING_BOX") or "sing-box.exe"
    which = subprocess.run(["where", singbox], capture_output=True, text=True)
    if which.returncode != 0:
        e(f"{singbox} not found in PATH (set SING_BOX env)"); sys.exit(1)
    path = which.stdout.strip().splitlines()[0]
    binpath = f'"{path}" run -c "{SB_CONFIG}" -D "{SB_DIR}"'
    r = subprocess.run(["sc.exe", "create", "sing-box", "binPath=", binpath, "start=", "auto"],
                       capture_output=True, text=True)
    if r.returncode == 0: e("Service 'sing-box' created (start=auto)")
    else: e(f"Failed: {r.stderr.strip() or r.stdout.strip()}")

def run_foreground():
    singbox = os.environ.get("SING_BOX") or "sing-box.exe"
    os.execvp(singbox, [singbox, "run", "-c", SB_CONFIG, "-D", SB_DIR])


# ═══════════════════════════════════════════════════════════
# Main
def main():
    if len(sys.argv) > 1:
        if sys.argv[1] in ("-install", "--install"): install_service(); return
        if sys.argv[1] in ("--run",): run_foreground(); return

    while True:
        pid = sb_pid()
        admin = is_admin()
        curr = current_node()
        cnt = node_count()
        lan_str = "ON" if lan_on() else "OFF"

        items = []
        items.append(("nodes", f"󰒒  {curr}  [{cnt}]"))
        subs = load_subs()
        items.append(("subs", f"󰓦  Subscriptions [{len(subs)}]"))
        if not pid or admin:
            items.append(("refetch", "󰑐  Refetch all"))
        if admin:
            if pid:
                items.append(("toggle", "⏹  Stop"))
            else:
                items.append(("toggle", "󰐚  Start"))
        if admin:
            items.append(("lan", f"󰒑  LAN [{lan_str}]"))

        print(f"\n── Sing-box ──")
        for i, (act, label) in enumerate(items, 1):
            print(f"  {i}. {label}")
        print("  q. 󰿅  Quit")
        choice = input("Select: ").strip()

        if choice == "q": break
        if not choice.isdigit(): continue
        i = int(choice) - 1
        if i < 0 or i >= len(items): continue
        act = items[i][0]

        if act == "nodes":
            if not sb_pid(): e("Start sing-box first"); continue
            nodes = list_nodes()
            if not nodes: e("No nodes"); continue
            curr = current_node()
            print()
            print("  1. 󰒒  Browse")
            print("  2. 󱐌  Browse (tested)")
            print()
            print("  Nodes:")
            for i, n in enumerate(nodes, 1):
                mark = " 󰗠" if n == curr else ""
                print(f"  {i}.{mark} {n}")
            print("  b. Back")
            sel = input("Select: ").strip()
            if sel == "b": continue
            if sel == "1":
                sel2 = input("Select node: ").strip()
                if sel2.isdigit():
                    j = int(sel2) - 1
                    if 0 <= j < len(nodes): switch_node(nodes[j])
            elif sel == "2":
                results = []
                for n in nodes:
                    d = test_node(n)
                    lat = f"{d}ms" if d else ""
                    sk = d if d else 99999
                    results.append((n, lat, sk))
                results.sort(key=lambda x: x[2])
                print()
                for i, (tag, lat, _) in enumerate(results, 1):
                    mark = "󰗠" if tag == curr else " "
                    print(f"  {i}. {mark} {lat:>5}  {tag}")
                sel2 = input("Select node (or Enter): ").strip()
                if sel2.isdigit():
                    j = int(sel2) - 1
                    if 0 <= j < len(results): switch_node(results[j][0])
            elif sel.isdigit():
                j = int(sel) - 1
                if 0 <= j < len(nodes): switch_node(nodes[j])

        elif act == "refetch":
            refetch_all()

        elif act == "subs":
            subs_submenu()

        elif act == "toggle":
            if pid: sb_stop()
            else: sb_start()

        elif act == "lan":
            lan_submenu()

if __name__ == "__main__":
    main()
