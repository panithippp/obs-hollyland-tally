$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Host "Hollyland Tally for OBS - installer" -ForegroundColor Cyan
$obs = Get-Process obs64 -ErrorAction SilentlyContinue
if ($obs) {
  Write-Host "OBS is open - closing it so the installer can update its settings..." -ForegroundColor Yellow
  $obs | ForEach-Object { [void]$_.CloseMainWindow() }
  for ($i = 0; $i -lt 60 -and (Get-Process obs64 -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 500 }
  if (Get-Process obs64 -ErrorAction SilentlyContinue) {
    Write-Host "OBS did not close. Please close OBS (answer any dialog it shows), then run this installer again." -ForegroundColor Red
    Read-Host "Press Enter to exit"; exit 1
  }
  Start-Sleep -Seconds 2
  $reopen = $true
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
# tell OBS where Python is ([Python] Path64bit in user.ini, older OBS: global.ini)
$pyPath = $py -replace '\\','/'
function Set-ObsPython($ini) {
  $lines = if (Test-Path $ini) { [System.Collections.Generic.List[string]]@(Get-Content $ini) } else { New-Object System.Collections.Generic.List[string] }
  $start = $lines.IndexOf("[Python]")
  if ($start -lt 0) { $lines.Add(""); $lines.Add("[Python]"); $lines.Add("Path64bit=$pyPath") }
  else {
    $end = $lines.Count
    for ($i = $start + 1; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\[') { $end = $i; break } }
    $found = $false
    for ($i = $start + 1; $i -lt $end; $i++) { if ($lines[$i] -match '^Path64bit=') { $lines[$i] = "Path64bit=$pyPath"; $found = $true } }
    if (-not $found) { $lines.Insert($start + 1, "Path64bit=$pyPath") }
  }
  [System.IO.File]::WriteAllLines($ini, $lines, (New-Object System.Text.UTF8Encoding($false)))
  Write-Host "Set OBS Python path in $(Split-Path -Leaf $ini): $pyPath"
}
$obsDir = "$env:APPDATA\obs-studio"
New-Item -ItemType Directory -Force $obsDir | Out-Null
Set-ObsPython "$obsDir\user.ini"
if (Test-Path "$obsDir\global.ini") { Set-ObsPython "$obsDir\global.ini" }
# add script to OBS Tools > Scripts
& "$py\python.exe" "$here\add_to_obs.py"
if ($LASTEXITCODE -ne 0) { Write-Host "Could not add the script to OBS. Open OBS once, close it, then run this installer again." -ForegroundColor Red; Read-Host "Press Enter to exit"; exit 1 }
Write-Host "`nDone. Open OBS: the tally script loads by itself and the status window opens automatically." -ForegroundColor Green
Write-Host "Set the Hollyland base 'Switcher IP' to this PC's IP, port 8099."
if ($reopen) {
  $exe = "C:\Program Files\obs-studio\bin\64bit\obs64.exe"
  if (Test-Path $exe) { Write-Host "Reopening OBS..."; Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) }
}
Read-Host "Press Enter to close"
