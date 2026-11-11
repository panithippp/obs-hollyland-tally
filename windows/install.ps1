# Hollyland Tally for OBS - Windows installer (run via "Install Hollyland Tally.bat")
# No admin needed. Only the optional firewall step asks for UAC, and only if it is needed.
# Test switches (normal users never need them):
#   -NoObsControl      never close/start OBS (for tests with a temporary APPDATA)
#   -SimulateNoPython  pretend no usable Python exists (with -PythonDownloadOnly: just download + verify the installer)
#   -PythonDownloadOnly
#   -SkipFirewall      only check, never ask for UAC
#   -NoPause           do not wait for Enter at the end
#   -ListPython        only list the Python installs found and exit
param([switch]$ListPython, [switch]$NoObsControl, [switch]$SimulateNoPython, [switch]$PythonDownloadOnly, [switch]$SkipFirewall, [switch]$NoPause)

$ErrorActionPreference = "Stop"
$PY_URL  = "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe"
$PY_PREF = @("3.11", "3.12", "3.10", "3.9", "3.8")   # OBS 28-33 load Python 3.6 - 3.12
$PORT    = 8099
$log     = Join-Path $env:TEMP "hollyland_tally_install.log"
$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$root    = Split-Path -Parent $here
# Installer files are in windows/; the OBS script files live in the repo root (parent folder).
function Get-Src([string]$name) {
  foreach ($d in @($here, $root)) {
    $p = Join-Path $d $name
    if (Test-Path -LiteralPath $p) { return $p }
  }
  return $null
}
$summary = [ordered]@{}
$script:startedTranscript = $false

function Say($msg, $color = "Gray") { Write-Host $msg -ForegroundColor $color }
function Step($msg) { Write-Host ""; Write-Host "== $msg" -ForegroundColor Cyan }
function Pause-End { if (-not $NoPause) { Write-Host ""; [void](Read-Host "Press Enter to close") } }

# ---------- OBS ----------
function Find-Obs {
  $dirs = @()
  foreach ($k in @("HKLM:\SOFTWARE\OBS Studio", "HKLM:\SOFTWARE\WOW6432Node\OBS Studio", "HKCU:\SOFTWARE\OBS Studio")) {
    try { $v = (Get-ItemProperty -LiteralPath $k -ErrorAction Stop).'(default)'; if ($v) { $dirs += $v } } catch {}
  }
  try { Get-Process obs64 -ErrorAction Stop | ForEach-Object { if ($_.Path) { $dirs += (Split-Path (Split-Path (Split-Path $_.Path))) } } } catch {}
  $dirs += @("$env:ProgramFiles\obs-studio", "${env:ProgramFiles(x86)}\obs-studio", "$env:LOCALAPPDATA\Programs\obs-studio",
             "${env:ProgramFiles(x86)}\Steam\steamapps\common\OBS Studio", "$env:ProgramFiles\Steam\steamapps\common\OBS Studio")
  foreach ($d in $dirs) {
    if (-not $d) { continue }
    $exe = Join-Path $d "bin\64bit\obs64.exe"
    if (Test-Path -LiteralPath $exe) { return (Get-Item -LiteralPath $exe).FullName }
  }
  return $null
}

function Get-ObsProcs { @(Get-Process obs64 -ErrorAction SilentlyContinue) }

$winApi = @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class HlWin {
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  public static List<IntPtr> Visible(int pid) {
    var r = new List<IntPtr>();
    EnumWindows((h, l) => { uint o; GetWindowThreadProcessId(h, out o); if (o == pid && IsWindowVisible(h)) r.Add(h); return true; }, IntPtr.Zero);
    return r;
  }
}
"@

function Close-ObsDialogs {
  # first run only: OBS opens the Auto-Configuration Wizard / update dialogs, which block closing. WM_CLOSE = Cancel.
  try { if (-not ("HlWin" -as [type])) { Add-Type -TypeDefinition $winApi } } catch { return }
  foreach ($p in (Get-ObsProcs)) {
    $main = $p.MainWindowHandle
    foreach ($h in [HlWin]::Visible($p.Id)) { if ($h -ne $main) { [void][HlWin]::PostMessage($h, 0x10, [IntPtr]::Zero, [IntPtr]::Zero) } }
  }
}

