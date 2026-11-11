#!/bin/bash
# Hollyland Tally for OBS - macOS installer (run via "1. Click to Install.command")
# No admin password needed. Homebrew is used only if it is already installed and you say yes.
# Works with the macOS /bin/bash (3.2). Test switches (normal users never need them):
#   --no-obs-control   never quit/start OBS
#   --obs-dir DIR      use DIR as the OBS settings folder (for tests)
#   --no-pause         do not wait for Return at the end
#   --list-python      only list the Python installs found and exit

PORT=8099
PY_PREF="3.11 3.12 3.10 3.9 3.8"          # OBS 28-33 load Python 3.6 - 3.12 (3.13+ NOT supported)
OBS_TRIES="3.12 3.11 3.10 3.9 3.8 3.7 3.6" # the order OBS itself tries inside one folder
BUNDLE_ID="com.obsproject.obs-studio"
HERE="$(cd "$(dirname "$0")" && pwd)"
# This script lives in mac/helpers/; the clickable installer is in mac/; scripts are in the repo root.
if [ "$(basename "$HERE")" = helpers ]; then APP="$(cd "$HERE/.." && pwd)"; else APP="$HERE"; fi
ROOT="$(cd "$APP/.." && pwd)"
src() {  # $1 = filename. Look in mac/, then the repo root.
  if [ -f "$APP/$1" ]; then printf '%s\n' "$APP/$1"
  elif [ -f "$ROOT/$1" ]; then printf '%s\n' "$ROOT/$1"
  fi
}
LOG="$HOME/Library/Logs/hollyland_tally_install.log"
CFG="$HOME/Library/Application Support/obs-studio"

NO_OBS=0; NO_PAUSE=0; LIST_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --no-obs-control) NO_OBS=1 ;;
    --no-pause) NO_PAUSE=1 ;;
    --list-python) LIST_ONLY=1 ;;
    --obs-dir) shift; CFG="$1" ;;
  esac
  shift
done

mkdir -p "$(dirname "$LOG")" 2>/dev/null
: > "$LOG" 2>/dev/null || LOG="${TMPDIR:-/tmp}/hollyland_tally_install.log"
exec > >(tee -a "$LOG") 2>&1

if [ -t 1 ] || [ -n "$TERM" ]; then C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_OFF=$'\033[0m'; fi
say()  { printf '%s\n' "$*"; }
good() { printf '%s%s%s\n' "$C_GREEN" "$*" "$C_OFF"; }
warn() { printf '%s%s%s\n' "$C_YELLOW" "$*" "$C_OFF"; }
step() { printf '\n%s== %s%s\n' "$C_CYAN" "$*" "$C_OFF"; }
ask()  { local a=""; printf '%s ' "$1"; { read -r a </dev/tty; } 2>/dev/null || read -r a; REPLY="$a"; }
pause_end() { [ "$NO_PAUSE" = 1 ] && return; echo; ask "When you have finished reading, press Return to close this window (or close it yourself)."; }

SUMMARY=""
sum() { SUMMARY="$SUMMARY$(printf '%-22s: %s' "$1" "$2")"$'\n'; }

OBS_APP=""; OBS_VER=""; OBS_MAJOR=0; WAS_OPEN=0; DEST=""; COPIED=0; BREW_DECLINED=0; W_PY=""; W_TK=""
PY_DIR=""; PY_VER=""; PY_BIN=""; PY_TK=0

# ---------- OBS ----------
obs_pids() { ps -axo pid=,comm= 2>/dev/null | awk '/\.app\/Contents\/MacOS\/(OBS|obs)$/ {print $1}'; }

find_obs() {
  local pid comm app d
  pid="$(obs_pids | head -n 1)"
  if [ -n "$pid" ]; then
    comm="$(ps -o comm= -p "$pid" 2>/dev/null)"
    app="${comm%%.app/Contents/MacOS/*}.app"
    [ -d "$app" ] && { echo "$app"; return 0; }
  fi
  for d in "/Applications/OBS.app" "$HOME/Applications/OBS.app" "/Applications/OBS Studio.app" \
           "$HOME/Library/Application Support/Steam/steamapps/common/OBS Studio/OBS.app" \
           "$HOME/Library/Application Support/Steam/steamapps/common/OBS Studio/arm64/OBS.app" \
           "$HOME/Library/Application Support/Steam/steamapps/common/OBS Studio/x86_64/OBS.app"; do
    [ -d "$d" ] && { echo "$d"; return 0; }
  done
  if command -v mdfind >/dev/null 2>&1; then
    d="$(mdfind "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" 2>/dev/null | grep '\.app$' | head -n 1)"
    [ -n "$d" ] && [ -d "$d" ] && { echo "$d"; return 0; }
  fi
  return 1
}

