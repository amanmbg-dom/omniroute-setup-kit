<#
.SYNOPSIS
  OmniRoute gateway + bridge watchdog - keeps the local stack answering.

.DESCRIPTION
  The gateway occasionally wedges: the port keeps LISTENING but HTTP requests
  hang forever (CLOSE_WAIT sockets pile up, /v1/models stops answering). This
  watchdog detects that state and restarts the gateway the kit way (launcher),
  then re-syncs the per-family combo/* routes so the model pickers stay
  complete. It also starts the gateway if it is not running at all, and keeps
  the three web bridges (gflow, flowui, mimo-web) alive. Every restart is
  started hidden (no console windows).

  Run it from a scheduled task every 5 minutes AND at logon (registered by
  setup.ps1).

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File watchdog.ps1
#>
param(
    [string]$Base = 'http://127.0.0.1:20128',
    [string]$Port = '20128',
    [string]$MagicToken = 'omniroute'
)
$ErrorActionPreference = 'Continue'
$logFile = Join-Path $HOME '.omniroute\watchdog.log'

# rotate the log when it outgrows 1MB (keep the last run in .old)
if ((Test-Path $logFile) -and ((Get-Item $logFile).Length -gt 1MB)) {
    Remove-Item "$logFile.old" -Force -ErrorAction SilentlyContinue
    Rename-Item $logFile "$logFile.old" -Force -ErrorAction SilentlyContinue
}

$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

function Log([string]$msg) {
    $line = "[$stamp] $msg"
    Add-Content -Path $logFile -Value $line -Encoding UTF8
    Write-Host $line -ForegroundColor DarkGray
}

# ---- 0.1. self-healing Startup .vbs guard ----
# If an old/buggy setup script ever rewrites the Startup .vbs launchers (bare
# USERPROFILE instead of %USERPROFILE% -> 80070002 dialogs at every login),
# repair them from the hardened template. This runs from the scheduled task
# (real absolute path), so it keeps working even when EVERY Startup .vbs is
# broken. Healthy files are untouched (idempotent).
$guardScript = $null
foreach ($cand in @(
    (Join-Path $PSScriptRoot 'guard-startup-vbs.ps1'),
    (Join-Path $HOME '.omniroute\guard-startup-vbs.ps1'),
    (Join-Path $HOME 'omniroute-setup-kit\guard-startup-vbs.ps1')
)) { if (Test-Path $cand) { $guardScript = $cand; break } }
if ($guardScript) {
    # NB: -WindowStyle Hidden is REQUIRED - this task runs every 5 min and any
    # nested powershell without it flashes a console window on the desktop.
    & powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $guardScript 2>&1 | Out-Null
} else {
    Log 'WARN: guard-startup-vbs.ps1 not found - Startup .vbs not self-repaired'
}

function Wait-ForGateway([int]$Seconds) {
    for ($i = 0; $i -lt $Seconds; $i++) {
        Start-Sleep -Seconds 1
        try {
            $r = Invoke-WebRequest -Uri "$Base/v1/models" -Headers @{ Authorization = "Bearer $MagicToken" } -TimeoutSec 4 -UseBasicParsing
            if ($r.StatusCode -eq 200) { return $true }
        } catch { }
    }
    return $false
}

# ---- 0.5. proactive memory restart ----
# The gateway has repeatedly wedged (listening but stalled) with the event loop
# stuck under memory pressure. If the listener's working set has climbed near the
# 6GB heap ceiling, restart it now - a 1-2min blip is cheaper than a hard stall.
$rssLimitMb = 5120
$listener = Get-NetTCPConnection -LocalPort ([int]$Port) -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($listener) {
    try {
        $proc = Get-Process -Id $listener.OwningProcess -ErrorAction Stop
        $rssMb = [math]::Round($proc.WorkingSet64 / 1MB)
        if ($rssMb -gt $rssLimitMb) {
            Log "WARN: gateway RSS ${rssMb}MB > ${rssLimitMb}MB - restarting proactively before it wedges"
            Stop-Process -Id $listener.OwningProcess -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
        }
    } catch { }
}

# ---- 0.7. /model picker self-heal (every run, not only after restarts) ----
# Claude Code auto-updates replace the native binary and revert the picker
# patch; the logon script only re-applies it at logon, so a mid-day update
# used to leave the /model picker filtered until the next reboot. Run the
# cheap picker-only heal now (fix-model-cache.ps1 -PickerOnly): it re-patches
# BOTH gateway-discovery filter sites in the VS Code extension binary AND the
# standalone ~/.local/bin/claude.exe CLI, and re-ensures the discovery env
# vars. Idempotent; if a claude.exe session is running the binary is locked
# and the patch lands on a later run, within 5 minutes of the session closing.
$fix = $null
foreach ($cand in @(
    (Join-Path $PSScriptRoot '..\fix-model-cache.ps1'),
    (Join-Path $HOME 'omniroute-setup-kit\fix-model-cache.ps1'),
    (Join-Path $HOME '.omniroute\fix-model-cache.ps1')
)) { if (Test-Path $cand) { $fix = $cand; break } }
if ($fix) {
    $fixLog = Join-Path $HOME '.omniroute\fix-model-cache.log'
    # NB: *>> would append UTF-16, garbling the log when mixed with the .cmd's
    # ANSI/UTF-8 output - pipe through Out-File -Append -Encoding utf8 instead.
    # -WindowStyle Hidden is REQUIRED - a visible powershell would flash a
    # console window every 5 min on the interactive desktop.
    & powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $fix -Base $Base -PickerOnly 2>&1 | Out-File -FilePath $fixLog -Append -Encoding utf8
    Log 'picker self-heal run (fix-model-cache.ps1 -PickerOnly)'
} else {
    Log 'WARN: fix-model-cache.ps1 not found - /model picker patch not re-applied'
}

# ---- 0.8. provider health check (every run) ----
# Surf the gateway's own connection tests: when a web-session provider's
# cookie dies (lmarena/arena 401 "User not found", mimo-web missing session,
# claude-web 400s, ...) the route stays in the picker but every call fails.
# check-providers.ps1 writes ~/.omniroute/provider-health.txt with a status
# table + the exact fix for each stale session, and logs to THIS file only
# when the state CHANGES (no 5-min spam). Runs hidden - no console windows.
$check = $null
foreach ($cand in @(
    (Join-Path $PSScriptRoot 'check-providers.ps1'),
    (Join-Path $HOME 'omniroute-setup-kit\launcher\check-providers.ps1'),
    (Join-Path $HOME '.omniroute\check-providers.ps1')
)) { if (Test-Path $cand) { $check = $cand; break } }
if ($check) {
    & powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $check -Base $Base 2>&1 | Out-Null
} else {
    Log 'WARN: check-providers.ps1 not found - provider health not tracked'
}

# ---- 1. probe ----
$probeOk = $false
try {
    $r = Invoke-WebRequest -Uri "$Base/v1/models" -Headers @{ Authorization = "Bearer $MagicToken" } -TimeoutSec 8 -UseBasicParsing
    $probeOk = ($r.StatusCode -eq 200)
} catch { $probeOk = $false }

if (-not $probeOk) {
    # ---- 2-4. gateway recovery (only when the probe failed) ----
    Log "WARN: gateway not answering $Base/v1/models (http probe failed) - checking port"

    $listeningPid = $null
    try {
        $conns = Get-NetTCPConnection -LocalPort ([int]$Port) -State Listen -ErrorAction SilentlyContinue
        if ($conns) { $listeningPid = ($conns | Select-Object -First 1).OwningProcess }
    } catch { $listeningPid = $null }

    # The package's `omniroute.mjs serve` runs a SUPERVISOR that respawns the
    # real server (server-ws.mjs) within ~2s whenever it dies, so the normal
    # recovery path is: kill the wedged listener and let the supervisor respawn
    # it. Only if no supervisor is alive do we (re)start the launcher ourselves.
    if ($listeningPid) {
        # A freshly restarted gateway cold-starts for up to ~60s before it answers
        # HTTP, so give a listener a grace period before calling it wedged - only
        # kill when it has stayed unresponsive for 60s straight.
        Log "port $Port is LISTENING (pid $listeningPid) but not answering HTTP - giving it 60s grace (cold start), then killing if still stuck"
        if (Wait-ForGateway 60) {
            Log "gateway answered within grace period - was cold-starting ($Base)"
        } else {
            Log 'still not answering after 60s - killing the wedged process'
            try { Stop-Process -Id $listeningPid -Force -ErrorAction Stop } catch { Log "  kill failed: $($_.Exception.Message)" }
            Log 'waiting for the package supervisor to respawn the server (up to 45s)...'
            if (Wait-ForGateway 45) {
                Log "gateway recovered via supervisor respawn ($Base)"
            } else {
                Log 'supervisor did not bring it back - starting the launcher'
            }
        }
    } else {
        Log "port $Port not listening - gateway is down"
        if (-not (Wait-ForGateway 10)) {
            Log 'still down - starting the launcher'
        }
    }

    # start it via the launcher only if still down
    if (-not (Wait-ForGateway 3)) {
        $launcher = $null
        foreach ($cand in @(
            (Join-Path $PSScriptRoot 'start-omniroute.cmd'),
            (Join-Path $HOME '.omniroute\start-omniroute.cmd'),
            (Join-Path $HOME 'omniroute-setup-kit\launcher\start-omniroute.cmd')
        )) { if (Test-Path $cand) { $launcher = $cand; break } }
        if (-not $launcher) {
            Log 'ERROR: start-omniroute.cmd launcher not found - cannot restart'
            exit 1
        }
        Log "starting gateway via $launcher"
        try {
            Start-Process -FilePath 'cmd.exe' -ArgumentList "/c `"$launcher`"" -WindowStyle Hidden
        } catch {
            Log "  start failed: $($_.Exception.Message)"
        }
    }

    if (-not (Wait-ForGateway 60)) {
        Log 'ERROR: gateway did not come back within 60s - check the gateway log'
    } else {
        Log "gateway is back up ($Base)"
    }

    # ---- 5. re-sync the combo/* routes (management-API state) so the pickers
    #        show the full route list again - fast mode, no picker patch ----
    if (Wait-ForGateway 3) {
        $fix = $null
        foreach ($cand in @(
            (Join-Path $PSScriptRoot '..\fix-model-cache.ps1'),
            (Join-Path $HOME 'omniroute-setup-kit\fix-model-cache.ps1'),
            (Join-Path $HOME '.omniroute\fix-model-cache.ps1')
        )) { if (Test-Path $cand) { $fix = $cand; break } }
        if ($fix) {
            Log "re-syncing combo/* routes (fix-model-cache.ps1 -CombosOnly)"
            # -WindowStyle Hidden is REQUIRED - this runs from the interactive
            # scheduled task and a visible powershell would flash a console.
            & powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $fix -Base $Base -CombosOnly 2>&1 | Out-Null
            Log 'combo re-sync done'
        } else {
            Log 'WARN: fix-model-cache.ps1 not found - combo/* routes not re-synced'
        }
    }
}

# ---- 6. bridge health - ALWAYS checked (even when the gateway is healthy).
#        Each bridge is a local OpenAI-compatible server; if its port is down,
#        start it hidden (no console window) via its launcher. The launchers
#        resolve their own paths and stay up as long as the bridge runs.
function Test-Port([int]$port, [string]$path) {
    try {
        $null = Invoke-WebRequest -Uri "http://127.0.0.1:$port$path" -TimeoutSec 4 -UseBasicParsing
        return $true  # any HTTP status (404/200) means something is listening
    } catch {
        # 404 from the bridge root still counts as alive; connection refused does not
        if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -lt 500) { return $true }
        return $false
    }
}

function Start-HiddenCmd([string]$cmdPath) {
    try {
        Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', "`"$cmdPath`"") -WindowStyle Hidden
        return $true
    } catch {
        Log "  start failed: $($_.Exception.Message)"
        return $false
    }
}

$bridges = @(
    @{ Name = 'gflow (gemini-bridge)';  Port = 20133; Path = '/health';  Launchers = @((Join-Path $HOME 'omniroute-setup-kit\bridge\gemini-bridge\start-bridge.cmd'), (Join-Path $HOME '.omniroute\bridge\gemini-bridge\start-bridge.cmd')) },
    @{ Name = 'flowui (flow-browser)';  Port = 20134; Path = '/';        Launchers = @((Join-Path $HOME 'omniroute-setup-kit\bridge\flow-browser\start-flow-browser.cmd'), (Join-Path $HOME '.omniroute\bridge\flow-browser\start-flow-browser.cmd')) },
    @{ Name = 'mimo-web';               Port = 20135; Path = '/healthz'; Launchers = @((Join-Path $HOME '.omniroute\bridge\mimo-web-bridge\start-bridge.cmd'), (Join-Path $HOME 'omniroute-setup-kit\bridge\mimo-web-bridge\start-bridge.cmd')) }
)
foreach ($b in $bridges) {
    if (Test-Port $b.Port $b.Path) { continue }  # healthy - nothing to do
    $launcher = $null
    foreach ($cand in $b.Launchers) { if (Test-Path $cand) { $launcher = $cand; break } }
    if (-not $launcher) {
        Log "WARN: $($b.Name) down on port $($b.Port) but no launcher found - re-run setup.ps1"
        continue
    }
    Log "$($b.Name) down on port $($b.Port) - starting hidden via $launcher"
    if (Start-HiddenCmd $launcher) {
        Start-Sleep -Seconds 5
        if (Test-Port $b.Port $b.Path) { Log "$($b.Name) is back up" }
        else { Log "$($b.Name) still not answering after start - check its log under ~/.omniroute" }
    }
}
exit 0
