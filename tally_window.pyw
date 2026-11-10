# Status window for the Hollyland tally OBS script (no terminal). Started automatically by obs_hollyland_tally.py.
# - Resizable: drag the frame, the colour bars and all text scale with the window.
# - Text size: A- / A+ buttons, keys + / - (Ctrl/Cmd too), 0 = 100 %, or OBS > Tools > Scripts > "Status window text size".
# - Closing it with X keeps it closed until "Open status window" is pressed in the script settings
#   (or the script is reloaded / OBS restarts). Size, position and text size are remembered.
import json, os, re, subprocess, sys, socket, threading, time, tempfile

STATUS = os.path.join(tempfile.gettempdir(), "obs_hollyland_tally_status.json")
CLOSED = os.path.join(tempfile.gettempdir(), "obs_hollyland_tally_closed.json")   # written when the user closes the window
PREFS = os.path.join(os.path.expanduser("~"), ".hollyland_tally_window.json")      # size / position / text size
OUI_FILE = os.path.join(os.path.expanduser("~"), ".hollyland_tally_oui.txt")
COL = {"1": ("#d32f2f", "#ffffff", "RED   PROGRAM"), "2": ("#2e9d46", "#ffffff", "GREEN PREVIEW"), "0": ("#2b2b2b", "#777777", "OFF")}
NOWIN = 0x08000000 if os.name == "nt" else 0
DEBUG = os.environ.get("HOLLYLAND_TALLY_DEBUG")   # tests only: dump window state to this file

# reference window size: at this size and 100 % the fonts are big=26, mid=17, small=14 (the original look)
REF_W, REF_H = 900, 720
BASE = {"big": 26, "mid": 17, "small": 14, "btn": 11}
SCALE_MIN, SCALE_MAX, SCALE_STEP = 50, 300, 10
DEFAULT_GEOM = "900x720+60+40"
MIN_W, MIN_H = 320, 220

# ---------------- pure helpers (unit tested) ----------------
def clamp_scale(v, default=100):
    try:
        v = int(round(float(v)))
    except Exception:
        return default
    return max(SCALE_MIN, min(SCALE_MAX, v))

def font_sizes(w, h, scale):
    """Font point sizes for a window of w x h pixels at user text size `scale` %."""
    fit = min(w / float(REF_W), h / float(REF_H))
    fit = max(0.3, min(4.0, fit))
    k = fit * clamp_scale(scale) / 100.0
    return {n: max(6, int(round(b * k))) for n, b in BASE.items()}

def resolve_scale(cur, seen, obs_scale):
    """cur = scale in use, seen = last OBS setting this window applied, obs_scale = OBS setting now.
    A change of the OBS setting wins; otherwise the window's own +/- choice stays. Returns (cur, seen)."""
    if obs_scale is None:
        return cur, seen
    obs_scale = clamp_scale(obs_scale)
    if seen != obs_scale:
        return obs_scale, obs_scale
    return cur, seen

def parse_geom(g):
    """'WxH+X+Y' (Tk writes a negative X as '+-1900'). Offsets from the right/bottom ('-X') count as unknown."""
    m = re.match(r"^(\d+)x(\d+)(?:\+(-?\d+)\+(-?\d+))?", str(g or "").strip())
    if not m:
        return None
    if m.group(3) is None:
        return int(m.group(1)), int(m.group(2)), -99999, -99999
    return int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4))

def safe_geom(g, screen):
    """Restore a saved geometry, but keep it a usable size and on the screen.
    screen = (x, y, w, h) of the (virtual) desktop."""
    p = parse_geom(g)
    if not p:
        return DEFAULT_GEOM
    w, h, x, y = p
    sx, sy, sw, sh = screen
    w = max(MIN_W, min(w, max(MIN_W, sw)))
    h = max(MIN_H, min(h, max(MIN_H, sh)))
    if x + w < sx + 100 or x > sx + sw - 100 or y < sy - 10 or y > sy + sh - 80:
        x, y = sx + 60, sy + 40
    return "%dx%d+%d+%d" % (w, h, x, y)

def load_prefs(path=PREFS):
    try:
        with open(path, "r", encoding="utf-8") as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except Exception:
        return {}

def save_prefs(d, path=PREFS):
    try:
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(d, f)
        os.replace(tmp, path)
    except Exception:
        pass

def write_closed_flag(owner, path=CLOSED):
    """The user closed the window: tell the OBS script (same OBS process / script load) not to reopen it."""
    try:
        with open(path, "w", encoding="utf-8") as f:
            json.dump({"pid": owner.get("pid"), "sid": owner.get("sid"), "ts": time.time()}, f)
    except Exception:
        pass

