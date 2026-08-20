<#
.SYNOPSIS
  Self-healing guard for the Startup .vbs launchers.

.DESCRIPTION
  The OmniRoute stack starts at login through six .vbs files in the Startup
  folder. If an old or buggy setup script ever rewrites them - e.g. a bare
  "USERPROFILE" (no percent signs) passed to ExpandEnvironmentStrings, or the
  On Error Resume Next / existence-check guard missing - wscript.exe throws
  80070002 "file not found" at Line 2 and pops a "Windows Script Host" dialog
  for every Startup .vbs at every login.

  This script rewrites any Startup .vbs that is missing or does not match the
  hardened template, so those dialogs can never come back. It is invoked from:
    - the OmniRoute-Watchdog scheduled task (every 5 min, real absolute path -
      it keeps working even when EVERY Startup .vbs is broken), and
    - fix-model-cache.ps1 (the logon self-heal, for immediacy).

  Idempotent: healthy files are left untouched (mtime preserved).

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File guard-startup-vbs.ps1
#>
$ErrorActionPreference = 'Continue'
$logFile = Join-Path $HOME '.omniroute\vbs-guard.log'
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
function Log([string]$msg) { Add-Content -Path $logFile -Value "[$stamp] $msg" -Encoding UTF8 }

# Most robust way to locate the Startup folder - the OS resolves it directly,
# no environment-variable expansion involved (immune to the bare-name bug).
$startup = [Environment]::GetFolderPath('Startup')
if (-not $startup -or -not (Test-Path $startup)) {
    Log "ERROR: Startup folder not found: $startup"
    exit 1
}

# Hardened template: On Error Resume Next + %USERPROFILE% + existence check that
# logs to ~\.omniroute\vbs-errors.log instead of ever showing a dialog.
$tpl = @'
On Error Resume Next
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
target = sh.ExpandEnvironmentStrings("%USERPROFILE%") & "<TARGET>"
If fso.FileExists(target) Then
  sh.Run """" & target & """", 0, False
Else
  Set log = fso.OpenTextFile(sh.ExpandEnvironmentStrings("%USERPROFILE%") & "\.omniroute\vbs-errors.log", 8, True)
  log.WriteLine Now & " MISSING: " & target
  log.Close
End If
'@

# Watchdog.vbs uses a different template (90s delay, powershell target).
$wdVbs = @"
' Watchdog.vbs - run the OmniRoute watchdog 90s after logon, fully hidden.
WScript.Sleep 90000
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & sh.ExpandEnvironmentStrings("%USERPROFILE%") & "\.omniroute\watchdog.ps1""", 0, False
"@

$entries = [ordered]@{
    'OmniRoute'     = '\.omniroute\start-omniroute.cmd'
    'FlowUI-Bridge' = '\omniroute-setup-kit\bridge\flow-browser\start-flow-browser.cmd'
    'Gemini-Bridge' = '\omniroute-setup-kit\bridge\gemini-bridge\start-bridge.cmd'
    'MiMo-Bridge'   = '\.omniroute\bridge\mimo-web-bridge\start-bridge.cmd'
    'Meta-Bridge'   = '\.omniroute\bridge\meta-web-bridge\start-bridge.cmd'
    'FixModelCache' = '\omniroute-setup-kit\fix-model-cache.cmd'
}

foreach ($name in $entries.Keys) {
    $path = Join-Path $startup "$name.vbs"
    $raw = ''
    if (Test-Path $path) { $raw = Get-Content $path -Raw }
    # Healthy = hardened template markers present (%USERPROFILE% + log fallback +
    # On Error Resume Next). Anything else (missing, bare-USERPROFILE bug, old
    # template, half-written file) gets rewritten.
    $healthy = ($raw -match '%USERPROFILE%') -and
               ($raw -match 'vbs-errors\.log') -and
               ($raw -match 'On Error Resume Next')
    if (-not $healthy) {
        [System.IO.File]::WriteAllText($path, $tpl.Replace('<TARGET>', $entries[$name]), (New-Object System.Text.UTF8Encoding($false)))
        Log "REPAIRED $name.vbs (was missing or stale template)"
    }
}

$wdPath = Join-Path $startup 'Watchdog.vbs'
$wdRaw = ''
if (Test-Path $wdPath) { $wdRaw = Get-Content $wdPath -Raw }
if ($wdRaw -notmatch '%USERPROFILE%') {
    [System.IO.File]::WriteAllText($wdPath, $wdVbs, (New-Object System.Text.UTF8Encoding($false)))
    Log 'REPAIRED Watchdog.vbs (was missing or stale template)'
}
exit 0
