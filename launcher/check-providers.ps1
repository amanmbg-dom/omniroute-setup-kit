<#
.SYNOPSIS
  Provider health check - surfaces stale web-session cookies and dead
  connections so the kit (and you) know exactly what needs refreshing.

.DESCRIPTION
  Reads the gateway's own connection tests (/api/providers) and the local
  bridge health, then writes ~/.omniroute/provider-health.txt with a status
  table and the exact fix for every problem (log in at X, then Cookie Pusher
  -> Grab & push sessions). Run from the OmniRoute-Watchdog task every 5 min
  (hidden, no console window); it logs to watchdog.log ONLY when the health
  state CHANGES, so a dead session is noticed once and recovery is noticed
  once. Also safe to run manually any time.

  The web-session ("unlim") providers are called out by name because they die
  silently - the route stays in the /model picker but every request fails
  (lmarena "User not found", mimo-web "No MiMo session cookie", claude-web
  400, chatgpt-web 502 rate limit...). A pushed cookie refreshes the bridge
  on the next request; lmarena/claude need a fresh login + push.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File check-providers.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File check-providers.ps1 -Base http://127.0.0.1:20128
#>
param(
    [string]$Base = 'http://127.0.0.1:20128'
)
$ErrorActionPreference = 'Continue'

$stateFile = Join-Path $HOME '.omniroute\provider-health.txt'
$stateHashFile = Join-Path $HOME '.omniroute\.provider-health-state.txt'
$wdLog = Join-Path $HOME '.omniroute\watchdog.log'
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

function Add-WdLog([string]$msg) {
    try { Add-Content -Path $wdLog -Value "[$stamp] $msg" -Encoding UTF8 } catch {}
}

# Admin token: the Cookie Pusher's per-machine key, else the localhost magic token.
$token = 'omniroute'
$extConfig = Join-Path $HOME 'omniroute-cookie-pusher\config.js'
if (Test-Path $extConfig) {
    $cfg = Get-Content $extConfig -Raw
    if ($cfg -match "DEFAULT_API_KEY\s*=\s*'([^']+)'") { $token = $Matches[1] }
}

$lines = @()
$bad = @()

function Test-Port([int]$port, [string]$path) {
    try {
        $null = Invoke-WebRequest -Uri "http://127.0.0.1:$port$path" -TimeoutSec 4 -UseBasicParsing
        return $true
    } catch {
        if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -lt 500) { return $true }
        return $false
    }
}

# ---- 1. gateway connections ----
$conns = @()
try {
    $r = Invoke-RestMethod -Uri "$Base/api/providers" -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 30
    $conns = @($r.connections)
} catch {
    $lines += "GATEWAY  BAD   /api/providers unreachable: $($_.Exception.Message)"
    $bad += 'gateway-api'
}

# Unlim web-session families -> what to do when they break.
$fixHints = @{
    'arena'        = "SESSION EXPIRED - log in at lmarena.ai (chat.lmsys.org), then Cookie Pusher -> Grab & push sessions"
    'mimo'         = "NO SESSION - sign in at aistudio.xiaomimimo.com, then Cookie Pusher -> Grab & push sessions"
    'claude web'   = "REFRESH - log in at claude.ai, then Cookie Pusher -> Grab & push sessions"
    'chatgpt'      = "RATE LIMITED (transient) - retry later or push another account via Cookie Pusher"
    'qwen'         = "REFRESH - log in at chat.qwen.ai, then Cookie Pusher -> Grab & push sessions"
    'z.ai glm'     = "REFRESH - log in at z.ai, then Cookie Pusher -> Grab & push sessions"
    'deepseek web' = "REFRESH - log in at chat.deepseek.com, then Cookie Pusher -> Grab & push sessions"
    'gemini web'   = "REFRESH - log in at gemini.google.com, then Cookie Pusher -> Grab & push sessions"
    'huggingchat'  = "REFRESH - log in at huggingface.co/chat, then Cookie Pusher -> Grab & push sessions"
    't3.chat'      = "REFRESH - log in at t3.chat, then Cookie Pusher -> Grab & push sessions"
}

function Get-FixHint([string]$name) {
    $n = $name.ToLowerInvariant()
    foreach ($k in $fixHints.Keys) { if ($n -like "*$k*") { return $fixHints[$k] } }
    return $null
}