plist_get() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null; }

start_obs() { [ -n "$OBS_APP" ] && open "$OBS_APP" >/dev/null 2>&1; }

wait_obs_gone() { local i=0; while [ $i -lt "$1" ] && [ -n "$(obs_pids)" ]; do sleep 0.5; i=$((i+1)); done; [ -z "$(obs_pids)" ]; }

close_obs() {  # $1 = why. returns 0 if OBS was open (and is now closed)
  [ -n "$(obs_pids)" ] || return 1
  warn "OBS is open - closing it $1..."
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1
  if ! wait_obs_gone 40; then
    while [ -n "$(obs_pids)" ]; do
      warn "OBS is still open (maybe it is streaming/recording, or showing a question)."
      warn "Please quit OBS yourself (OBS menu > Quit OBS, or Cmd+Q; answer any OBS dialog)."
      ask "Press Return when OBS is closed."
      wait_obs_gone 10
    done
  fi
  sleep 2
  return 0
}

# ---------- Python ----------
need_arch() {  # arm64 or x86_64: what OBS runs as on this Mac
  local exe
  if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ]; then
    if [ -n "$OBS_APP" ]; then
      exe="$OBS_APP/Contents/MacOS/$(plist_get "$OBS_APP" CFBundleExecutable)"
      if [ -f "$exe" ] && ! file -b "$exe" 2>/dev/null | grep -q arm64; then echo x86_64; return; fi
    fi
    echo arm64
  else
    echo x86_64
  fi
}

tk_ok() { awk -v t="$1" 'BEGIN { exit !((t + 0) >= 8.6) }'; }

in_list() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }

# test_python DIR -> sets T_VER T_BIN T_TK; returns 1 if OBS cannot use DIR
# DIR is what OBS wants in Python Settings: the folder that holds Python.framework
test_python() {
  local dir="${1%/}" v lib=""
  T_VER=""; T_BIN=""; T_TK=0
  [ -n "$dir" ] && [ -d "$dir/Python.framework" ] || return 1
  for v in $OBS_TRIES; do
    if [ -e "$dir/Python.framework/Versions/$v/lib/libpython$v.dylib" ]; then lib="$dir/Python.framework/Versions/$v/lib/libpython$v.dylib"; T_VER="$v"; break; fi
  done
  [ -n "$T_VER" ] || return 1
  in_list "$T_VER" "$PY_PREF" || return 1
  if command -v file >/dev/null 2>&1; then
    file -bL "$lib" 2>/dev/null | grep -q "$NEED_ARCH" || return 1
  fi
  T_BIN="$dir/Python.framework/Versions/$T_VER/bin/python$T_VER"
  [ -x "$T_BIN" ] || return 1
  T_TK="$("$T_BIN" -c 'import tkinter, _tkinter; print(tkinter.TkVersion)' 2>/dev/null | tail -n 1)"
  [ -n "$T_TK" ] || T_TK=0
  return 0
}

python_candidates() {
  local v cur
  cur="$(ini_get "$CFG/user.ini" Python Path64bit)"; [ -n "$cur" ] && echo "$cur"
  cur="$(ini_get "$CFG/global.ini" Python Path64bit)"; [ -n "$cur" ] && echo "$cur"
  for v in $PY_PREF; do
    echo "/opt/homebrew/opt/python@$v/Frameworks"
    echo "/usr/local/opt/python@$v/Frameworks"
  done
  echo "/Library/Frameworks"
  echo "$HOME/Library/Frameworks"
}