# ---------------- device scan ----------------
def load_ouis():
    s = {"80:0e:4b"}
    try:
        for l in open(OUI_FILE).read().split():
            s.add(l.strip().lower())
    except Exception:
        pass
    return s

def save_oui(o):
    s = load_ouis()
    if o not in s:
        try: open(OUI_FILE, "a").write(o + "\n")
        except Exception: pass

def norm_mac(m):
    p = re.split(r"[-:]", m.strip().lower())
    return ":".join(x.zfill(2) for x in p) if len(p) == 6 else ""

scan = {"found": [], "ts": 0, "busy": False}   # found: [(ip, mac)]
conn_ips = set()

def do_scan(ips):
    scan["busy"] = True
    try:
        udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        for ip in ips:
            if ip.startswith("100.") or ip.startswith("169.254."): continue
            pre = ".".join(ip.split(".")[:3])
            for i in range(1, 255):
                try: udp.sendto(b"x", ("%s.%d" % (pre, i), 9))
                except Exception: pass
        time.sleep(2.0)
        kw = dict(capture_output=True, text=True, timeout=10)
        if os.name == "nt":
            kw["creationflags"] = NOWIN
        out = subprocess.run(["arp", "-a"] if os.name == "nt" else ["arp", "-an"], **kw).stdout
        found = []
        ouis = load_ouis()
        for ip, mac in re.findall(r"(\d+\.\d+\.\d+\.\d+)\)?\s+(?:at\s+)?([0-9a-fA-F]{1,2}(?:[-:][0-9a-fA-F]{1,2}){5})", out):
            m = norm_mac(mac)
            if m and (m[:8] in ouis or ip in conn_ips) and not m.startswith("ff:ff"):
                found.append((ip, m))
        scan["found"] = found
        for ip, m in found:
            if ip in conn_ips: save_oui(m[:8])
    except Exception:
        pass
    scan["ts"] = time.time(); scan["busy"] = False