foreach ($c in $conns) {
    $name = if ($c.name) { $c.name } else { $c.provider }
    $status = if ($c.testStatus) { $c.testStatus } else { 'unknown' }
    $err = if ($c.errorCode) { $c.errorCode } else { '' }
    $errType = if ($c.lastErrorType) { $c.lastErrorType } else { '' }
    $lastErr = if ($c.lastErrorAt) { $c.lastErrorAt } else { '' }
    $hint = Get-FixHint $name

    $problem = ($status -eq 'error') -or ($status -eq 'failed') -or ($err -and $err -ne 'none') -or (-not $c.isActive)
    # 'unknown' with an upstream error (e.g. mimo bridge before a session is
    # pushed) is a problem; plain 'unknown' with no error is just untested.
    if (-not $problem -and $status -eq 'unknown' -and $err) { $problem = $true }
    # The two inactive "amanmbgcard..." connections are stale duplicates - only
    # flag when they are active-but-erroring.
    if (-not $c.isActive -and $name -match '@') { $problem = $false }

    if ($problem) {
        $fix = if ($hint) { "FIX: $hint" } elseif ($err -eq 'auth_failed') { 'FIX: API key rejected - re-add/rotate it' } else { 'FIX: check the connection (re-add or refresh credentials)' }
        $lines += ("{0,-22} BAD   {1} (last error {2}) - {3}" -f $name, ($err + ' ' + $errType).Trim(), $lastErr, $fix)
        $bad += $name
    } else {
        $inactive = if (-not $c.isActive) { ' (inactive)' } else { '' }
        $lines += ("{0,-22} OK    test={1}{2}" -f $name, $status, $inactive)
    }
}

