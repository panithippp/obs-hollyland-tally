"""OBS -> Hollyland Wireless Tally (vMix TCP API emulation, port 8099).
Load in OBS: Tools > Scripts. Pure logic works without obspython (for tests)."""
import socket, threading, selectors, time, subprocess, re, sys, os, json, tempfile

try:
    import obspython as obs
except ImportError:
    obs = None

VMIX_VERSION = "27.0.0.49"
MAX_CH = 16

# ---------------- pure logic ----------------
def compute_tally(mapping, program, preview, scene_tree, n_inputs=16):
    """mapping: {ch:int -> 'Scene:Name'|'Source:Name'}
    scene_tree: {scene_name: [(item_source_name, visible, is_scene_or_group), ...]}
    returns string of digits len n_inputs."""
    def visible_sources(scene, seen=None):
        seen = seen or set()
        if scene is None or scene in seen:
            return set()
        seen.add(scene)
        out = set()
        for name, vis, nested in scene_tree.get(scene, []):
            if not vis:
                continue
            out.add(name)
            if nested:
                out |= visible_sources(name, seen)
        return out
    pgm_src = visible_sources(program)
    pvw_src = visible_sources(preview) if preview else set()
    digits = []
    for ch in range(1, n_inputs + 1):
        m = mapping.get(ch) or ""
        state = 0
        if m.startswith("Scene:"):
            s = m[6:]
            if s == program: state = 1
            elif preview and s == preview: state = 2
        elif m.startswith("Source:"):
            s = m[7:]
            if s in pgm_src: state = 1
            elif s in pvw_src: state = 2
        digits.append(str(state))
    return "".join(digits)

def build_xml(tally, mapping):
    from xml.sax.saxutils import escape
    active = tally.find("1") + 1 if "1" in tally else 0
    preview = tally.find("2") + 1 if "2" in tally else 0
    inputs = "".join(
        '<input key="obs-%d" number="%d" type="Capture" title="%s" state="Running">%s</input>'
        % (i, i, escape((mapping.get(i) or "Input %d" % i), {'"': "&quot;"}),
           escape(mapping.get(i) or "Input %d" % i))
        for i in range(1, len(tally) + 1))
    return ("<vmix><version>%s</version><edition>4K</edition><inputs>%s</inputs>"
            "<active>%d</active><preview>%d</preview></vmix>" % (VMIX_VERSION, inputs, active, preview))

def handle_line(line, state):
    """state: object with .tally, .mapping. Returns (reply_bytes, subscribe:bool|None, quit:bool)"""
    line = line.strip()
    if not line:
        return b"", None, False
    parts = line.split(" ", 1)
    cmd = parts[0].upper()
    arg = parts[1].strip() if len(parts) > 1 else ""
    if cmd == "TALLY":
        return ("TALLY OK %s\r\n" % state.tally).encode(), None, False
    if cmd == "VERSION":
        return ("VERSION OK %s\r\n" % VMIX_VERSION).encode(), None, False
    if cmd == "XML":
        x = build_xml(state.tally, state.mapping).encode("utf-8")
        x += b"\r\n"  # vMix: length includes trailing \r\n
        return b"XML %d\r\n" % len(x) + x, None, False
    if cmd == "SUBSCRIBE":
        if arg.upper() == "TALLY":
            return b"SUBSCRIBE OK TALLY\r\n" + ("TALLY OK %s\r\n" % state.tally).encode(), True, False
        return ("SUBSCRIBE ER %s\r\n" % (arg or "Missing")).encode(), None, False
    if cmd == "UNSUBSCRIBE":
        return ("UNSUBSCRIBE OK %s\r\n" % arg.upper()).encode(), False, False
    if cmd == "FUNCTION":
        fn = arg.split(" ", 1)[0]
        if not fn:
            return b"FUNCTION ER No function specified\r\n", None, False
        return ("FUNCTION OK %s\r\n" % fn).encode(), None, False   # accepted, ignored
    if cmd == "ACTS":
        # vMix listener clients (e.g. Hollyland) send "ACTS Overlay1"; reply "ACTS OK <name> 0"
        name = arg.split(" ", 1)[0] if arg else "Unknown"
        v = 0
        if name == "InputPreview":
            v = state.tally.find("2") + 1      # preview input number (0 = none)
        elif name == "Input":
            v = state.tally.find("1") + 1      # program input number
        return ("ACTS OK %s %d\r\n" % (name, v)).encode(), None, False
    if cmd == "XMLTEXT":
        return ("%s ER Not supported\r\n" % cmd).encode(), None, False
    if cmd == "QUIT":
        return b"", None, True
    return ("%s ER Unknown\r\n" % cmd).encode(), None, False

