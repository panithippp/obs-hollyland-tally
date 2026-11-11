#!/bin/bash
# Hollyland Tally for OBS - macOS uninstaller (run via "Uninstall Hollyland Tally.command")
# Removes the script from every OBS scene collection and deletes its two files.
# Keeps Python and the OBS Python path (other scripts may use them).
# Test switches: --no-obs-control, --no-pause, --yes, --obs-dir DIR
CFG="$HOME/Library/Application Support/obs-studio"
BUNDLE_ID="com.obsproject.obs-studio"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
src() {
  if [ -f "$HERE/$1" ]; then printf '%s\n' "$HERE/$1"
  elif [ -f "$ROOT/$1" ]; then printf '%s\n' "$ROOT/$1"
  fi
}
NO_OBS=0; NO_PAUSE=0; YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --no-obs-control) NO_OBS=1 ;; --no-pause) NO_PAUSE=1 ;; --yes) YES=1 ;;
    --obs-dir) shift; CFG="$1" ;;
  esac
  shift
done
C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_OFF=$'\033[0m'
say()  { printf '%s\n' "$*"; }
warn() { printf '%s%s%s\n' "$C_YELLOW" "$*" "$C_OFF"; }
ask()  { local a=""; printf '%s ' "$1"; { read -r a </dev/tty; } 2>/dev/null || read -r a; REPLY="$a"; }
pause_end() { [ "$NO_PAUSE" = 1 ] && return; echo; ask "When you have finished reading, press Return to close this window (or close it yourself)."; }
obs_pids() { ps -axo pid=,comm= 2>/dev/null | awk '/\.app\/Contents\/MacOS\/(OBS|obs)$/ {print $1}'; }
wait_obs_gone() { local i=0; while [ $i -lt "$1" ] && [ -n "$(obs_pids)" ]; do sleep 0.5; i=$((i+1)); done; [ -z "$(obs_pids)" ]; }
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

say "${C_CYAN}Hollyland Tally for OBS - uninstall${C_OFF}"
if [ "$YES" = 0 ]; then
  ask "Remove the Hollyland Tally script from OBS? (y/n)"
  case "$REPLY" in [yY]*) ;; *) say "Cancelled."; pause_end; exit 0 ;; esac
fi

OBS_APP=""; WAS_OPEN=0
pid="$(obs_pids | head -n 1)"
if [ -n "$pid" ]; then comm="$(ps -o comm= -p "$pid" 2>/dev/null)"; OBS_APP="${comm%%.app/Contents/MacOS/*}.app"; fi
if [ "$NO_OBS" = 0 ] && [ -n "$(obs_pids)" ]; then
  warn "Closing OBS..."
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1
  if ! wait_obs_gone 40; then
    while [ -n "$(obs_pids)" ]; do ask "Please quit OBS yourself (Cmd+Q), then press Return."; wait_obs_gone 10; done
  fi
  sleep 2; WAS_OPEN=1
fi
# stop the status window
pkill -f "tally_window\.pyw" >/dev/null 2>&1

# a Python to edit the scene collections: the one OBS uses, else any python3 that runs
py=""
for ini in user.ini global.ini; do
  d="$(ini_get "$CFG/$ini" Python Path64bit)"; d="${d%/}"
  [ -n "$py" ] || [ -z "$d" ] && continue
  for v in 3.12 3.11 3.10 3.9 3.8 3.7 3.6; do
    c="$d/Python.framework/Versions/$v/bin/python$v"
    [ -x "$c" ] && { py="$c"; break; }
  done
done
if [ -z "$py" ]; then
  for c in /opt/homebrew/bin/python3 /usr/local/bin/python3 /Library/Frameworks/Python.framework/Versions/Current/bin/python3; do
    [ -x "$c" ] && "$c" -c 'import json' >/dev/null 2>&1 && { py="$c"; break; }
  done
fi
if [ -z "$py" ] && xcode-select -p >/dev/null 2>&1 && [ -x /usr/bin/python3 ]; then py=/usr/bin/python3; fi

removed=0
ADD="$(src add_to_obs.py)"
if [ -n "$py" ] && [ -n "$ADD" ] && ls "$CFG/basic/scenes/"*.json >/dev/null 2>&1; then
  "$py" "$ADD" --remove --obsdir "$CFG" && removed=1
fi
[ $removed = 1 ] || warn "Could not edit the OBS scene collections automatically. In OBS > Tools > Scripts, select obs_hollyland_tally.py and click '-'."

for f in obs_hollyland_tally.py tally_window.pyw; do
  t="$CFG/scripts/$f"
  [ -f "$t" ] && rm -f "$t" && say "Deleted $t"
done
rm -f "$CFG/scripts/__pycache__/"obs_hollyland_tally*.pyc 2>/dev/null
rm -f "$HOME/.hollyland_tally_window.json" 2>/dev/null
T="${TMPDIR:-/tmp}"; T="${T%/}"
rm -f "$T/obs_hollyland_tally_status.json" "$T/obs_hollyland_tally_status.json.tmp" "$T/obs_hollyland_tally_closed.json" 2>/dev/null

if [ "$WAS_OPEN" = 1 ] && [ -n "$OBS_APP" ] && [ -d "$OBS_APP" ] && [ "$NO_OBS" = 0 ]; then open "$OBS_APP" >/dev/null 2>&1; fi
[ -d "$CFG/scripts" ] && open "$CFG/scripts" >/dev/null 2>&1
say ""; printf '%sHollyland Tally removed.%s\n' "$C_GREEN" "$C_OFF"
pause_end; exit 0