select_python() {  # best: Tk 8.6+ (status window works with the same Python), then version order
  local d seen="" bestscore=999 score idx v
  PY_DIR=""; PY_VER=""; PY_BIN=""; PY_TK=0
  while IFS= read -r d; do
    d="${d%/}"; [ -n "$d" ] || continue
    case "$seen" in *"|$d|"*) continue ;; esac; seen="$seen|$d|"
    test_python "$d" || continue
    idx=0; for v in $PY_PREF; do [ "$v" = "$T_VER" ] && break; idx=$((idx+1)); done
    score=$idx; tk_ok "$T_TK" || score=$((score+10))
    if [ $score -lt $bestscore ]; then bestscore=$score; PY_DIR="$d"; PY_VER="$T_VER"; PY_BIN="$T_BIN"; PY_TK="$T_TK"; fi
  done <<< "$(python_candidates)"
  [ -n "$PY_DIR" ]
}

# Pythons the script itself checks for the status window (see _python_with_tk in obs_hollyland_tally.py)
window_python() {
  local p t
  for p in /opt/homebrew/opt/python@3.14/bin/python3.14 /opt/homebrew/bin/python3.14 \
           /opt/homebrew/opt/python@3.13/bin/python3.13 /opt/homebrew/bin/python3.13 \
           /opt/homebrew/opt/python@3.12/bin/python3.12 /opt/homebrew/opt/python@3.11/bin/python3.11 \
           /usr/local/opt/python@3.14/bin/python3.14 /usr/local/bin/python3.14 \
           /usr/local/opt/python@3.13/bin/python3.13 /usr/local/opt/python@3.12/bin/python3.12 /usr/local/opt/python@3.11/bin/python3.11 \
           /Library/Frameworks/Python.framework/Versions/3.12/bin/python3.12 /Library/Frameworks/Python.framework/Versions/3.11/bin/python3.11 \
           /opt/homebrew/bin/python3 /usr/local/bin/python3; do
    [ -x "$p" ] || continue
    t="$("$p" -c 'import tkinter, _tkinter; print(tkinter.TkVersion)' 2>/dev/null | tail -n 1)"
    if [ -n "$t" ] && tk_ok "$t"; then W_PY="$p"; W_TK="$t"; return 0; fi
  done
  return 1
}

find_brew() {
  local b
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew "$(command -v brew 2>/dev/null)"; do
    [ -n "$b" ] && [ -x "$b" ] && { echo "$b"; return 0; }
  done
  return 1
}

brew_install() {  # $@ = formulae
  say "Homebrew will install: $*"
  say "(Python for OBS and Tk 8.6+ for the status window. This can take a few minutes.)"
  ask "Press Return to install, or type n and Return to skip:"
  case "$REPLY" in [nN]*) warn "Skipped Homebrew install."; BREW_DECLINED=1; return 1 ;; esac
  "$BREW" install "$@"
}

# ---------- ini ----------
ini_get() {  # file section key  (BOM and CRLF tolerant)
  [ -f "$1" ] || return 0
  LC_ALL=C awk -v sec="$2" -v key="$3" '
    BEGIN { bom = sprintf("%c%c%c", 239, 187, 191) }
    NR == 1 && substr($0, 1, 3) == bom { $0 = substr($0, 4) }
    { sub(/\r$/, "") }
    /^[ \t]*\[.*\][ \t]*$/ { s = $0; gsub(/^[ \t]*\[|\][ \t]*$/, "", s); ins = (s == sec); next }
    ins {
      line = $0; sub(/^[ \t]+/, "", line)
      if (index(line, key) == 1) {
        rest = substr(line, length(key) + 1); sub(/^[ \t]+/, "", rest)
        if (substr(rest, 1, 1) == "=") { v = substr(rest, 2); gsub(/^[ \t]+|[ \t]+$/, "", v); print v; exit }
      }
    }' "$1"
}

ini_set() {  # python file section key value. Keeps the file's BOM / line endings; backup in FILE.bak_tally
  "$1" - "$2" "$3" "$4" "$5" <<'PYEOF'
import os, shutil, sys
ini, sec, key, val = sys.argv[1:5]
raw = b""
if os.path.exists(ini):
    with open(ini, "rb") as f:
        raw = f.read()
bom = raw.startswith(b"\xef\xbb\xbf")   # OBS on macOS writes no BOM; keep whatever the file has
text = raw.decode("utf-8-sig")
nl = "\r\n" if "\r\n" in text else "\n"
lines = text.splitlines()
while lines and lines[-1] == "":
    lines.pop()
start = next((i for i, l in enumerate(lines) if l.strip() == "[%s]" % sec), -1)
if start < 0:
    if lines:
        lines.append("")
    lines += ["[%s]" % sec, "%s=%s" % (key, val)]
else:
    end = next((i for i in range(start + 1, len(lines)) if lines[i].lstrip().startswith("[")), len(lines))
    done = False
    for i in range(start + 1, end):
        if lines[i].split("=", 1)[0].strip() == key and "=" in lines[i]:
            lines[i] = "%s=%s" % (key, val); done = True
    if not done:
        ins = end
        while ins > start + 1 and lines[ins - 1].strip() == "":
            ins -= 1
        lines.insert(ins, "%s=%s" % (key, val))
if os.path.exists(ini):
    shutil.copy2(ini, ini + ".bak_tally")
data = (nl.join(lines) + nl).encode("utf-8")
with open(ini, "wb") as f:
    f.write((b"\xef\xbb\xbf" if bom else b"") + data)
PYEOF
}