# ---------------- TCP server ----------------
class TallyServer:
    def __init__(self, port=8099, host="0.0.0.0"):
        self.port, self.host = port, host
        self.tally = "0" * MAX_CH
        self.mapping = {}
        self.lock = threading.Lock()
        self.clients = {}  # sock -> {"buf":b"", "sub":bool}
        self._stop = threading.Event()
        self.thread = None
        self.sel = None
        self.lsock = None
        self.real = self.tally          # real tally from OBS
        self.override = None            # tally forced by light test
        self.on_first_subscribe = None  # callback(ip) when a base subscribes and none was subscribed
        self.test = None                # running LightTest
        self.log = print

    def start(self):
        self.lsock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.lsock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.lsock.bind((self.host, self.port))
        self.lsock.listen(8)
        self.lsock.setblocking(False)
        self.sel = selectors.DefaultSelector()
        self.sel.register(self.lsock, selectors.EVENT_READ)
        self._stop.clear()
        self.thread = threading.Thread(target=self._run, daemon=True, name="hollyland-tally")
        self.thread.start()

    def _drop(self, s):
        try: self.sel.unregister(s)
        except Exception: pass
        try: s.close()
        except Exception: pass
        self.clients.pop(s, None)

    def _send(self, s, data):
        try:
            s.setblocking(True); s.settimeout(1.0)
            s.sendall(data)
            s.setblocking(False)
        except Exception:
            self._drop(s)

    def _run(self):
        while not self._stop.is_set():
            for key, _ in self.sel.select(timeout=0.2):
                s = key.fileobj
                if s is self.lsock:
                    try:
                        c, _ = self.lsock.accept()
                        c.setblocking(False)
                        c.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                        with self.lock:
                            self.clients[c] = {"buf": b"", "sub": False, "ip": _[0], "since": time.time(), "last": time.time(), "cmds": 0}
                        self.sel.register(c, selectors.EVENT_READ)
                    except Exception:
                        pass
                    continue
                try:
                    data = s.recv(4096)
                except (BlockingIOError, InterruptedError):
                    continue
                except Exception:
                    data = b""
                with self.lock:
                    if not data:
                        self._drop(s); continue
                    cl = self.clients.get(s)
                    if cl is None: continue
                    cl["buf"] += data
                    cl["last"] = time.time(); cl["cmds"] += 1
                    while b"\n" in cl["buf"]:
                        raw, cl["buf"] = cl["buf"].split(b"\n", 1)
                        reply, sub, quit_ = handle_line(raw.decode("utf-8", "ignore"), self)
                        if sub is not None:
                            was_any = any(c["sub"] for c in self.clients.values())
                            cl["sub"] = sub
                            if sub and not was_any and self.on_first_subscribe:
                                threading.Thread(target=self.on_first_subscribe, args=(cl["ip"],), daemon=True).start()
                        if reply: self._send(s, reply)
                        if quit_ or s not in self.clients:
                            self._drop(s); break

    def _push(self, tally):
        """lock held. Push effective tally to subscribers if changed."""
        if tally == self.tally: return False
        self.tally = tally
        msg = ("TALLY OK %s\r\n" % tally).encode()
        # Hollyland polls (never subscribes): push the new state at once so lights change in real time
        poll = msg + ("ACTS OK InputPreview %d\r\n" % (tally.find("2") + 1)).encode()
        for s, cl in list(self.clients.items()):
            self._send(s, msg if cl["sub"] else poll)
        return True

    def update(self, tally, mapping=None):
        """Real tally from OBS. Held (not sent) while a light test runs."""
        with self.lock:
            if mapping is not None: self.mapping = dict(mapping)
            changed = tally != self.real
            self.real = tally
            if self.override is None:
                self._push(tally)
            return changed

    def set_override(self, tally):
        with self.lock:
            self.override = tally
            self._push(tally if tally is not None else self.real)

    def start_light_test(self, channels, n_inputs, step=1.0, rounds=3, sleep=None):
        self.cancel_light_test()
        self.test = LightTest(self, channels, n_inputs, step, rounds, sleep, self.log)
        self.test.start()
        return self.test

    def cancel_light_test(self):
        t = self.test
        if t:
            t.cancel(); t.join(3)
        self.test = None

    @property
    def testing(self):
        return bool(self.test and self.test.is_alive())

    def probe(self):
        """Liveness check: re-send tally to subscribers (dead socket -> dropped).
        Returns list of dicts describing live clients."""
        with self.lock:
            msg = ("TALLY OK %s\r\n" % self.tally).encode()
            for s, cl in list(self.clients.items()):
                if cl["sub"]:
                    self._send(s, msg)
            return [dict(ip=c["ip"], since=c["since"], last=c["last"], sub=c["sub"])
                    for c in self.clients.values()]

    def stop(self):
        self.cancel_light_test()
        self._stop.set()
        if self.thread: self.thread.join(2)
        with self.lock:
            for s in list(self.clients): self._drop(s)
        try: self.sel.unregister(self.lsock)
        except Exception: pass
        try: self.lsock.close()
        except Exception: pass
        try: self.sel.close()
        except Exception: pass