function Close-Obs([string]$why, [bool]$firstRun = $false) {
  if ((Get-ObsProcs).Count -eq 0) { return $false }
  Say "OBS is open - closing it $why..." Yellow
  if ($firstRun) {
    # wizard / "New update available" dialogs block closing: cancel them (WM_CLOSE), then ask the main window once
    for ($k = 0; $k -lt 5; $k++) { Close-ObsDialogs; Start-Sleep -Seconds 1 }
    Get-ObsProcs | ForEach-Object { [void]$_.CloseMainWindow() }
    for ($k = 0; $k -lt 30 -and (Get-ObsProcs).Count; $k++) { Start-Sleep -Seconds 1; Close-ObsDialogs }
  } else {
    Get-ObsProcs | ForEach-Object { [void]$_.CloseMainWindow() }
  }
  for ($i = 0; $i -lt 40 -and (Get-ObsProcs).Count; $i++) { Start-Sleep -Milliseconds 500 }
  while ((Get-ObsProcs).Count) {
    Say "OBS is still open (maybe it is streaming/recording or showing a question)." Yellow
    Say "Please close OBS yourself (answer any OBS dialog), then press Enter here." Yellow
    [void](Read-Host "Press Enter when OBS is closed")
    for ($i = 0; $i -lt 10 -and (Get-ObsProcs).Count; $i++) { Start-Sleep -Milliseconds 500 }
  }
  Start-Sleep -Seconds 2
  return $true
}

function Start-Obs($exe) {
  Start-Process -FilePath $exe -WorkingDirectory (Split-Path -Parent $exe) | Out-Null
}