def get():
    try:
        with open(STATUS, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None

def screen_box(root):
    if os.name == "nt":
        try:
            import ctypes
            gm = ctypes.windll.user32.GetSystemMetrics
            w, h = gm(78), gm(79)          # virtual desktop = all monitors
            if w > 0 and h > 0:
                return gm(76), gm(77), w, h
        except Exception:
            pass
    return 0, 0, root.winfo_screenwidth(), root.winfo_screenheight()

# ---------------- window ----------------
def main():
    import tkinter as tk
    from tkinter import font as tkfont

    family = "Segoe UI" if os.name == "nt" else ("Helvetica Neue" if sys.platform == "darwin" else "Helvetica")
    prefs = load_prefs()
    st = {"scale": clamp_scale(prefs.get("scale", 100)), "seen": prefs.get("obs_scale"),
          "applied": None, "cfg_job": None, "save_job": None, "closing": False}

    root = tk.Tk()
    root.title("Hollyland Tally Status")
    root.configure(bg="#111111")
    root.geometry(safe_geom(prefs.get("geometry", DEFAULT_GEOM), screen_box(root)))
    root.minsize(MIN_W, MIN_H)
    root.resizable(True, True)
    root.attributes("-topmost", True)

    fs = font_sizes(REF_W, REF_H, st["scale"])
    big = tkfont.Font(family=family, size=fs["big"], weight="bold")
    mid = tkfont.Font(family=family, size=fs["mid"])
    small = tkfont.Font(family=family, size=fs["small"])
    btnf = tkfont.Font(family=family, size=fs["btn"])

    top = tk.Frame(root, bg="#111111"); top.pack(fill="x", padx=14, pady=(10, 2))
    ctl = tk.Frame(top, bg="#111111"); ctl.pack(side="right")
    head = tk.Label(top, text="", font=mid, bg="#111111", fg="#dddddd", anchor="w", justify="left")
    head.pack(side="left", fill="x", expand=True)
    bkw = dict(font=btnf, bg="#333333", fg="#eeeeee", activebackground="#555555", activeforeground="#ffffff",
               relief="flat", bd=0, padx=8, pady=2, cursor="hand2", highlightthickness=0)
    b_minus = tk.Button(ctl, text="A-", **bkw); b_minus.pack(side="left", padx=2)
    pct = tk.Label(ctl, text="", font=btnf, bg="#111111", fg="#aaaaaa", width=5); pct.pack(side="left")
    b_plus = tk.Button(ctl, text="A+", **bkw); b_plus.pack(side="left", padx=2)
    ipl = tk.Label(root, text="", font=mid, bg="#111111", fg="#8ecbff", anchor="w", justify="left")
    ipl.pack(fill="x", padx=14, pady=2)
    basel = tk.Label(root, text="", font=mid, bg="#111111", fg="#dddddd", anchor="w", justify="left")
    basel.pack(fill="x", padx=14, pady=2)
    guide = tk.Label(root, text="", font=small, bg="#3a2a00", fg="#ffd27a", anchor="w", justify="left", padx=10, pady=6)
    box = tk.Frame(root, bg="#111111"); box.pack(fill="both", expand=True, padx=14, pady=6)
    note = tk.Label(root, text="", font=small, bg="#111111", fg="#9e9e9e", anchor="w", justify="left")
    note.pack(fill="x", padx=14, pady=(0, 10))
    rows = []
    quit_at = [None]
    owner = {"pid": None, "sid": None}   # the OBS process / script load that started this window

    def save_now():
        st["save_job"] = None
        try:
            geom = root.wm_geometry() if root.state() == "normal" else prefs.get("geometry", DEFAULT_GEOM)
        except Exception:
            geom = prefs.get("geometry", DEFAULT_GEOM)
        prefs.update({"geometry": geom, "scale": st["scale"], "obs_scale": st["seen"]})
        save_prefs(prefs)

    def save_later():
        if st["save_job"]: root.after_cancel(st["save_job"])
        st["save_job"] = root.after(1000, save_now)

    def apply_fonts(force=False):
        st["cfg_job"] = None
        w, h = max(root.winfo_width(), 1), max(root.winfo_height(), 1)
        if w < 50 or h < 50:          # not mapped yet
            w, h = REF_W, REF_H
        key = (w, h, st["scale"])
        if key == st["applied"] and not force:
            return
        st["applied"] = key
        f = font_sizes(w, h, st["scale"])
        for fo, n in ((big, "big"), (mid, "mid"), (small, "small"), (btnf, "btn")):
            if fo.cget("size") != f[n]: fo.configure(size=f[n])
        wrap = max(100, w - 40)
        for l in (ipl, basel, note):
            l.configure(wraplength=wrap)
        guide.configure(wraplength=max(100, w - 60))
        head.configure(wraplength=max(100, w - 40 - ctl.winfo_reqwidth()))
        for l in rows:
            l.configure(wraplength=max(100, w - 70), padx=max(4, f["big"] // 2), pady=max(1, f["big"] // 6))
        pct.configure(text="%d%%" % st["scale"])

    def on_configure(e):
        if e.widget is not root:
            return
        if st["cfg_job"]: root.after_cancel(st["cfg_job"])
        st["cfg_job"] = root.after(120, apply_fonts)   # debounce: fonts change once the drag pauses
        save_later()

    def set_scale(v):
        v = clamp_scale(v, st["scale"])
        if v != st["scale"]:
            st["scale"] = v; apply_fonts(); save_later()

    def bump(d):
        set_scale(st["scale"] + d * SCALE_STEP)
        return "break"

    b_minus.configure(command=lambda: bump(-1))
    b_plus.configure(command=lambda: bump(+1))
    for seq in ("<plus>", "<equal>", "<KP_Add>", "<Control-plus>", "<Control-equal>", "<Command-plus>", "<Command-equal>"):
        try: root.bind(seq, lambda e: bump(+1))
        except Exception: pass
    for seq in ("<minus>", "<KP_Subtract>", "<Control-minus>", "<Command-minus>"):
        try: root.bind(seq, lambda e: bump(-1))
        except Exception: pass
    for seq in ("<Key-0>", "<Control-Key-0>", "<Command-Key-0>"):
        try: root.bind(seq, lambda e: set_scale(100))
        except Exception: pass
    root.bind("<Configure>", on_configure)

    def finish(user=False):
        if st["closing"]: return
        st["closing"] = True
        if user:
            write_closed_flag(owner)
        try: save_now()
        except Exception: pass
        root.destroy()

    root.protocol("WM_DELETE_WINDOW", lambda: finish(user=True))

    def tick():
        if st["closing"]: return
        d = get(); now = time.time()
        if d is None or now - d.get("ts", 0) > 8 or d.get("quit"):
            if quit_at[0] is None: quit_at[0] = now
            head.config(text="OBS / tally script is not running (closing...)", fg="#ff8a80")
            if now - quit_at[0] > 6: finish(); return
            root.after(1000, tick); return
        quit_at[0] = None
        if d.get("pid"):
            if owner["pid"] is None: owner["pid"] = d["pid"]
            elif d["pid"] != owner["pid"]: finish(); return   # OBS was restarted: its new window takes over
        if d.get("sid"):
            if owner["sid"] is None: owner["sid"] = d["sid"]
            elif d["sid"] != owner["sid"]: finish(); return   # script reloaded: its new window takes over
        sc, st["seen"] = resolve_scale(st["scale"], st["seen"], d.get("scale"))
        if sc != st["scale"]:
            st["scale"] = sc; apply_fonts(); save_later()
        conn = d.get("connected")
        pres = d.get("presence", "")
        conn_ips.clear(); conn_ips.update(re.findall(r"\d+\.\d+\.\d+\.\d+", pres))
        ips = d.get("ips", []); port = d.get("port", 8099)
        if not scan["busy"] and now - scan["ts"] > 20 and ips:
            threading.Thread(target=do_scan, args=(ips,), daemon=True).start()
        head.config(text="%s    OBS: RUNNING" % time.strftime("%H:%M:%S"), fg="#dddddd")
        found = scan["found"]
        def pri(i):
            if i.startswith("100."): return 3
            if i.startswith("192.168."): return 0
            return 1
        pick = sorted(ips, key=pri)
        main_ip = pick[0] if pick else "?"
        for fip, _m in (list(found) + [(c, "") for c in conn_ips]):
            for i in ips:
                if i.split(".")[:3] == fip.split(".")[:3]:
                    main_ip = i
        base_ip = (found[0][0] if found else "")
        ipl.config(text="OBS IP (this computer):  %s    (port %s)" % (main_ip, port))
        if conn:
            basel.config(text="Tally device: CONNECTED  (%s)" % (", ".join(sorted(conn_ips)) or "?"), fg="#7CFC8A")
            guide.pack_forget()
        elif found:
            basel.config(text="Tally device found at %s, but it is NOT connected to receive commands" % base_ip, fg="#ffb74d")
            guide.config(text="Please set Switcher IP on the tally device to receive commands from OBS:\n"
                              "Switcher IP = %s   (OBS IP)     Port = %s\n"
                              "Do not use %s - that is the tally device's own IP." % (main_ip, port, base_ip))
            guide.pack(fill="x", padx=14, pady=6, before=box)
        else:
            basel.config(text="Tally device: NOT FOUND%s" % ("  (scanning...)" if scan["busy"] else ""), fg="#ff8a80")
            guide.config(text="1) Turn on the tally device and connect it to the same network as this computer.\n"
                              "2) Set Switcher IP on the tally device to %s (OBS IP), Port = %s\n"
                              "3) This window turns green when the device connects." % (main_ip, port))
            guide.pack(fill="x", padx=14, pady=6, before=box)
        lights = d.get("lights", [])
        if len(rows) != len(lights):
            while len(rows) < len(lights):
                l = tk.Label(box, font=big, anchor="w", padx=16, pady=4)
                l.pack(fill="both", expand=True, pady=3)      # bars share the free height
                rows.append(l)
            while len(rows) > len(lights):
                rows.pop().destroy()
            apply_fonts(force=True)
        for l, it in zip(rows, lights):
            bg, fg, txt = COL.get(it["s"], COL["0"])
            t = "%d   %-13s  %s" % (it["ch"], txt, it["name"])
            if l.cget("text") != t or l.cget("bg") != bg:
                l.config(text=t, bg=bg, fg=fg)
        if DEBUG:
            try:
                with open(DEBUG, "w") as f:
                    json.dump({"t": time.time(), "geom": root.wm_geometry(), "scale": st["scale"],
                               "fonts": {"big": big.cget("size"), "mid": mid.cget("size"), "small": small.cget("size")},
                               "rows": [l.cget("bg") for l in rows], "row_h": [l.winfo_height() for l in rows]}, f)
            except Exception:
                pass
        if not lights:
            note.config(text="No light is mapped yet: open OBS > Tools > Scripts > obs_hollyland_tally.py and pick a scene for each light.")
        elif d.get("auto"):
            note.config(text="AUTO: lights follow the first scenes in OBS order (on a new OBS, missing scenes \"Camera 2\", \"Camera 3\"... are created).\n"
                             "To choose yourself: OBS > Tools > Scripts > obs_hollyland_tally.py")
        else:
            note.config(text="")
        root.after(100, tick)

    apply_fonts(force=True)
    tick()
    root.mainloop()

if __name__ == "__main__":
    main()