class LightTest(threading.Thread):
    """For each channel in order: red step s, green step s, x rounds; others off."""
    def __init__(self, server, channels, n_inputs, step, rounds, sleep, log):
        super().__init__(daemon=True, name="tally-light-test")
        self.server, self.channels, self.n = server, list(channels), n_inputs
        self.step, self.rounds, self.log = step, rounds, log
        self.ev = threading.Event()
        self._sleep = sleep or (lambda sec: self.ev.wait(sec))
        self.steps = []   # (ch, colour) for tests
        self.cancelled = False
        self.done = False

    def cancel(self):
        self.cancelled = True; self.ev.set()

    def run(self):
        self.log("[Tally] เริ่มทดสอบไฟ (light test): %s" % ", ".join(map(str, self.channels)))
        try:
            for ch in self.channels:
                for r in range(1, self.rounds + 1):
                    for d, name in (("1", "แดง"), ("2", "เขียว")):
                        if self.cancelled: return
                        t = "".join(d if i == ch else "0" for i in range(1, self.n + 1))
                        self.server.set_override(t)
                        self.steps.append((ch, d))
                        self.log("[Tally] ทดสอบไฟเบอร์ %d รอบ %d/%d: %s" % (ch, r, self.rounds, name))
                        self._sleep(self.step)
                        if self.cancelled: return
            self.done = True
        finally:
            self.server.set_override(None)
            self.log("[Tally] %s กลับสู่ tally จริง" % ("ยกเลิกการทดสอบ —" if self.cancelled else "ทดสอบไฟเสร็จ —"))

# ---------------- helpers (pure) ----------------
COLOR_TH = {"0": "ดับ (off)", "1": "แดง (Program)", "2": "เขียว (Preview)"}

def lan_ips():
    ips = set()
    try:
        if sys.platform.startswith("win"):
            out = subprocess.run(["ipconfig"], capture_output=True, text=True, timeout=3,
                                 creationflags=0x08000000).stdout  # CREATE_NO_WINDOW
            ips |= set(re.findall(r"IPv4[^:]*:\s*(\d+\.\d+\.\d+\.\d+)", out))
        else:
            out = subprocess.run(["ifconfig"], capture_output=True, text=True, timeout=2).stdout
            ips |= set(re.findall(r"inet (\d+\.\d+\.\d+\.\d+)", out))
    except Exception:
        pass
    try:
        u = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        u.connect(("10.255.255.255", 1)); ips.add(u.getsockname()[0]); u.close()
    except Exception:
        pass
    ips.discard("127.0.0.1")
    def is_cgnat(ip):  # 100.64.0.0/10 = Tailscale/VPN, list last
        a, b = map(int, ip.split(".")[:2]); return a == 100 and 64 <= b < 128
    return sorted((i for i in ips if not i.startswith("169.254.")), key=lambda i: (is_cgnat(i), i))

