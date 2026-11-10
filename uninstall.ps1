# Hollyland Tally for OBS - uninstaller (run via "Uninstall Hollyland Tally.bat")
# Removes the script from every OBS scene collection and deletes its files.
# Keeps Python and the OBS Python path (other scripts may use them).
param([switch]$NoObsControl, [switch]$NoPause, [switch]$Yes)
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$PORT = 8099
function Say($m, $c = "Gray") { Write-Host $m -ForegroundColor $c }
function Pause-End { if (-not $NoPause) { Write-Host ""; [void](Read-Host "Press Enter to close") } }
function Get-ObsProcs { @(Get-Process obs64 -ErrorAction SilentlyContinue) }
try {
  Say "Hollyland Tally for OBS - uninstall" Cyan
  if (-not $Yes) {
    $a = Read-Host "Remove the Hollyland Tally script from OBS? (y/n)"
    if ($a -notmatch '^[yY]') { Say "Cancelled."; Pause-End; exit 0 }
  }
  $obsDir = Join-Path $env:APPDATA "obs-studio"
  $obsExe = $null; $wasOpen = $false
  $p = Get-ObsProcs | Select-Object -First 1
  if ($p -and $p.Path) { $obsExe = $p.Path }
  if (-not $NoObsControl -and (Get-ObsProcs).Count) {
    Say "Closing OBS..." Yellow
    Get-ObsProcs | ForEach-Object { [void]$_.CloseMainWindow() }
    for ($i = 0; $i -lt 40 -and (Get-ObsProcs).Count; $i++) { Start-Sleep -Milliseconds 500 }
    while ((Get-ObsProcs).Count) { [void](Read-Host "Please close OBS yourself, then press Enter") }
    Start-Sleep -Seconds 2; $wasOpen = $true
  }
  # stop the status window
  Get-CimInstance Win32_Process -Filter "Name='pythonw.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*tally_window.pyw*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

  # find the Python that OBS uses, to edit the scene collections safely
  $py = $null
  foreach ($ini in @("user.ini", "global.ini")) {
    $f = Join-Path $obsDir $ini
    if (-not $py -and (Test-Path -LiteralPath $f)) {
      $in = $false
      foreach ($l in ([IO.File]::ReadAllText($f) -split "\r?\n")) {
        if ($l -match '^\s*\[(.+)\]') { $in = ($matches[1] -eq "Python"); continue }
        if ($in -and $l -match '^\s*Path64bit\s*=(.+)$') { $c = Join-Path ($matches[1].Trim() -replace '/', '\') "python.exe"; if (Test-Path -LiteralPath $c) { $py = $c } }
      }
    }
  }
  $removed = $false
  if ($py -and (Test-Path -LiteralPath (Join-Path $here "add_to_obs.py"))) {
    $ErrorActionPreference = "Continue"
    & $py (Join-Path $here "add_to_obs.py") --remove 2>&1 | ForEach-Object { Say "$_" }
    $removed = ($LASTEXITCODE -eq 0)
    $ErrorActionPreference = "Stop"
  }
  if (-not $removed) { Say "Could not edit the OBS scene collections automatically. In OBS > Tools > Scripts, select obs_hollyland_tally.py and click '-'." Yellow }

  foreach ($f in @("obs_hollyland_tally.py", "tally_window.pyw")) {
    $t = Join-Path $obsDir "scripts\$f"
    if (Test-Path -LiteralPath $t) { Remove-Item -LiteralPath $t -Force; Say "Deleted $t" }
  }
  Remove-Item -Path (Join-Path $obsDir "scripts\__pycache__\obs_hollyland_tally*.pyc") -Force -ErrorAction SilentlyContinue
  foreach ($f in @("obs_hollyland_tally_status.json", "obs_hollyland_tally_status.json.tmp")) { Remove-Item -LiteralPath (Join-Path $env:TEMP $f) -Force -ErrorAction SilentlyContinue }

  $rule = Get-NetFirewallRule -DisplayName "Hollyland Tally (OBS TCP $PORT)" -ErrorAction SilentlyContinue
  if ($rule) {
    Say "Removing the firewall rule 'Hollyland Tally (OBS TCP $PORT)' (Windows asks for permission)..." Yellow
    try {
      Start-Process -FilePath "powershell.exe" -Verb RunAs -WindowStyle Hidden -Wait -ArgumentList @("-NoProfile", "-Command", "Remove-NetFirewallRule -DisplayName 'Hollyland Tally (OBS TCP $PORT)'") | Out-Null
    } catch { Say "Firewall rule kept (permission declined). Remove it in Windows Defender Firewall > Inbound Rules if you want." Yellow }
  }
  if ($wasOpen -and $obsExe -and -not $NoObsControl) { Start-Process -FilePath $obsExe -WorkingDirectory (Split-Path -Parent $obsExe) | Out-Null }
  Say ""; Say "Hollyland Tally removed." Green
  Pause-End; exit 0
} catch {
  Say "UNINSTALL FAILED: $($_.Exception.Message)" Red
  Pause-End; exit 1
}
