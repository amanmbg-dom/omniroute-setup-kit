# verify-boot.ps1 - run AFTER a real reboot to confirm the Startup .vbs chain
# started every service silently with no dialogs.
$ErrorActionPreference = 'Continue'
Write-Host "=== POST-REBOOT VERIFICATION $(Get-Date -Format 'HH:mm:ss') ==="

# 1. boot time (must be a fresh boot, not resume)
$os = Get-CimInstance Win32_OperatingSystem
Write-Host "--- 1. boot time: $($os.LastBootUpTime) | now: $(Get-Date)"

# 2. ports (gateway + 3 bridges)
Write-Host "--- 2. ports ---"
foreach ($p in @(20128, 20133, 20134, 20135)) {
    $conn = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue
    if ($conn) { Write-Host "  port $p : UP (pid $($conn[0].OwningProcess))" }
    else { Write-Host "  port $p : DOWN" }
}

# 3. gateway models + routes + combos
Write-Host "--- 3. gateway /v1/models ---"
try {
    $r = Invoke-WebRequest -Uri 'http://127.0.0.1:20128/v1/models' -Headers @{ Authorization = 'Bearer omniroute' } -TimeoutSec 30 -UseBasicParsing
    $models = ($r.Content | ConvertFrom-Json).data
    $ids = $models | ForEach-Object { $_.id }
    Write-Host "  http:$($r.StatusCode) routes:$($ids.Count)"
    foreach ($c in @('qwen','glm','deepseek','lmarena','lmarena-fast','lmarena-slow','mimo','mimo-web')) {
        if ($ids -contains $c) { Write-Host "  combo $c : PRESENT" } else { Write-Host "  combo $c : MISSING" }
    }
} catch { Write-Host "  gateway NOT answering: $($_.Exception.Message)" }

# 4. bridges health
Write-Host "--- 4. bridges ---"
foreach ($b in @(@{n='gflow';p=20133;path='/health'}, @{n='flowui';p=20134;path='/'}, @{n='mimo';p=20135;path='/healthz'})) {
    try {
        $rr = Invoke-WebRequest -Uri "http://127.0.0.1:$($b.p)$($b.path)" -TimeoutSec 6 -UseBasicParsing
        Write-Host "  $($b.n) : http:$($rr.StatusCode)"
    } catch { Write-Host "  $($b.n) : DOWN ($($_.Exception.Message))" }
}

# 5. vbs-errors.log must NOT exist (no missing targets = no dialogs possible)
Write-Host "--- 5. vbs-errors.log ---"
$ve = Join-Path $HOME '.omniroute\vbs-errors.log'
if (Test-Path $ve) { Write-Host "  EXISTS (a vbs target was missing!):"; Get-Content $ve | Select-Object -Last 5 } else { Write-Host "  absent - every Startup vbs resolved its target" }

# 6. logon self-heal (fix-model-cache) must have run after boot
Write-Host "--- 6. fix-model-cache.log ---"
$fl = Join-Path $HOME '.omniroute\fix-model-cache.log'
if (Test-Path $fl) {
    $t = (Get-Item $fl).LastWriteTime
    Write-Host "  last write: $t (boot was $($os.LastBootUpTime))"
    Get-Content $fl | Select-Object -Last 4
} else { Write-Host "  MISSING" }

# 7. watchdog log: runs since boot?
Write-Host "--- 7. watchdog.log tail ---"
$wl = Join-Path $HOME '.omniroute\watchdog.log'
if (Test-Path $wl) { Get-Content $wl | Select-Object -Last 6 } else { Write-Host "  MISSING" }

# 8. no error dialogs: WSH/VBScriptDeprecationAlert events since boot
Write-Host "--- 8. Windows Script Host error events since boot ---"
try {
    $evts = Get-WinEvent -FilterHashtable @{ LogName='Application'; StartTime=$os.LastBootUpTime } -ErrorAction SilentlyContinue |
        Where-Object { $_.ProviderName -match 'VBScriptDeprecationAlert|Windows Script Host' -or $_.Message -match '80070002|Script Host' }
    if ($evts) { $evts | Select-Object -First 6 TimeCreated, ProviderName, Id | Format-Table -AutoSize } else { Write-Host "  none - no script-host error dialogs" }
} catch { Write-Host "  (could not read event log)" }

# 9. no malware processes
Write-Host "--- 9. malware check (wscript/uusd/xedaniwo) ---"
$bad = Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'wscript.exe' -or $_.Name -eq 'uusd.exe' -or $_.CommandLine -match 'nudeluba|xedaniwo' }
if ($bad) { $bad | Select-Object ProcessId, Name, CommandLine | Format-List } else { Write-Host "  clean" }

# 10. zai captcha worker still headed (zai works)
Write-Host "--- 10. zai captcha worker ---"
$zp = "$env:APPDATA\npm\node_modules\omniroute\dist\.build\next\server\zai-captcha-worker.js"
if (Test-Path $zp) {
    $s = Get-Content $zp -Raw
    $i = $s.IndexOf('headless')
    Write-Host "  $($s.Substring($i, 18))"
} else { Write-Host "  worker file missing" }

# 11. claude picker patch still applied
Write-Host "--- 11. claude picker patch ---"
$cp = "$env:USERPROFILE\.claude\cache\gateway-models.json"
if (Test-Path $cp) {
    $m = (Get-Content $cp -Raw | ConvertFrom-Json)
    Write-Host "  cache exists, entries: $(@($m).Count)"
} else { Write-Host "  cache missing (will be rebuilt at first use)" }

Write-Host "=== END VERIFICATION ==="
