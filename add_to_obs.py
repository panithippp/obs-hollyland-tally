"""Add (or remove with --remove) obs_hollyland_tally.py in every OBS scene collection.
Used by install.ps1 / uninstall.ps1. OBS must be closed (it rewrites these files on exit).
Existing script settings (light mapping) are kept."""
import json, glob, os, sys, shutil, time

NAME = "obs_hollyland_tally.py"
remove = "--remove" in sys.argv
appdata = os.environ["APPDATA"]
obsdir = os.path.join(appdata, "obs-studio")
path = os.path.join(obsdir, "scripts", NAME).replace("\\", "/")
files = sorted(glob.glob(os.path.join(obsdir, "basic", "scenes", "*.json")))
stamp = time.strftime("%Y%m%d_%H%M%S")

def is_ours(x):
    return isinstance(x, dict) and os.path.basename(str(x.get("path", "")).replace("\\", "/")) == NAME

def load(f):
    with open(f, "r", encoding="utf-8-sig") as fh:
        return json.load(fh)

def save(f, d):
    shutil.copy2(f, "%s.bak_tally_%s" % (f, stamp))
    tmp = f + ".tmp_tally"
    with open(tmp, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(d, fh, ensure_ascii=False, indent=4)
    os.replace(tmp, f)

if not files:
    print("No OBS scene collection found in %s" % os.path.join(obsdir, "basic", "scenes"))
    sys.exit(2)

bad = 0
for f in files:
    n = os.path.basename(f)
    try:
        d = load(f)
        if not isinstance(d, dict):
            raise ValueError("not a scene collection")
    except Exception as e:
        print("  skip %s (cannot read: %s)" % (n, e)); bad += 1; continue
    mods = d.get("modules")
    if not isinstance(mods, dict):
        mods = d["modules"] = {}
    lst = mods.get("scripts-tool")
    if not isinstance(lst, list):
        lst = mods["scripts-tool"] = []
    ours = [x for x in lst if is_ours(x)]
    if remove:
        if ours:
            mods["scripts-tool"] = [x for x in lst if not is_ours(x)]
            save(f, d); print("  removed from %s" % n)
        else:
            print("  not in %s" % n)
        continue
    if not ours:
        lst.append({"path": path, "settings": {}})
        save(f, d); print("  added to %s" % n)
    else:
        keep = ours[0]
        changed = keep.get("path") != path or len(ours) > 1 or not isinstance(keep.get("settings"), dict)
        if changed:
            keep["path"] = path
            if not isinstance(keep.get("settings"), dict):
                keep["settings"] = {}
            mods["scripts-tool"] = [x for x in lst if not is_ours(x) or x is keep]
            save(f, d); print("  updated in %s (settings kept)" % n)
        else:
            print("  already in %s (settings kept)" % n)

# verify
ok = 0
for f in files:
    try:
        has = any(is_ours(x) for x in load(f).get("modules", {}).get("scripts-tool", []))
        ok += (not has) if remove else has
    except Exception:
        pass
total = len(files) - bad
if remove:
    print("Script removed from OBS: %s (%d of %d scene collection(s))" % ("OK" if ok >= total else "FAILED", ok, total))
else:
    print("Script added to OBS: %s (%d of %d scene collection(s))" % ("OK" if ok and ok >= total else "FAILED", ok, total))
sys.exit(0 if (ok >= total if remove else (ok and ok >= total)) else 1)
