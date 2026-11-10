$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Host "Hollyland Tally for OBS - installer" -ForegroundColor Cyan
if (Get-Process obs64 -ErrorAction SilentlyContinue) {
  Write-Host "Please close OBS first, then run this installer again." -ForegroundColor Yellow
  Read-Host "Press Enter to exit"; exit 1
}
# find Python 3.11 (python.org install)
$cands = @("$env:LOCALAPPDATA\Programs\Python\Python311", "$env:LOCALAPPDATA\Programs\Python\Python310", "$env:LOCALAPPDATA\Programs\Python\Python312", "C:\Program Files\Python311", "C:\Python311")
$py = $cands | Where-Object { Test-Path "$_\python.exe" } | Select-Object -First 1
if (-not $py) {
  Write-Host "Python 3.11 (64-bit) was not found. Install it from python.org (tick 'tcl/tk'), then run this again." -ForegroundColor Red
  Read-Host "Press Enter to exit"; exit 1
}
Write-Host "Python: $py"
$dest = "$env:APPDATA\obs-studio\scripts"
New-Item -ItemType Directory -Force $dest | Out-Null
Copy-Item "$here\obs_hollyland_tally.py" $dest -Force
Copy-Item "$here\tally_window.pyw" $dest -Force
# tell OBS where Python is
$ini = "$env:APPDATA\obs-studio\user.ini"
$txt = if (Test-Path $ini) { Get-Content $ini -Raw } else { "" }
if ($txt -notmatch "(?m)^Path64=") {
  Add-Content $ini "`r`n[Python]`r`nPath64=$($py -replace '\\','/')"
  Write-Host "Set OBS Python path"
}
# add script to OBS Tools > Scripts
& "$py\python.exe" "$here\add_to_obs.py"
Write-Host "`nDone. Open OBS: the tally script loads by itself and the status window opens automatically." -ForegroundColor Green
Write-Host "Set the Hollyland base 'Switcher IP' to this PC's IP, port 8099."
Read-Host "Press Enter to close"
