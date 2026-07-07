# cm-singbox.py — Sing-box manager for Windows

import os, sys, json, base64, hashlib, re, time, subprocess, urllib.request, urllib.error

# ═══════════════════════════════════════════════════════════
# EDIT YOUR SUBSCRIPTIONS HERE
# ═══════════════════════════════════════════════════════════
SUBS = [
    # {"name": "mysub", "url": "https://example.com/sub"},
]


# ═══════════════════════════════════════════════════════════
UP = os.environ.get("USERPROFILE", os.path.expanduser("~"))
CONFIG_DIR = os.path.join(UP, ".config", "cm-singbox")
CACHE_DIR  = os.path.join(CONFIG_DIR, "cache")
SB_CONFIG  = os.path.join(UP, ".config", "sing-box", "config.json")
SB_DIR     = os.path.dirname(SB_CONFIG)
LAN_FILE   = os.path.join(CONFIG_DIR, "lan")
API_BASE   = "http://127.0.0.1:9090"
SELECTOR   = "Proxy"


os.makedirs(CONFIG_DIR, exist_ok=True)
os.makedirs(CACHE_DIR, exist_ok=True)
if not os.path.exists(LAN_FILE):
    with open(LAN_FILE, "w") as f: f.write("state=0\nport=1080\n")


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
    try: raw = urllib.request.urlopen(url, timeout=10).read().decode()
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
    if not SUBS: e("No subscriptions configured (edit script header)"); return
    c = 0
    for sub in SUBS:
        idx = sub_idx(sub["name"])
        nodes = fetch_sub(idx, sub["name"], sub["url"])
        if nodes and apply_sub(idx, sub["name"]): c += 1
    if c > 0: sb_restart()
    e(f"Refetched {c} subscriptions")


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
        curr = current_node()
        cnt = node_count()
        lan_str = "ON" if lan_on() else "OFF"
        print(f"\n── Sing-box ──")
        print(f"  1. {curr}  [{cnt}]")
        print(f"  2. Refetch all")
        print(f"  3. LAN [{lan_str}]")
        print(f"  q. Quit")
        choice = input("Select: ").strip()

        if choice == "1":
            nodes = list_nodes()
            if not nodes: e("No nodes or sing-box not running"); continue
            curr = current_node()
            print(f"\nNodes ({len(nodes)}):")
            for i, n in enumerate(nodes, 1):
                mark = " <" if n == curr else ""
                print(f"  {i}. {n}{mark}")
            print("  b. Back")
            sel = input("Select: ").strip()
            if sel == "b": continue
            try:
                i = int(sel) - 1
                if 0 <= i < len(nodes): switch_node(nodes[i])
            except ValueError: pass

        elif choice == "2":
            refetch_all()

        elif choice == "3":
            lan_toggle()

        elif choice in ("q", "quit", "exit"):
            break

        elif choice == "":
            continue

if __name__ == "__main__":
    main()