# ---------- network ----------
lan_ips() {  # prints "ip<TAB>interface<TAB>label<TAB>virtual(0/1)", best first
  local defif ifs i ip name virt rank o2
  defif="$(route -n get default 2>/dev/null | awk '/interface:/ {print $2}')"
  ifs="$(ifconfig -l 2>/dev/null)"
  for i in $ifs; do
    for ip in $(ifconfig "$i" 2>/dev/null | awk '$1 == "inet" {print $2}'); do
      case "$ip" in 127.*|169.254.*) continue ;; esac
      name="$(networksetup -listallhardwareports 2>/dev/null | awk -v dev="$i" '/^Hardware Port:/ {sub(/^Hardware Port: /, ""); p = $0} /^Device:/ && $2 == dev {print p; exit}')"
      [ -n "$name" ] || name="$i"
      virt=0
      case "$i" in utun*|ppp*|ipsec*|tun*|tap*|feth*|zt*|vmnet*|bridge*|awdl*|llw*|gif*|stf*) virt=1 ;; esac
      o2="$(echo "$ip" | cut -d. -f2)"
      case "$ip" in 100.*) [ "$o2" -ge 64 ] && [ "$o2" -lt 128 ] && virt=1 ;; esac
      rank=0; [ $virt = 1 ] && rank=$((rank+10)); [ "$i" != "$defif" ] && rank=$((rank+2))
      case "$ip" in 192.168.*) ;; *) rank=$((rank+1)) ;; esac
      printf '%d\t%s\t%s\t%s\t%d\n' "$rank" "$ip" "$i" "$name" "$virt"
    done
  done | sort -n -k1,1 | cut -f2-
}

finish() {  # $1 = exit code
  if [ "$1" != 0 ] && [ "$WAS_OPEN" = 1 ] && [ "$NO_OBS" = 0 ] && [ -z "$(obs_pids)" ]; then start_obs; fi
  if [ "$COPIED" = 1 ] && [ -n "$DEST" ]; then open "$DEST" >/dev/null 2>&1; fi
  pause_end
  exit "$1"
}

fail() {
  echo
  printf '%sINSTALL FAILED: %s%s\n' "$C_RED" "$*" "$C_OFF"
  say "Log: $LOG"
  finish 1
}

# ================= main =================
say "${C_CYAN}Hollyland Tally for OBS - macOS installer${C_OFF}"
say "Folder: $APP"
say "Scripts: $ROOT"
say "Log:    $LOG"
echo
say "This installer does everything automatically. You do not need to paste files by hand."
say "It will:"
say "  1. Find OBS and the OBS scripts folder"
say "  2. Copy obs_hollyland_tally.py and tally_window.pyw into that folder"
say "  3. Set the Python path in OBS if it finds Python 3.11 or 3.12"
say "  4. Add the script to every scene collection"
say "  5. Open the scripts folder in Finder so you can see the files"
say "  6. Show a summary and this Mac's IP for the Hollyland tally base"
say "At the end this window stays open so you can read the summary, then close it yourself."
for f in obs_hollyland_tally.py tally_window.pyw add_to_obs.py; do
  [ -n "$(src "$f")" ] || fail "Missing file '$f'. Extract the whole ZIP first (double-click it), then open the mac folder and double-click '1. Click to Install.command'."
done
chmod +x "$APP/"*.command "$HERE/"*.sh 2>/dev/null   # in case the ZIP lost the execute bit
[ "$(uname -s)" = Darwin ] || warn "This installer is for macOS (this system is $(uname -s))."