def presence_text(clients, now=None, stale_after=120):
    now = now or time.time()
    if not clients:
        return False, "❌ ยังไม่พบตัวรับ Hollyland (not connected)"
    lines = []
    for c in clients:
        age = int(now - c["last"])
        note = "" if age < stale_after else " ⚠️ เงียบนาน (no traffic)"
        lines.append("✅ %s — ส่งข้อมูลล่าสุด %s (%d วิที่แล้ว)%s%s" % (
            c["ip"], time.strftime("%H:%M:%S", time.localtime(c["last"])), age,
            "" if c["sub"] else " [ยังไม่ SUBSCRIBE]", note))
    return True, "<br>".join(lines)

def channel_status_text(tally, mapping, n_lights):
    rows = []
    for ch in range(1, n_lights + 1):
        m = mapping.get(ch) or ""
        if not m:
            continue
        name = m.split(":", 1)[1]
        rows.append("%d %s = %s" % (ch, name, COLOR_TH.get(tally[ch - 1] if ch <= len(tally) else "0")))
    return "<br>".join(rows) or "(ยังไม่ได้ตั้งไฟเบอร์ไหนเลย)"

def guide_html(ips, port, mapping, n_lights):
    ipstr = ", ".join(ips) or "(หา IP ไม่เจอ — Mac: System Settings > Network / Windows: ipconfig)"
    knobs = ", ".join("ไฟดวงเบอร์ %d → %s" % (ch, mapping[ch].split(":", 1)[1])
                      for ch in range(1, n_lights + 1) if mapping.get(ch)) or "-"
    return ("<b>📖 วิธีตั้งค่าไฟ Tally Hollyland (Setup guide)</b><ol>"
            "<li>ต่อสาย LAN (Ethernet) จากตัวรับ (Base) เข้าเราเตอร์/สวิตช์วงเดียวกับคอมพิวเตอร์ที่รัน OBS</li>"
            "<li>ที่ตัวรับ ตั้งโหมด Switcher เป็น <b>vMix</b></li>"
            "<li>ตั้ง Switcher IP = <b>%s</b> (Port <b>%d</b>)</li>"
            "<li>จับคู่ (Pair) ไฟแต่ละดวงกับตัวรับ โดยเสียบสาย USB-C ระหว่างไฟกับตัวรับ</li>"
            "<li>หมุนปุ่มเลือกช่อง (Channel knob) ที่ไฟแต่ละดวงให้ตรงเบอร์: %s</li>"
            "<li>สลับ Scene ใน OBS แล้วดูไฟ — แดง = ออกอากาศ, เขียว = Preview</li></ol>"
            % (ipstr, port, knobs))

# ---------------- OBS glue ----------------
server = None
settings_cache = {"auto_test": True, "port": 8099, "n_inputs": 16, "n_lights": 4, "use_preview": True, "mapping": {}}
_state = {"last_check": 0.0, "connected": None, "presence": "", "props": None}
CHECK_EVERY = 60

def _scene_tree():
    tree = {}
    scenes = obs.obs_frontend_get_scenes() or []
    def walk(name, scene_ptr):
        if name in tree: return
        items = obs.obs_scene_enum_items(scene_ptr) or []
        lst, nested = [], []
        for it in items:
            src = obs.obs_sceneitem_get_source(it)
            n = obs.obs_source_get_name(src)
            vis = obs.obs_sceneitem_visible(it)
            is_grp = obs.obs_sceneitem_is_group(it)
            is_scene = obs.obs_source_get_type(src) == obs.OBS_SOURCE_TYPE_SCENE
            lst.append((n, vis, is_grp or is_scene))
            if is_grp:
                nested.append((n, obs.obs_sceneitem_group_get_scene(it)))
            elif is_scene:
                nested.append((n, obs.obs_scene_from_source(src)))
        obs.sceneitem_list_release(items)
        tree[name] = lst
        for n, sp in nested:
            if sp: walk(n, sp)
    for sc in scenes:
        walk(obs.obs_source_get_name(sc), obs.obs_scene_from_source(sc))
    obs.source_list_release(scenes)
    return tree

def _cur(getter):
    s = getter()
    if not s: return None
    n = obs.obs_source_get_name(s)
    obs.obs_source_release(s)
    return n


STATUS_FILE = os.path.join(tempfile.gettempdir(), "obs_hollyland_tally_status.json")
_win = {"proc": None, "last": 0}

