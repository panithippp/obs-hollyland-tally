@echo off
setlocal
title Hollyland Tally for OBS - Uninstall
if not exist "%~dp0uninstall.ps1" (
  echo  uninstall.ps1 was not found next to this file. Extract the whole ZIP first, then open the windows folder.
  pause
  exit /b 1
)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" %*
set ERR=%ERRORLEVEL%
if not "%ERR%"=="0" (
  echo.
  echo  Uninstall ended with error %ERR%.
  pause
)
exit /b %ERR%