# ---------- Python ----------
function Test-Python($dir) {
  # returns @{Dir;Ver;Tk} or $null. Must be 64-bit CPython with pythonw.exe and pythonXY.dll (what OBS loads)
  if (-not $dir) { return $null }
  $dir = $dir.TrimEnd('\', '/')
  if ($dir -match '\\WindowsApps(\\|$)') { return $null }   # Microsoft Store stub: OBS cannot load it
  $py = Join-Path $dir "python.exe"
  if (-not (Test-Path -LiteralPath $py) -or -not (Test-Path -LiteralPath (Join-Path $dir "pythonw.exe"))) { return $null }
  try {
    $out = & $py -c "import sys,struct;v='%d.%d'%sys.version_info[:2];b=struct.calcsize('P')*8
try:
  import tkinter;r=tkinter.Tcl();tk='1'
except Exception: tk='0'
print(v,b,tk)" 2>$null
  } catch { return $null }
  if (-not $out) { return $null }
  $p = ("$out".Trim()) -split '\s+'
  if ($p.Count -lt 3 -or $p[1] -ne "64") { return $null }
  if ($PY_PREF -notcontains $p[0]) { return $null }   # OBS cannot load 3.13+ (or very old versions)
  $dll = Join-Path $dir ("python" + ($p[0] -replace '\.', '') + ".dll")
  if (-not (Test-Path -LiteralPath $dll)) { return $null }
  return @{ Dir = (Get-Item -LiteralPath $dir).FullName; Ver = $p[0]; Tk = ($p[2] -eq "1") }
}

function Find-PythonCandidates {
  $c = New-Object System.Collections.Generic.List[string]
  foreach ($hive in @("HKCU:", "HKLM:")) {
    foreach ($v in $PY_PREF) {
      foreach ($tag in @($v, "$v-64")) {
        try { $ip = (Get-ItemProperty -LiteralPath "$hive\Software\Python\PythonCore\$tag\InstallPath" -ErrorAction Stop).'(default)'; if ($ip) { $c.Add($ip) } } catch {}
      }
    }
  }
  try {
    $lines = & py -0p 2>$null
    foreach ($l in @($lines)) {
      if ("$l" -match '-V:(3\.\d+)\s+\*?\s*(.+python\.exe)\s*$') { $c.Add((Split-Path -Parent $matches[2].Trim())) }
      elseif ("$l" -match '^\s*-(3\.\d+)(-64)?\s+\*?\s*(.+python\.exe)\s*$') { $c.Add((Split-Path -Parent $matches[3].Trim())) }
    }
  } catch {}
  foreach ($v in $PY_PREF) {
    $n = "Python" + ($v -replace '\.', '')
    $c.Add("$env:LOCALAPPDATA\Programs\Python\$n"); $c.Add("$env:ProgramFiles\$n"); $c.Add("C:\$n")
    $c.Add("$env:ProgramFiles\Python\$n")
  }
  return $c
}

function Select-Python {
  if ($SimulateNoPython) { return $null }
  $seen = @{}; $found = @()
  foreach ($d in (Find-PythonCandidates)) {
    if (-not $d) { continue }
    $key = $d.TrimEnd('\', '/').ToLower()
    if ($seen.ContainsKey($key)) { continue }; $seen[$key] = 1
    $t = Test-Python $d
    if ($t) { $found += $t }
  }
  if (-not $found) { return $null }
  # best: has tkinter, then preferred version order
  $best = $found | Sort-Object @{ e = { if ($_.Tk) { 0 } else { 1 } } }, @{ e = { $i = [array]::IndexOf($PY_PREF, $_.Ver); if ($i -lt 0) { 99 } else { $i } } } | Select-Object -First 1
  return $best
}

function Install-Python {
  $exe = Join-Path $env:TEMP "python-3.11.9-amd64.exe"
  $okDownload = $false
  try {
    Say "Downloading Python 3.11 (64-bit) from python.org ..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = "SilentlyContinue"
    Invoke-WebRequest -Uri $PY_URL -OutFile $exe -UseBasicParsing
    $sig = Get-AuthenticodeSignature -LiteralPath $exe
    if ($sig.Status -ne "Valid" -or $sig.SignerCertificate.Subject -notmatch "Python Software Foundation") {
      throw "downloaded file is not signed by the Python Software Foundation ($($sig.Status))"
    }
    $okDownload = $true
    Say ("Downloaded and verified: {0:N1} MB, signed by Python Software Foundation" -f ((Get-Item $exe).Length / 1MB))
  } catch { Say "Download failed: $($_.Exception.Message)" Yellow }
  if ($PythonDownloadOnly) { Remove-Item -LiteralPath $exe -Force -ErrorAction SilentlyContinue; $summary["Python download test"] = $(if ($okDownload) { "OK (not installed: -PythonDownloadOnly)" } else { "FAILED" }); return }
  if ($okDownload) {
    Say "Installing Python 3.11 for this user only (no admin, takes about 1 minute)..."
    $p = Start-Process -FilePath $exe -ArgumentList "/quiet InstallAllUsers=0 Include_tcltk=1 Include_pip=1 PrependPath=0 Include_launcher=0 Include_test=0 Shortcuts=0" -Wait -PassThru
    Say "Python installer exit code: $($p.ExitCode)"
    Remove-Item -LiteralPath $exe -Force -ErrorAction SilentlyContinue
    if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010) { return }
  }
  $wg = Get-Command winget -ErrorAction SilentlyContinue
  if ($wg) {
    Say "Trying winget instead..."
    $ErrorActionPreference = "Continue"
    & winget install -e --id Python.Python.3.11 --scope user --silent --accept-package-agreements --accept-source-agreements 2>&1 | ForEach-Object { Say "$_" }
    $ErrorActionPreference = "Stop"
  }
}

# ---------- ini (OBS writes UTF-8 with BOM) ----------
function Set-IniValue($ini, $section, $key, $value) {
  $text = ""
  if (Test-Path -LiteralPath $ini) { $text = [IO.File]::ReadAllText($ini) }   # BOM-aware, UTF-8 default
  $nl = if ($text -match "`r`n") { "`r`n" } else { "`n" }
  $lines = New-Object System.Collections.Generic.List[string]
  if ($text.Length) { foreach ($l in ($text -split "\r?\n")) { $lines.Add($l) } }
  while ($lines.Count -and $lines[$lines.Count - 1] -eq "") { $lines.RemoveAt($lines.Count - 1) }
  $start = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq "[$section]") { $start = $i; break } }
  if ($start -lt 0) {
    if ($lines.Count) { $lines.Add("") }
    $lines.Add("[$section]"); $lines.Add("$key=$value")
  } else {
    $end = $lines.Count
    for ($i = $start + 1; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*\[') { $end = $i; break } }
    $done = $false
    for ($i = $start + 1; $i -lt $end; $i++) { if ($lines[$i] -match ("^\s*" + [regex]::Escape($key) + "\s*=")) { $lines[$i] = "$key=$value"; $done = $true } }
    if (-not $done) {
      $ins = $end; while ($ins -gt $start + 1 -and $lines[$ins - 1].Trim() -eq "") { $ins-- }
      $lines.Insert($ins, "$key=$value")
    }
  }
  if (Test-Path -LiteralPath $ini) { Copy-Item -LiteralPath $ini -Destination "$ini.bak_tally" -Force }
  [IO.File]::WriteAllText($ini, (($lines -join $nl) + $nl), (New-Object System.Text.UTF8Encoding($true)))
}

function Get-IniValue($ini, $section, $key) {
  if (-not (Test-Path -LiteralPath $ini)) { return $null }
  $in = $false
  foreach ($l in ([IO.File]::ReadAllText($ini) -split "\r?\n")) {
    if ($l -match '^\s*\[(.+)\]\s*$') { $in = ($matches[1] -eq $section); continue }
    if ($in -and $l -match ("^\s*" + [regex]::Escape($key) + "\s*=(.*)$")) { return $matches[1].Trim() }
  }
  return $null
}

# ---------- firewall ----------
function Test-FirewallOk($obsExe) {
  # returns "OK", "OFF", "BLOCKED", "MISSING", or "UNKNOWN"   (reading rules needs no admin)
  try {
    $on = @(Get-NetFirewallProfile -ErrorAction Stop | Where-Object { "$($_.Enabled)" -eq "True" } | ForEach-Object { "$($_.Name)" })
    $cats = @(Get-NetConnectionProfile -ErrorAction SilentlyContinue | ForEach-Object { "$($_.NetworkCategory)" -replace 'DomainAuthenticated', 'Domain' })
    if (-not $cats) { $cats = @("Private", "Public") }
    $cats = @($cats | Where-Object { $on -contains $_ } | Select-Object -Unique)
    if (-not $cats) { return "OFF" }
    $cand = @()
    $cand += @(Get-NetFirewallApplicationFilter -ErrorAction Stop | Where-Object { $_.Program -and [Environment]::ExpandEnvironmentVariables($_.Program) -ieq $obsExe } | Get-NetFirewallRule)
    $cand += @(Get-NetFirewallPortFilter -Protocol TCP -ErrorAction SilentlyContinue | Where-Object { @($_.LocalPort) -contains "$PORT" } | Get-NetFirewallRule)
    $allow = $false; $block = $false; $seen = @{}
    foreach ($r in $cand) {
      if ($seen.ContainsKey($r.Name)) { continue }; $seen[$r.Name] = 1
      if ("$($r.Enabled)" -ne "True" -or "$($r.Direction)" -ne "Inbound") { continue }
      $pf = $r | Get-NetFirewallPortFilter
      $prog = "$(($r | Get-NetFirewallApplicationFilter).Program)"
      if (-not ($prog -eq "Any" -or [Environment]::ExpandEnvironmentVariables($prog) -ieq $obsExe)) { continue }
      if (-not ("$($pf.Protocol)" -eq "Any" -or "$($pf.Protocol)" -eq "TCP")) { continue }
      if (-not (@($pf.LocalPort) -contains "Any" -or @($pf.LocalPort) -contains "$PORT")) { continue }
      $p = "$($r.Profile)"
      $covers = ($p -eq "Any") -or (@($cats | Where-Object { $p -match $_ }).Count -eq $cats.Count)
      if ("$($r.Action)" -eq "Block") { if ($p -eq "Any" -or @($cats | Where-Object { $p -match $_ }).Count) { $block = $true } }
      elseif ($covers) { $allow = $true }
    }
    if ($block) { return "BLOCKED" }
    if ($allow) { return "OK" }
    return "MISSING"
  } catch { return "UNKNOWN" }
}

function Fix-Firewall($obsExe) {
  $tmp = Join-Path $env:TEMP "hollyland_tally_firewall.ps1"
  $q = $obsExe -replace "'", "''"
  @"
`$ErrorActionPreference = 'Continue'
`$exe = '$q'
Get-NetFirewallRule -Direction Inbound -Action Block -ErrorAction SilentlyContinue | Where-Object { (`$_ | Get-NetFirewallApplicationFilter).Program -ieq `$exe } | Remove-NetFirewallRule
Get-NetFirewallRule -DisplayName 'Hollyland Tally (OBS TCP $PORT)' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
New-NetFirewallRule -DisplayName 'Hollyland Tally (OBS TCP $PORT)' -Direction Inbound -Action Allow -Program `$exe -Protocol TCP -LocalPort $PORT -Profile Any | Out-Null
"@ | Set-Content -LiteralPath $tmp -Encoding UTF8
  try {
    $p = Start-Process -FilePath "powershell.exe" -Verb RunAs -WindowStyle Hidden -Wait -PassThru `
         -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$tmp`"")
    return ($p.ExitCode -eq 0)
  } catch { return $false }
  finally { Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue }
}

function Get-LanIps {
  $ips = @()
  try {
    $cfg = @(Get-NetIPConfiguration -ErrorAction Stop | Where-Object { $_.IPv4Address -and $_.NetAdapter.Status -eq "Up" })
    foreach ($c in $cfg) {
      foreach ($a in @($c.IPv4Address)) {
        $ip = $a.IPAddress
        if ($ip -like "127.*" -or $ip -like "169.254.*") { continue }
        $o = [int]($ip.Split('.')[1])
        $virt = ($c.InterfaceAlias -match 'ZeroTier|Tailscale|VPN|vEthernet|VirtualBox|VMware|Hyper-V|WSL|Loopback|Hamachi|Radmin|WireGuard|OpenVPN|TAP') -or
                ($c.InterfaceDescription -match 'ZeroTier|Tailscale|VPN|Virtual|VMware|Hyper-V|TAP-|WireGuard|Hamachi') -or
                ($ip -like "100.*" -and $o -ge 64 -and $o -lt 128)
        $rank = 0; if ($virt) { $rank += 10 }; if (-not $c.IPv4DefaultGateway) { $rank += 2 }; if ($ip -notlike "192.168.*") { $rank += 1 }
        $ips += [pscustomobject]@{ IP = $ip; If = $c.InterfaceAlias; Rank = $rank; Virt = $virt }
      }
    }
  } catch {}
  return @($ips | Sort-Object Rank)
}

# ================= main =================
try {
  try { Start-Transcript -LiteralPath $log -Force | Out-Null; $script:startedTranscript = $true } catch {}
  Say "Hollyland Tally for OBS - installer" Cyan
  Say "Folder: $here"
  Say "Scripts: $root"
  Say "Log:    $log"
  foreach ($f in @("obs_hollyland_tally.py", "tally_window.pyw", "add_to_obs.py")) {
    if (-not (Get-Src $f)) { throw "Missing file '$f'. Extract the whole ZIP first (right click > Extract All), then open the windows folder and run the installer from there." }
  }
  Get-ChildItem -LiteralPath $here -File | Unblock-File -ErrorAction SilentlyContinue
  Get-ChildItem -LiteralPath $root -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue
  if ($ListPython) {
    foreach ($d in (Find-PythonCandidates | ForEach-Object { $_.TrimEnd('\', '/') } | Sort-Object -Unique)) { $t = Test-Python $d; if ($t) { Say ("usable  {0}  tkinter={1}  {2}" -f $t.Ver, $t.Tk, $t.Dir) Green } elseif (Test-Path -LiteralPath (Join-Path $d "python.exe")) { Say "skipped $d (not 64-bit, no pythonw/DLL, or version OBS cannot load)" } }
    $b = Select-Python; Say "selected: $(if ($b) { "$($b.Ver) $($b.Dir)" } else { 'none' })" Cyan
    exit 0
  }

  Step "1/6 OBS Studio"
  $obsExe = Find-Obs
  if (-not $obsExe) { throw "OBS Studio (64-bit) is not installed on this PC. Install it from https://obsproject.com and run this installer again." }
  $obsVer = (Get-Item -LiteralPath $obsExe).VersionInfo.ProductVersion
  Say "OBS: $obsExe (version $obsVer)" Green
  $summary["OBS"] = "$obsExe ($obsVer)"
  $obsMajor = 0; [void][int]::TryParse(("$obsVer" -split '\.')[0], [ref]$obsMajor)

  Step "2/6 Python (OBS needs 64-bit Python 3.6 - 3.12, 3.11 recommended)"
  $py = Select-Python
  if (-not $py -or (-not $py.Tk -and -not (Test-Path "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe"))) {
    if ($py) { Say "Found Python $($py.Ver) at $($py.Dir), but it has no tkinter (needed for the status window)." Yellow }
    else { Say "No usable 64-bit Python 3.6 - 3.12 found." Yellow }
    Install-Python
    if ($SimulateNoPython -and $PythonDownloadOnly) { $SimulateNoPython = $false }
    $py2 = Select-Python
    if ($py2) { $py = $py2 }
  }
  if (-not $py) { throw "Python could not be installed automatically. Install Python 3.11 64-bit from https://www.python.org/downloads/windows/ (keep 'tcl/tk' ticked), then run this installer again." }
  Say "Python $($py.Ver): $($py.Dir)" Green
  if (-not $py.Tk) { Say "WARNING: this Python has no tkinter, so the status window cannot open (tally lights still work). Fix: run the Python installer > Modify > tick 'tcl/tk and IDLE'." Yellow }
  $summary["Python"] = "$($py.Ver) $($py.Dir)$(if (-not $py.Tk) { ' (no tkinter: status window disabled)' })"
  $pyExe = Join-Path $py.Dir "python.exe"

  $obsDir = Join-Path $env:APPDATA "obs-studio"
  $scenesDir = Join-Path $obsDir "basic\scenes"
  $wasOpen = $false

  Step "3/6 OBS settings folder"
  if (-not $NoObsControl) { $wasOpen = Close-Obs "so the installer can change its settings" }
  $haveScenes = (Test-Path -LiteralPath $scenesDir) -and @(Get-ChildItem -LiteralPath $scenesDir -Filter *.json -File -ErrorAction SilentlyContinue).Count -gt 0
  $needUserIni = ($obsMajor -ge 31) -and -not (Test-Path -LiteralPath (Join-Path $obsDir "user.ini"))
  if (-not $haveScenes -or $needUserIni) {
    if ($NoObsControl) { throw "OBS has not been run on this profile yet (no scene collection / user.ini in $obsDir) and -NoObsControl is set (cannot start OBS)." }
    Say "OBS has not been set up on this PC yet. Starting OBS once so it creates its settings (it closes again by itself)..." Yellow
    $t0 = Get-Date
    Start-Obs $obsExe
    for ($i = 0; $i -lt 120; $i++) {
      Start-Sleep -Milliseconds 500
      if ((Test-Path -LiteralPath $scenesDir) -and @(Get-ChildItem -LiteralPath $scenesDir -Filter *.json -File -ErrorAction SilentlyContinue).Count -and
          ($obsMajor -lt 31 -or (Test-Path -LiteralPath (Join-Path $obsDir "user.ini")))) { break }
    }
    # let OBS finish starting (closing it too early can hang its shutdown)
    $logDir = Join-Path $obsDir "logs"
    for ($i = 0; $i -lt 60; $i++) {
      $lf = Get-ChildItem -LiteralPath $logDir -Filter *.txt -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
      if ($lf -and (Select-String -LiteralPath $lf.FullName -Pattern "Startup complete" -Quiet)) { break }
      Start-Sleep -Seconds 1
    }
    Start-Sleep -Seconds 8
    [void](Close-Obs "again (first-run setup done)" $true)
    if (-not ((Test-Path -LiteralPath $scenesDir) -and @(Get-ChildItem -LiteralPath $scenesDir -Filter *.json -File).Count)) {
      throw "OBS did not create a scene collection. Open OBS once, close it, then run this installer again."
    }
    Say "OBS settings created." Green
  }
  $active = Get-IniValue (Join-Path $obsDir "user.ini") "Basic" "SceneCollectionFile"
  if (-not $active) { $active = Get-IniValue (Join-Path $obsDir "global.ini") "Basic" "SceneCollectionFile" }
  $cols = @(Get-ChildItem -LiteralPath $scenesDir -Filter *.json -File | ForEach-Object { $_.BaseName })
  Say "Scene collections: $($cols -join ', ')   (active: $active)"

  Step "4/6 Copy the script and set OBS Python path"
  $dest = Join-Path $obsDir "scripts"
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Copy-Item -LiteralPath (Get-Src "obs_hollyland_tally.py") -Destination $dest -Force
  Copy-Item -LiteralPath (Get-Src "tally_window.pyw") -Destination $dest -Force
  Say "Copied to $dest"
  $pyPath = $py.Dir -replace '\\', '/'
  $userIni = Join-Path $obsDir "user.ini"; $globalIni = Join-Path $obsDir "global.ini"
  $targets = @()
  if ($obsMajor -ge 31 -or (Test-Path -LiteralPath $userIni)) { $targets += $userIni }      # OBS 31+: user.ini
  if ($obsMajor -lt 31 -or (Test-Path -LiteralPath $globalIni)) { $targets += $globalIni }  # older OBS: global.ini
  foreach ($ini in $targets) {
    Set-IniValue $ini "Python" "Path64bit" $pyPath
    $chk = Get-IniValue $ini "Python" "Path64bit"
    if ($chk -ne $pyPath) { throw "Could not write the Python path to $ini" }
    Say "Set [Python] Path64bit=$pyPath in $(Split-Path -Leaf $ini)" Green
  }
  $summary["OBS Python path"] = "$pyPath (" + (($targets | ForEach-Object { Split-Path -Leaf $_ }) -join ", ") + ")"

  Step "5/6 Add the script to OBS (Tools > Scripts)"
  $ErrorActionPreference = "Continue"
  & $pyExe (Get-Src "add_to_obs.py") 2>&1 | ForEach-Object { Say "$_" }
  $added = ($LASTEXITCODE -eq 0)
  $ErrorActionPreference = "Stop"
  if (-not $added) { throw "Could not add the script to OBS (see messages above)." }
  $summary["Script added to OBS"] = "OK ($($cols.Count) scene collection(s))"

  Step "6/6 Windows Firewall (incoming TCP $PORT for OBS)"
  $fw = Test-FirewallOk $obsExe
  Say "Firewall check: $fw"
  if ($fw -eq "MISSING" -or $fw -eq "BLOCKED") {
    if ($SkipFirewall) { $summary["Firewall"] = "NEEDS ACTION ($fw) - not changed (-SkipFirewall)" }
    else {
      Say "Windows will ask for permission (UAC) to allow the tally base to reach OBS on port $PORT. Click Yes." Yellow
      if (Fix-Firewall $obsExe) { $fw = Test-FirewallOk $obsExe; if ($fw -eq "UNKNOWN") { $fw = "OK" } }
      if ($fw -eq "OK") { $summary["Firewall"] = "OK (rule 'Hollyland Tally (OBS TCP $PORT)' added)" }
      else { $summary["Firewall"] = "NEEDS ACTION" }
    }
  } elseif ($fw -eq "OFF") { $summary["Firewall"] = "OK (Windows Firewall is off)" }
  elseif ($fw -eq "OK") { $summary["Firewall"] = "OK (OBS is allowed)" }
  else { $summary["Firewall"] = "UNKNOWN (could not read rules)" }
  if ($summary["Firewall"] -notlike "OK*") {
    Say "If the tally base cannot connect: when OBS starts and Windows asks 'Allow access', tick Private AND Public and click Allow." Yellow
    Say "Or: Windows Security > Firewall > Allow an app > obs64 > tick Private and Public (needs admin)." Yellow
  }

  # start OBS again
  $obsStarted = $false
  if (-not $NoObsControl) {
    Say ""; Say "Starting OBS..."
    $t0 = Get-Date
    Start-Obs $obsExe; $obsStarted = $true
    $logDir = Join-Path $obsDir "logs"; $loaded = $null
    for ($i = 0; $i -lt 60 -and $loaded -eq $null; $i++) {
      Start-Sleep -Milliseconds 500
      $lf = Get-ChildItem -LiteralPath $logDir -Filter *.txt -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $t0.AddSeconds(-2) } | Sort-Object LastWriteTime | Select-Object -Last 1
      if ($lf) {
        $txt = Get-Content -LiteralPath $lf.FullName -Raw -ErrorAction SilentlyContinue
        if ($txt -match "Loaded python script: obs_hollyland_tally\.py") { $loaded = $true }
        elseif ($txt -match "\[Python\] Could not load library") { $loaded = $false }
      }
    }
    $summary["Script loaded in OBS"] = $(if ($loaded) { "OK" } elseif ($loaded -eq $false) { "FAILED - see OBS > Tools > Scripts > Script Log" } else { "not confirmed yet (check the status window)" })
  }

  $ips = @(Get-LanIps)
  Write-Host ""
  Write-Host "================ SUMMARY ================" -ForegroundColor Green
  foreach ($k in $summary.Keys) { Write-Host ("{0,-22}: {1}" -f $k, $summary[$k]) }
  Write-Host ""
  Write-Host "On the Hollyland tally base set:" -ForegroundColor Cyan
  Write-Host "   Switcher = vMix,  Switcher IP = one of this PC's IPs below,  Port = $PORT" -ForegroundColor Cyan
  if ($ips) {
    $first = $true
    foreach ($x in $ips) {
      $tag = if ($first -and -not $x.Virt) { "  <- use this one (most likely)" } elseif ($x.Virt) { "  (VPN/virtual - not for the tally base)" } else { "" }
      Write-Host ("   {0,-16} ({1}){2}" -f $x.IP, $x.If, $tag) -ForegroundColor $(if ($first -and -not $x.Virt) { "Green" } else { "White" })
      $first = $false
    }
  }
  else { Write-Host "   (no network address found - connect this PC to the network)" -ForegroundColor Yellow }
  Write-Host "   (NOT the tally base's own IP. The base and this PC must be on the same network.)"
  Write-Host ""
  Write-Host "Until you pick scenes for the lights (OBS > Tools > Scripts > obs_hollyland_tally.py)," -ForegroundColor Gray
  Write-Host "lights 1,2,3,4 follow your first 4 OBS scenes automatically." -ForegroundColor Gray
  Write-Host "Log saved to $log" -ForegroundColor Gray
  if ($script:startedTranscript) { try { Stop-Transcript | Out-Null } catch {} }
  Pause-End
  exit 0
} catch {
  Write-Host ""
  Write-Host "INSTALL FAILED: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host ("  at line {0}" -f $_.InvocationInfo.ScriptLineNumber) -ForegroundColor DarkGray
  Write-Host "Log: $log" -ForegroundColor Gray
  if ($wasOpen -and -not $NoObsControl -and $obsExe -and (Get-ObsProcs).Count -eq 0) { Start-Obs $obsExe }
  if ($script:startedTranscript) { try { Stop-Transcript | Out-Null } catch {} }
  Pause-End
  exit 1
}
