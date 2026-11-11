#!/bin/bash
# Hollyland Tally for OBS - macOS installer. Double-click this file in Finder.
# If macOS blocks it: right-click > Open > Open (or System Settings > Privacy & Security > Open Anyway).
# If it says you do not have access privileges: in Terminal run
#   chmod +x "Install Hollyland Tally.command"     (or: bash "Install Hollyland Tally.command")
printf '\033]0;Hollyland Tally for OBS - Installer\007'
cd "$(dirname "$0")" || exit 1
if [ ! -f "install_mac.sh" ] || [ ! -f "obs_hollyland_tally.py" ] || [ ! -f "tally_window.pyw" ]; then
  echo
  echo " install_mac.sh / the script files were not found next to this file."
  echo " Extract the whole ZIP first (double-click the ZIP), then run"
  echo " \"Install Hollyland Tally.command\" from the extracted folder."
  echo
  printf 'Press Return to close this window. '; read -r _
  exit 1
fi
/bin/bash "./install_mac.sh" "$@"