def write_status(quit=False):
    try:
        lights = []
        t = _state.get("tally_now", "")
        for ch in range(1, settings_cache["n_lights"] + 1):
            m = settings_cache["mapping"].get(ch) or ""
            if not m: continue
            lights.append({"ch": ch, "name": m.split(":", 1)[1] if ":" in m else m,
                           "s": t[ch - 1] if ch <= len(t) else "0"})
        pres = re.sub(r"<[^>]+>", " | ", str(_state.get("presence", ""))).strip(" |")
        pres = re.sub(r"[^\x20-\x7e\u0e00-\u0e7f]", "", pres)
        if time.time() - _state.get("ips_ts", 0) > 30:
            _state["ips"] = [i for i in lan_ips()]; _state["ips_ts"] = time.time()
        d = {"ts": time.time(), "quit": quit, "connected": bool(_state.get("connected")),
             "presence": pres, "lights": lights, "ips": _state.get("ips", []),
             "port": settings_cache.get("port", 8099)}
        tmp = STATUS_FILE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f: json.dump(d, f, ensure_ascii=False)
        os.replace(tmp, STATUS_FILE)
    except Exception as e:
        print("[Tally] write_status error: %s" % e)

def open_window():
    p = _win["proc"]
    if p is not None and p.poll() is None: return
    try:
        here = os.path.dirname(os.path.abspath(__file__))
        win = os.path.join(here, "tally_window.pyw")
        if not os.path.exists(win): return
        write_status()
        if os.name == "nt":
            pyw = None
            for base in (getattr(sys, "exec_prefix", ""), getattr(sys, "base_prefix", ""), os.path.dirname(os.__file__) + "\\.."):
                c = os.path.join(base, "pythonw.exe")
                if os.path.exists(c): pyw = c; break
            if pyw is None:
                import shutil; pyw = shutil.which("pythonw")
            if pyw is None: print("[Tally] ไม่พบ pythonw.exe เปิดหน้าต่างสถานะไม่ได้"); return
            _win["proc"] = subprocess.Popen([pyw, win], creationflags=0x08000000)
        else:
            import shutil
            py = shutil.which("python3") or "/usr/bin/python3"
            _win["proc"] = subprocess.Popen([py, win])
    except Exception as e:
        print("[Tally] เปิดหน้าต่างสถานะไม่ได้: %s" % e)

def refresh():
    if server is None or obs is None: return
    prog = _cur(obs.obs_frontend_get_current_scene)
    prev = None
    if settings_cache["use_preview"] and obs.obs_frontend_preview_program_mode_active():
        prev = _cur(obs.obs_frontend_get_current_preview_scene)
    t = compute_tally(settings_cache["mapping"], prog, prev, _scene_tree(), settings_cache["n_inputs"])
    _state["tally_now"] = t if isinstance(t, str) else "".join(map(str, t))
    if server.update(t, settings_cache["mapping"]):
        write_status()
        print("[Tally] " + channel_status_text(t, settings_cache["mapping"], settings_cache["n_lights"]).replace("<br>", " | "))

def check_presence(force=False):
    if server is None:
        _state["presence"] = "❌ เซิร์ฟเวอร์ไม่ทำงาน (port ใช้งานไม่ได้)"; return
    now = time.time()
    if not force and now - _state["last_check"] < CHECK_EVERY:
        return
    _state["last_check"] = now
    ok, txt = presence_text(server.probe(), now)
    if ok != _state["connected"] or force:
        print("[Tally] ตรวจสถานะ %s: %s" % (time.strftime("%H:%M:%S"), txt.replace("<br>", " | ")))
    elif ok:
        print("[Tally] ตรวจสถานะ %s: ยังเชื่อมต่ออยู่" % time.strftime("%H:%M:%S"))
    else:
        print("[Tally] ตรวจสถานะ %s: ยังไม่พบตัวรับ" % time.strftime("%H:%M:%S"))
    _state["connected"], _state["presence"] = ok, txt

def _mapped_channels():
    return [c for c in range(1, settings_cache["n_lights"] + 1) if settings_cache["mapping"].get(c)]