OBS_APP="$(find_obs)"
NEED_ARCH="$(need_arch)"

if [ "$LIST_ONLY" = 1 ]; then
  say "OBS: ${OBS_APP:-not found}   needs $NEED_ARCH Python"
  python_candidates | while IFS= read -r d; do
    if test_python "$d"; then say "usable  $T_VER  Tk=$T_TK  $d"; elif [ -d "$d/Python.framework" ]; then say "skipped $d (version OBS cannot load, wrong CPU type, or missing files)"; fi
  done
  if select_python; then say "selected: $PY_VER $PY_DIR"; else say "selected: none"; fi
  if window_python; then say "status window Python: $W_PY (Tk $W_TK)"; else say "status window Python: none with Tk 8.6+"; fi
  exit 0
fi

step "1/6 OBS Studio"
if [ -n "$OBS_APP" ]; then
  OBS_VER="$(plist_get "$OBS_APP" CFBundleShortVersionString)"
  OBS_MAJOR="${OBS_VER%%.*}"; case "$OBS_MAJOR" in ''|*[!0-9]*) OBS_MAJOR=0 ;; esac
  good "OBS: $OBS_APP (version ${OBS_VER:-unknown})"
  sum "OBS" "$OBS_APP (${OBS_VER:-unknown})"
else
  warn "OBS Studio was not found in /Applications or ~/Applications."
  warn "Install it from https://obsproject.com (drag OBS into Applications), open it once, then run this installer again."
  warn "The installer still copies the script files for you."
  sum "OBS" "NOT FOUND"
fi

step "2/6 Python (OBS needs Python 3.6 - 3.12, 3.11 recommended; 3.13+ does not work in OBS)"
BREW="$(find_brew)"
if ! select_python || ! tk_ok "$PY_TK"; then
  if [ -n "$PY_DIR" ]; then warn "Found Python $PY_VER at $PY_DIR, but its tkinter is missing or older than Tk 8.6."
  else warn "No Python that OBS can load was found (needs $NEED_ARCH Python 3.8 - 3.12)."; fi
  if [ -n "$BREW" ]; then
    if [ -z "$PY_DIR" ]; then
      brew_install python@3.11 python-tk@3.11 || true
    else
      case "$PY_DIR" in */opt/python@*) brew_install "python-tk@$PY_VER" || true ;; esac
    fi
    select_python
  fi
fi
if [ -n "$PY_DIR" ]; then
  good "Python $PY_VER: $PY_DIR (Tk $PY_TK)"
  sum "Python for OBS" "$PY_VER $PY_DIR"
else
  warn "Python could not be set up automatically. To fix it, do ONE of these, then run this installer again:"
  warn "  a) Install Python 3.11 from python.org: https://www.python.org/downloads/release/python-3119/"
  warn "     (macOS 64-bit universal2 installer; it includes Tk 8.6 for the status window), or"
  if [ -n "$BREW" ]; then warn "  b) In Terminal: brew install python@3.11 python-tk@3.11"
  else warn "  b) Install Homebrew (https://brew.sh), then in Terminal: brew install python@3.11 python-tk@3.11"; fi
  sum "Python for OBS" "NOT FOUND - see the steps above"
  if [ -z "$BREW" ]; then
    ask "Open the python.org download page now? (y/n)"
    case "$REPLY" in [yY]*) open "https://www.python.org/downloads/release/python-3119/" >/dev/null 2>&1 ;; esac
  fi
fi

step "3/6 OBS settings folder"
if [ "$NO_OBS" = 0 ] && close_obs "so the installer can change its settings"; then WAS_OPEN=1; fi
have_scenes() { ls "$CFG/basic/scenes/"*.json >/dev/null 2>&1; }
need_setup=0
have_scenes || need_setup=1
[ "$OBS_MAJOR" -ge 31 ] && [ ! -f "$CFG/user.ini" ] && need_setup=1
if [ $need_setup = 1 ] && [ -n "$OBS_APP" ] && [ "$NO_OBS" = 0 ]; then
  warn "OBS has not been set up on this Mac yet. Starting OBS once so it creates its settings..."
  warn "(If OBS shows the Auto-Configuration Wizard or asks for permissions, you can cancel/close those.)"
  start_obs
  i=0; while [ $i -lt 120 ]; do
    sleep 0.5; i=$((i+1))
    have_scenes && { [ "$OBS_MAJOR" -lt 31 ] || [ -f "$CFG/user.ini" ]; } && break
  done
  i=0; while [ $i -lt 60 ]; do   # let OBS finish starting (quitting too early can hang its shutdown)
    lf="$(ls -t "$CFG/logs/"*.txt 2>/dev/null | head -n 1)"
    [ -n "$lf" ] && grep -q "Startup complete" "$lf" 2>/dev/null && break
    sleep 1; i=$((i+1))
  done
  sleep 5
  close_obs "again (first-run setup done)" || true
  if have_scenes; then good "OBS settings created."; else warn "OBS did not create a scene collection yet."; fi
