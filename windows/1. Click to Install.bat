@echo off
setlocal
title Hollyland Tally for OBS - Installer
if not exist "%~dp0helpers\install.ps1" (
  echo.
  echo  helpers\install.ps1 was not found next to this file.
  echo  Extract the whole ZIP first: right click the ZIP ^> Extract All, then open
  echo  the windows folder and double-click "1. Click to Install.bat".
  echo.
  pause
  exit /b 1
)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0helpers\install.ps1" %*
set ERR=%ERRORLEVEL%
if not "%ERR%"=="0" (
  echo.
  echo  Installer ended with error %ERR%. Log: %TEMP%\hollyland_tally_install.log
  pause
)
exit /b %ERR%