def start_test(reason="manual"):
    if server is None: return None
    chans = _mapped_channels()
    if not chans:
        print("[Tally] ไม่มีไฟที่ตั้งเบอร์ไว้ ข้ามการทดสอบ"); return None
    print("[Tally] ทดสอบไฟ (%s)" % reason)
    return server.start_light_test(chans, settings_cache["n_inputs"])

def _on_base_connected(ip):
    print("[Tally] ตัวรับเชื่อมต่อจาก %s" % ip)
    if not settings_cache["auto_test"]:
        return
    if obs.obs_frontend_streaming_active() or obs.obs_frontend_recording_active():
        print("[Tally] กำลังไลฟ์/อัดอยู่ — ข้ามการทดสอบไฟอัตโนมัติ (skip auto test while live/recording)")
        return
    start_test("auto: %s" % ip)

def _on_test_btn(props, prop):
    start_test("ปุ่มทดสอบ"); _fill_dynamic(props)
    return True

def tick():
    refresh()
    check_presence()
    if time.time() - _win['last'] > 1:
        _win['last'] = time.time(); write_status()
        if settings_cache.get('show_window', True): open_window()

def _on_event(ev):
    if ev in (obs.OBS_FRONTEND_EVENT_SCENE_CHANGED, obs.OBS_FRONTEND_EVENT_PREVIEW_SCENE_CHANGED,
              obs.OBS_FRONTEND_EVENT_STUDIO_MODE_ENABLED, obs.OBS_FRONTEND_EVENT_STUDIO_MODE_DISABLED,
              obs.OBS_FRONTEND_EVENT_SCENE_LIST_CHANGED):
        refresh()

def _status_html():
    t = server.real if server else "0" * MAX_CH
    return ("<b>📡 สถานะตัวรับ (Base status)</b> — ตรวจทุก 60 วินาที<br>%s<br><br>"
            "<b>💡 สีไฟที่ควรเป็นตอนนี้ (Expected colours)</b><br>%s<br><br>"
            "<i>หมายเหตุ: OBS ตรวจเจอได้แค่ตัวรับ (Base) ไฟแต่ละดวงคุยกับตัวรับทางวิทยุ "
            "จึงตรวจจากที่นี่ไม่ได้ว่าไฟดวงไหนติดอยู่ (individual lights can't be detected)</i>"
            % (("🧪 <b>กำลังทดสอบไฟ...</b> (testing lights)<br>" if server and server.testing else "")
               + (_state["presence"] or "(กด รีเฟรชสถานะ)"),
               channel_status_text(t, settings_cache["mapping"], settings_cache["n_lights"])))

def _fill_dynamic(props):
    p = obs.obs_properties_get(props, "status")
    if p: obs.obs_property_set_long_description(p, _status_html()); obs.obs_property_set_description(p, _status_html())
    g = obs.obs_properties_get(props, "guide")
    has_map = any(settings_cache["mapping"].get(c) for c in range(1, settings_cache["n_lights"] + 1))
    if g:
        obs.obs_property_set_description(g, guide_html(lan_ips(), settings_cache["port"],
                                         settings_cache["mapping"], settings_cache["n_lights"]))
        obs.obs_property_set_visible(g, has_map)

def _on_refresh_btn(props, prop):
    refresh(); check_presence(force=True); _fill_dynamic(props)
    return True

def _on_nlights(props, prop, s):
    n = obs.obs_data_get_int(s, "n_lights")
    for ch in range(1, MAX_CH + 1):
        p = obs.obs_properties_get(props, "ch%d" % ch)
        if p: obs.obs_property_set_visible(p, ch <= n)
    return True

def script_description():
    return ("<b>🎥 Hollyland Tally สำหรับ OBS</b><br>ทำให้ OBS ทำตัวเหมือน vMix เพื่อให้ไฟ Tally Hollyland ติดตาม Scene"
            "<br>🔴 แดง = ออกอากาศ (Program) &nbsp; 🟢 เขียว = Preview (Studio Mode)")

def script_defaults(s):
    obs.obs_data_set_default_int(s, "port", 8099)
    obs.obs_data_set_default_int(s, "n_inputs", 16)
    obs.obs_data_set_default_int(s, "n_lights", 4)
    obs.obs_data_set_default_bool(s, "use_preview", True)
    obs.obs_data_set_default_bool(s, "auto_test", True)

