#!/bin/bash
# Hollyland Tally for OBS - macOS uninstaller. Double-click this file to uninstall.
printf '\033]0;Hollyland Tally for OBS - Uninstall\007'
cd "$(dirname "$0")" || exit 1
if [ ! -f "helpers/uninstall_mac.sh" ]; then
  echo
  echo " helpers/uninstall_mac.sh was not found."
  echo " Extract the whole ZIP first, then open the mac folder and run this file from there."
  echo
  printf 'Press Return to close this window. '; read -r _
  exit 1
fi
/bin/bash "./helpers/uninstall_mac.sh" "$@"
