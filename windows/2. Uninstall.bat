@echo off
setlocal
title Hollyland Tally for OBS - Uninstall
if not exist "%~dp0helpers\uninstall.ps1" (
  echo.
  echo  helpers\uninstall.ps1 was not found. Extract the whole ZIP first, then open the windows folder.
  echo.
  pause
  exit /b 1
)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0helpers\uninstall.ps1" %*
exit /b %ERRORLEVEL%