def script_properties():
    p = obs.obs_properties_create()
    obs.obs_properties_add_text(p, "h1", "<b>① จับคู่ไฟกับกล้อง (Map lights)</b>", obs.OBS_TEXT_INFO)
    nl = obs.obs_properties_add_int_slider(p, "n_lights", "จำนวนไฟที่ใช้ (Lights)", 1, MAX_CH, 1)
    obs.obs_property_set_modified_callback(nl, _on_nlights)
    names_sc, names_src = [], []
    scenes = obs.obs_frontend_get_scenes() or []
    for sc in scenes: names_sc.append(obs.obs_source_get_name(sc))
    obs.source_list_release(scenes)
    srcs = obs.obs_enum_sources() or []
    for sr in srcs: names_src.append(obs.obs_source_get_name(sr))
    obs.source_list_release(srcs)
    for ch in range(1, MAX_CH + 1):
        l = obs.obs_properties_add_list(p, "ch%d" % ch, "ไฟเบอร์ %d (Light %d)" % (ch, ch),
                                        obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
        obs.obs_property_list_add_string(l, "— ไม่ใช้ (none) —", "")
        for n in sorted(names_sc): obs.obs_property_list_add_string(l, "Scene: " + n, "Scene:" + n)
        for n in sorted(names_src): obs.obs_property_list_add_string(l, "Source: " + n, "Source:" + n)
        obs.obs_property_set_visible(l, ch <= settings_cache["n_lights"])
    obs.obs_properties_add_bool(p, "use_preview", "ไฟเขียวตาม Preview ใน Studio Mode")
    obs.obs_properties_add_bool(p, "auto_test", "ทดสอบอัตโนมัติเมื่อเชื่อมต่อ (Auto test on connect)")
    obs.obs_properties_add_button(p, "test_btn", "🧪 ทดสอบไฟ (Test lights)", _on_test_btn)
    obs.obs_properties_add_text(p, "guide", "", obs.OBS_TEXT_INFO)
    obs.obs_properties_add_text(p, "h2", "<b>② สถานะ (Status)</b>", obs.OBS_TEXT_INFO)
    obs.obs_properties_add_text(p, "status", "", obs.OBS_TEXT_INFO)
    obs.obs_properties_add_button(p, "refresh_btn", "🔄 รีเฟรชสถานะ (Refresh)", _on_refresh_btn)
    adv = obs.obs_properties_create()
    obs.obs_properties_add_int(adv, "port", "Port (vMix = 8099)", 1, 65535, 1)
    obs.obs_properties_add_int(adv, "n_inputs", "จำนวน input ที่รายงาน (Inputs reported)", 1, MAX_CH, 1)
    obs.obs_properties_add_group(p, "adv", "ขั้นสูง (Advanced)", obs.OBS_GROUP_NORMAL, adv)
    _fill_dynamic(p)
    return p

def script_update(s):
    global server
    port = obs.obs_data_get_int(s, "port")
    settings_cache["port"] = port
    settings_cache["n_inputs"] = obs.obs_data_get_int(s, "n_inputs")
    settings_cache["n_lights"] = obs.obs_data_get_int(s, "n_lights")
    settings_cache["use_preview"] = obs.obs_data_get_bool(s, "use_preview")
    settings_cache["auto_test"] = obs.obs_data_get_bool(s, "auto_test")
    settings_cache["mapping"] = {ch: (obs.obs_data_get_string(s, "ch%d" % ch) if ch <= settings_cache["n_lights"] else "")
                                 for ch in range(1, MAX_CH + 1)}
    if server is None or server.port != port:
        if server: server.stop()
        server = TallyServer(port)
        server.on_first_subscribe = _on_base_connected
        try:
            server.start()
            print("[Tally] เปิด vMix TCP ที่ port %d, IP ของเครื่องนี้: %s" % (port, ", ".join(lan_ips())))
        except OSError as e:
            print("[Tally] เปิด port %d ไม่ได้: %s" % (port, e)); server = None
    refresh(); check_presence(force=True)

def script_load(s):
    obs.obs_frontend_add_event_callback(_on_event)
    obs.timer_add(tick, 250)

def script_unload():
    global server
    obs.timer_remove(tick)
    write_status(quit=True)
    if server: server.stop(); server = None
    print("[Tally] ปิดแล้ว (stopped)")