# ---- 1.5. live chat probes (self-throttled: at most every 30 min) ----
# The gateway's connection test can report "active" while the session is
# actually dead (lmarena/arena 401 "User not found" only surfaces at chat
# time). Probe the unlim combo routes for real, but never more often than
# every 30 min so the 5-min watchdog run stays light. A "OK" needs an actual
# completion; a timeout counts as BAD so a wedged provider is noticed too.
$liveFile = Join-Path $HOME '.omniroute\.provider-health-live.txt'
$doLive = $true
if (Test-Path $liveFile) {
    try {
        $lastLive = [DateTime]::ParseExact((Get-Content $liveFile -Raw).Trim(), 'yyyy-MM-dd HH:mm:ss', $null)
        if (((Get-Date) - $lastLive).TotalMinutes -lt 30) { $doLive = $false }
    } catch { }
}
$liveLines = @()
$liveBad = @()
$liveRoutes = @('combo/qwen', 'combo/glm', 'combo/deepseek', 'combo/lmarena', 'combo/mimo', 'combo/mimo-web', 'gemini-web/gemini-3.1-pro', 'chatgpt-web/gpt-5.6-pro', 'claude-web/claude-opus-5')
if ($doLive) {
    foreach ($m in $liveRoutes) {
        $body = @{ model = $m; messages = @(@{ role = 'user'; content = 'Reply with exactly: PING' }); max_tokens = 8; stream = $false } | ConvertTo-Json -Depth 6
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $resp = Invoke-RestMethod -Uri "$Base/v1/chat/completions" -Method Post `
                -Headers @{ Authorization = 'Bearer omniroute' } -ContentType 'application/json' -Body $body -TimeoutSec 30
            $sw.Stop()
            $content = ($resp.choices[0].message.content -join '').Trim()
            $ok = ($content -match 'PING|PONG')
            if ($ok) { $liveLines += ("{0,-22} OK    live probe {1}s (reply: {2})" -f $m, [math]::Round($sw.Elapsed.TotalSeconds, 1), ($content.Substring(0, [Math]::Min(16, $content.Length)))) }
            else { $liveLines += ("{0,-22} BAD   live probe answered but no content ({1}s) - session may be degraded" -f $m, [math]::Round($sw.Elapsed.TotalSeconds, 1)); $bad += $m; $liveBad += $m }
        } catch {
            $sw.Stop()
            $msg = $_.Exception.Message
            if ($msg -match 'No MiMo session cookie') { $msg = '401 No MiMo session cookie - sign in at aistudio.xiaomimimo.com, then push via Cookie Pusher' }
            elseif ($msg -match 'User not found') { $msg = '401 User not found - lmarena session expired: log in at lmarena.ai, then push via Cookie Pusher' }
            elseif ($msg -match 'hit your limit') { $msg = '502 rate limited (transient)' }
            elseif ($msg -match 'Claude Web API error') { $msg = '400 Claude Web API error - refresh the claude.ai session via Cookie Pusher' }
            $liveLines += ("{0,-22} BAD   live probe failed ({1}s): {2}" -f $m, [math]::Round($sw.Elapsed.TotalSeconds, 1), $msg)
            $bad += $m
            $liveBad += $m
        }
    }
    try { [System.IO.File]::WriteAllText($liveFile, (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), (New-Object System.Text.UTF8Encoding($false))) } catch { }
}

# ---- 2. local bridges + mimo cookie file ----
if (Test-Port 20133 '/health') { $lines += 'gemini bridge    OK    port 20133' } else { $lines += 'gemini bridge    BAD   port 20133 down - fix-model-cache.ps1/watchdog restarts it; re-run setup.ps1 if persistent'; $bad += 'gemini-bridge' }
if (Test-Port 20134 '/')      { $lines += 'flowui bridge    OK    port 20134' } else { $lines += 'flowui bridge    BAD   port 20134 down - re-run setup.ps1 if persistent'; $bad += 'flowui-bridge' }
if (Test-Port 20135 '/healthz') { $lines += 'mimo-web bridge  OK    port 20135' } else { $lines += 'mimo-web bridge  BAD   port 20135 down - watchdog restarts it; re-run setup.ps1 if persistent'; $bad += 'mimo-bridge' }

$mimoCookie = Join-Path $HOME '.omniroute\mimo-cookies.json'
if (Test-Path $mimoCookie) {
    $ageH = [math]::Round(((Get-Date) - (Get-Item $mimoCookie).LastWriteTime).TotalHours, 1)
    $lines += "mimo session     OK    cookie file present ($ageH h old)"
} else {
    $lines += 'mimo session     BAD   no ~/.omniroute/mimo-cookies.json - sign in at aistudio.xiaomimimo.com, then Cookie Pusher -> Grab & push sessions'
    $bad += 'mimo-session'
}

# ---- 3. write state + log on change ----
# Two hashes: the STABLE body (connection tests + bridges + cookie file) and
# the LIVE body (throttled chat probes). Each logs only on its own change, so
# the 30-min live-probe cycle does not churn the watchdog log.
function Get-Md5([string]$s) {
    return [System.BitConverter]::ToString([System.Security.Cryptography.MD5]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($s))).Replace('-', '')
}
$stableBody = $lines -join "`n"
$prevHash = ''
if (Test-Path $stateHashFile) { $prevHash = (Get-Content $stateHashFile -Raw).Trim() }
$newHash = Get-Md5 $stableBody
$changed = ($newHash -ne $prevHash)
if ($changed) { try { [System.IO.File]::WriteAllText($stateHashFile, $newHash, (New-Object System.Text.UTF8Encoding($false))) } catch {} }

$liveStateHashFile = Join-Path $HOME '.omniroute\.provider-health-live-state.txt'
$liveChanged = $false
if ($doLive) {
    $prevLiveHash = ''
    if (Test-Path $liveStateHashFile) { $prevLiveHash = (Get-Content $liveStateHashFile -Raw).Trim() }
    $newLiveHash = Get-Md5 ($liveLines -join "`n")
    $liveChanged = ($newLiveHash -ne $prevLiveHash)
    if ($liveChanged) { try { [System.IO.File]::WriteAllText($liveStateHashFile, $newLiveHash, (New-Object System.Text.UTF8Encoding($false))) } catch {} }
}

$bad = @($bad | Select-Object -Unique)
$out = @()
$out += "OmniRoute provider health - $stamp (gateway $Base)"
$out += ''
$out += $lines
if ($liveLines.Count -gt 0) {
    $out += ''
    $out += '--- live chat probes (unlim routes) ---'
    $out += $liveLines
}
$out += ''
if ($bad.Count -gt 0) {
    $out += "PROBLEMS: $($bad.Count) - $($bad -join ', ')"
    $out += 'Refresh sessions: open each site, confirm you are signed in, then Cookie Pusher -> Grab & push sessions (auto-refresh ON pushes every few hours while the browser runs).'
} else {
    $out += 'ALL HEALTHY - every provider connection is active and the bridges are up.'
}
try {
    [System.IO.File]::WriteAllText($stateFile, ($out -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
} catch {}

if ($changed) {
    if ($bad.Count -gt 0) {
        Add-WdLog "PROVIDER HEALTH CHANGED: problems - $($bad -join ', ') (details: $stateFile)"
    } else {
        Add-WdLog 'PROVIDER HEALTH CHANGED: all providers healthy'
    }
}
if ($liveChanged) {
    $liveBadD = @($liveBad | Select-Object -Unique)
    if ($liveBadD.Count -gt 0) {
        Add-WdLog "LIVE PROBE STATE CHANGED: problems - $($liveBadD -join ', ')"
    } else {
        Add-WdLog 'LIVE PROBE STATE CHANGED: all unlim routes healthy'
    }
}

# ---- 4. console output (manual runs) ----
$out | ForEach-Object { Write-Host $_ }
if ($bad.Count -gt 0) { exit 1 }
exit 0
