import json, glob, os, sys, shutil
appdata = os.environ["APPDATA"]
path = os.path.join(appdata, "obs-studio", "scripts", "obs_hollyland_tally.py").replace("\\", "/")
for f in glob.glob(os.path.join(appdata, "obs-studio", "basic", "scenes", "*.json")):
    try:
        with open(f, "r", encoding="utf-8") as fh: d = json.load(fh)
    except Exception as e:
        print("skip", f, e); continue
    mods = d.setdefault("modules", {})
    lst = mods.setdefault("scripts-tool", [])
    if not any(os.path.basename(x.get("path", "")) == "obs_hollyland_tally.py" for x in lst):
        shutil.copy2(f, f + ".bak_tally")
        lst.append({"path": path, "settings": {}})
        with open(f, "w", encoding="utf-8") as fh: json.dump(d, fh, ensure_ascii=False, indent=4)
        print("added to", os.path.basename(f))
    else:
        print("already in", os.path.basename(f))

# verify
ok = 0
for f in glob.glob(os.path.join(appdata, "obs-studio", "basic", "scenes", "*.json")):
    try:
        with open(f, "r", encoding="utf-8") as fh: d = json.load(fh)
        if any(os.path.basename(x.get("path", "")) == "obs_hollyland_tally.py" for x in d.get("modules", {}).get("scripts-tool", [])):
            ok += 1
    except Exception:
        pass
print("Script added to OBS: %s (%d scene collection(s))" % ("OK" if ok else "FAILED", ok))
sys.exit(0 if ok else 1)