fi
if [ -d "$CFG" ]; then
  DEST="$CFG/scripts"
  mkdir -p "$DEST" || fail "Could not create $DEST"
else
  warn "The OBS settings folder was not found: $CFG"
  warn "Please choose the folder to copy the script into (normally ~/Library/Application Support/obs-studio/scripts)."
  DEST="$(osascript -e 'POSIX path of (choose folder with prompt "Choose the folder to copy the Hollyland Tally script into (OBS scripts folder):")' 2>/dev/null)"
  DEST="${DEST%/}"
  [ -n "$DEST" ] && [ -d "$DEST" ] || fail "No folder chosen. Open OBS once (so it creates its settings), then run this installer again."
fi
active="$(ini_get "$CFG/user.ini" Basic SceneCollectionFile)"
[ -n "$active" ] || active="$(ini_get "$CFG/global.ini" Basic SceneCollectionFile)"
cols="$(ls "$CFG/basic/scenes/"*.json 2>/dev/null | sed 's#.*/##; s#\.json$##' | paste -sd, - | sed 's/,/, /g')"
ncols="$(ls "$CFG/basic/scenes/"*.json 2>/dev/null | wc -l | tr -d ' ')"
say "Scene collections: ${cols:-none}   (active: ${active:-?})"

step "4/6 Copy the script and set OBS Python path"
for f in obs_hollyland_tally.py tally_window.pyw; do
  s="$(src "$f")"
  cp -f "$s" "$DEST/$f" || fail "Could not copy $f to $DEST"
  cmp -s "$s" "$DEST/$f" || fail "Copy check failed for $DEST/$f"
  xattr -d com.apple.quarantine "$DEST/$f" >/dev/null 2>&1
done
COPIED=1
good "Copied obs_hollyland_tally.py and tally_window.pyw to $DEST"
sum "Script files" "$DEST"
if [ -n "$PY_DIR" ] && [ "$DEST" = "$CFG/scripts" ]; then
  targets=""
  { [ "$OBS_MAJOR" -ge 31 ] || [ -f "$CFG/user.ini" ]; } && targets="user.ini"            # OBS 31+: user.ini
  { [ "$OBS_MAJOR" -lt 31 ] || [ -f "$CFG/global.ini" ]; } && targets="$targets global.ini"  # older OBS: global.ini
  for t in $targets; do
    ini_set "$PY_BIN" "$CFG/$t" Python Path64bit "$PY_DIR" || fail "Could not write the Python path to $CFG/$t"
    [ "$(ini_get "$CFG/$t" Python Path64bit)" = "$PY_DIR" ] || fail "Could not write the Python path to $CFG/$t"
    good "Set [Python] Path64bit=$PY_DIR in $t"
  done
  tl="${targets# }"; sum "OBS Python path" "$PY_DIR (${tl// /, })"
else
  warn "OBS Python path not set. In OBS: Tools > Scripts > Python Settings > choose the folder that holds Python.framework"
  warn "(python.org: /Library/Frameworks, Homebrew: /opt/homebrew/opt/python@3.11/Frameworks)."
  sum "OBS Python path" "NOT SET"
fi

step "5/6 Add the script to OBS (Tools > Scripts)"
added=0
if [ -n "$PY_BIN" ] && [ "$DEST" = "$CFG/scripts" ] && [ "${ncols:-0}" -gt 0 ]; then
  "$PY_BIN" "$(src add_to_obs.py)" --obsdir "$CFG" && added=1
fi
if [ $added = 1 ]; then
  sum "Script added to OBS" "OK ($ncols scene collection(s))"
