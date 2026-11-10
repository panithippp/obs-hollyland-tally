# Status window for the Hollyland tally OBS script (no terminal). Started automatically by obs_hollyland_tally.py.
import json, os, re, subprocess, sys, socket, threading, time, tempfile
import tkinter as tk
from tkinter import font as tkfont

STATUS = os.path.join(tempfile.gettempdir(), "obs_hollyland_tally_status.json")
OUI_FILE = os.path.join(os.path.expanduser("~"), ".hollyland_tally_oui.txt")
COL = {"1": ("#d32f2f", "#ffffff", "RED   PROGRAM"), "2": ("#2e9d46", "#ffffff", "GREEN PREVIEW"), "0": ("#2b2b2b", "#777777", "OFF")}
NOWIN = 0x08000000 if os.name == "nt" else 0

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
        out = subprocess.run(["arp", "-a"] if os.name == "nt" else ["arp", "-an"], capture_output=True, text=True,
                             timeout=10, creationflags=NOWIN).stdout
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

root = tk.Tk()
root.title("Hollyland Tally Status")
root.configure(bg="#111111")
root.geometry("900x720+60+40")
root.attributes("-topmost", True)
big = tkfont.Font(family="Segoe UI", size=26, weight="bold")
mid = tkfont.Font(family="Segoe UI", size=17)
small = tkfont.Font(family="Segoe UI", size=14)
head = tk.Label(root, text="", font=mid, bg="#111111", fg="#dddddd", anchor="w", justify="left")
head.pack(fill="x", padx=14, pady=(10, 2))
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
owner = [None]   # pid of the OBS that started this window

def get():
    try:
        with open(STATUS, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None

def tick():
    d = get(); now = time.time()
    if d is None or now - d.get("ts", 0) > 8 or d.get("quit"):
        if quit_at[0] is None: quit_at[0] = now
        head.config(text="OBS / tally script is not running (closing...)", fg="#ff8a80")
        if now - quit_at[0] > 6: root.destroy(); return
        root.after(1000, tick); return
    quit_at[0] = None
    if d.get("pid"):
        if owner[0] is None: owner[0] = d["pid"]
        elif d["pid"] != owner[0]: root.destroy(); return   # OBS was restarted: its new window takes over
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
    while len(rows) < len(lights):
        l = tk.Label(box, font=big, anchor="w", padx=16, pady=4); l.pack(fill="x", pady=3); rows.append(l)
    while len(rows) > len(lights):
        rows.pop().destroy()
    for l, it in zip(rows, lights):
        bg, fg, txt = COL.get(it["s"], COL["0"])
        l.config(text="%d   %-13s  %s" % (it["ch"], txt, it["name"]), bg=bg, fg=fg)
    if not lights:
        note.config(text="No light is mapped yet: open OBS > Tools > Scripts > obs_hollyland_tally.py and pick a scene for each light.")
    elif d.get("auto"):
        note.config(text="AUTO: lights follow the first scenes in OBS order (on a new OBS, missing scenes \"Camera 2\", \"Camera 3\"... are created).\n"
                         "To choose yourself: OBS > Tools > Scripts > obs_hollyland_tally.py")
    else:
        note.config(text="")
    root.after(100, tick)

tick()
root.mainloop()
