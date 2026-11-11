#!/bin/bash
# Hollyland Tally for OBS - macOS installer. Double-click this file first.
# If macOS blocks it: right-click > Open > Open (or System Settings > Privacy & Security > Open Anyway).
# If it says you do not have access privileges: in Terminal run
#   chmod +x "1. Click to Install.command"     (or: bash "1. Click to Install.command")
printf '\033]0;Hollyland Tally for OBS - Installer\007'
cd "$(dirname "$0")" || exit 1
if [ ! -f "helpers/install_mac.sh" ] || [ ! -f "../obs_hollyland_tally.py" ] || [ ! -f "../tally_window.pyw" ]; then
  echo
  echo " The installer files were not found."
  echo " Extract the whole ZIP first (double-click the ZIP), then open the mac"
  echo " folder and double-click \"1. Click to Install.command\"."
  echo
  printf 'Press Return to close this window. '; read -r _
  exit 1
fi
/bin/bash "./helpers/install_mac.sh" "$@"