else
  warn "The script was not added to OBS automatically. In OBS: Tools > Scripts > + > choose $DEST/obs_hollyland_tally.py"
  sum "Script added to OBS" "NO - add it in Tools > Scripts (+)"
fi

step "6/6 Status window (needs a Python with Tk 8.6+)"
if ! window_python && [ -n "$BREW" ] && [ "$BREW_DECLINED" = 0 ]; then
  case "$PY_DIR" in */opt/python@*) brew_install "python-tk@$PY_VER" || true ;; *) brew_install python-tk@3.14 || true ;; esac
  window_python
fi
if [ -n "$W_PY" ]; then
  good "Status window will use $W_PY (Tk $W_TK)"
  sum "Status window" "OK ($W_PY, Tk $W_TK)"
else
  warn "No Python with Tk 8.6+ was found, so the status window may open blank or not at all."
  if [ -n "$BREW" ]; then warn "Tally lights still work. Fix: in Terminal run: brew install python-tk@3.14"
  else warn "Tally lights still work. Fix: install Homebrew (https://brew.sh), then: brew install python-tk@3.14"; fi
  sum "Status window" "NEEDS Tk 8.6+ (brew install python-tk@3.14)"
fi
fw="$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null)"
case "$fw" in *enabled*|*"State = 1"*|*"State = 2"*)
  warn "macOS Firewall is on. When OBS asks to accept incoming network connections, click Allow (the base connects to TCP $PORT)."
  sum "macOS Firewall" "ON - allow OBS incoming connections" ;;
*disabled*|*"State = 0"*) sum "macOS Firewall" "off" ;;
*) sum "macOS Firewall" "unknown" ;;
esac

if [ "$NO_OBS" = 0 ] && [ -n "$OBS_APP" ]; then
  say ""; say "Starting OBS..."
  t0="$(date +%s)"
  start_obs
  loaded=""
  i=0; while [ $i -lt 60 ] && [ -z "$loaded" ]; do
    sleep 0.5; i=$((i+1))
    lf="$(ls -t "$CFG/logs/"*.txt 2>/dev/null | head -n 1)"
    [ -n "$lf" ] || continue
    [ "$(stat -f %m "$lf" 2>/dev/null || echo 0)" -ge $((t0 - 2)) ] || continue
    if grep -q "Loaded python script: .*obs_hollyland_tally\.py" "$lf" 2>/dev/null; then loaded=yes
    elif grep -q "\[Python\] Could not load library" "$lf" 2>/dev/null; then loaded=no; fi
  done
  case "$loaded" in
    yes) sum "Script loaded in OBS" "OK" ;;
    no)  sum "Script loaded in OBS" "FAILED - OBS could not load Python (Tools > Scripts > Python Settings)" ;;
    *)   sum "Script loaded in OBS" "not confirmed yet (check the status window)" ;;
  esac
fi

say ""; say "Opening the scripts folder in Finder: $DEST"
open "$DEST" >/dev/null 2>&1

echo
say "${C_GREEN}================ WHAT THE INSTALLER DID ================${C_OFF}"
say "Read this summary, then close this window yourself when you are done."

printf '%s' "$SUMMARY"
echo
say "${C_CYAN}On the Hollyland tally base set:${C_OFF}"
say "${C_CYAN}   Switcher = vMix,  Switcher IP = one of this Mac's IPs below,  Port = $PORT${C_OFF}"
ips="$(lan_ips)"
if [ -n "$ips" ]; then
  first=1
  while IFS=$'\t' read -r ip dev label virt; do
    tag=""
    if [ $first = 1 ] && [ "$virt" = 0 ]; then tag="  <- use this one (most likely)"; elif [ "$virt" = 1 ]; then tag="  (VPN/virtual - not for the tally base)"; fi
    printf '   %-16s (%s, %s)%s\n' "$ip" "$label" "$dev" "$tag"
    first=0
  done <<< "$ips"
else
  warn "   (no network address found - connect this Mac to the network)"
fi
say "   (NOT the tally base's own IP. The base and this Mac must be on the same network.)"
say "   If macOS asks whether OBS may find devices on your local network, click Allow."
echo
say "Until you pick scenes for the lights (OBS > Tools > Scripts > obs_hollyland_tally.py),"
say "lights 1,2,3,4 follow your first 4 OBS scenes automatically."
say "Log saved to $LOG"
COPIED=0   # Finder already opened
finish 0
