<#
.SYNOPSIS
  Point Claude Code (CLI + Desktop Code tab) at the remote OmniRoute VPS.
.DESCRIPTION
  Reads ~/.omniroute/remote.env (written by setup-vps.sh). Health-checks the
  tunnel URL; if the gateway is down it SSH-starts the systemd service, waits
  for it, then rewrites ~/.claude/settings.json env vars to the VPS and prints
  the API key. Run omni-local.ps1 to switch back to the local gateway.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File "$HOME\.omniroute\omni-remote.ps1"
#>
$ErrorActionPreference = 'Stop'
$envFile = Join-Path $HOME '.omniroute\remote.env'

if (-not (Test-Path $envFile)) {
    Write-Host "remote.env not found at $envFile" -ForegroundColor Red
    Write-Host "Run setup-vps.sh on the VPS first, then copy ~/.omniroute/remote.env here."
    exit 1
}

# ---- parse remote.env (KEY=VALUE, # comments) ----
$cfg = @{}
foreach ($line in Get-Content $envFile) {
    if ($line -match '^\s*#') { continue }
    if ($line -match '^\s*([A-Z0-9_]+)=(.*)$') { $cfg[$Matches[1]] = $Matches[2].Trim() }
}

$tunnel = $cfg['TUNNEL_URL'].TrimEnd('/')
$apiKey = $cfg['API_KEY']
$sshUser = if ($cfg['SSH_USER']) { $cfg['SSH_USER'] } else { 'ubuntu' }
$sshHost = $cfg['SSH_HOST']
if (-not $tunnel -or -not $apiKey) {
    Write-Host 'remote.env missing TUNNEL_URL or API_KEY - re-run setup-vps.sh' -ForegroundColor Red
    exit 1
}

$health = "$tunnel/v1/models"
Write-Host "Checking gateway: $health" -ForegroundColor Cyan

function Test-Remote([int]$tries = 15) {
    for ($i = 0; $i -lt $tries; $i++) {
        try {
            $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 8 -Headers @{ Authorization = "Bearer $apiKey" } -Uri $health
            if ($r.StatusCode -eq 200) { return $true }
        } catch { }
        Start-Sleep -Seconds 4
    }
    return $false
}

$up = Test-Remote 3
if (-not $up) {
    if (-not $sshHost) {
        Write-Host 'Gateway unreachable and SSH_HOST is empty in remote.env - set it first.' -ForegroundColor Red
        exit 1
    }
    Write-Host "Gateway down - starting it via SSH ($sshUser@$sshHost) ..." -ForegroundColor Yellow
    ssh "$sshUser@$sshHost" "sudo systemctl start omniroute" 2>&1 | Out-Host
    $up = Test-Remote 15
}
if (-not $up) {
    Write-Host "Gateway still unreachable after start. Check on the VPS: journalctl -u omniroute -n 50" -ForegroundColor Red
    exit 1
}
Write-Host 'Gateway is UP.' -ForegroundColor Green

# ---- rewrite ~/.claude/settings.json (no BOM, like the kit does) ----
$ccFile = Join-Path $HOME '.claude\settings.json'
New-Item -ItemType Directory -Force -Path (Split-Path $ccFile) | Out-Null
if (Test-Path $ccFile) {
    Copy-Item $ccFile "$ccFile.bak-local" -Force
    $cc = Get-Content $ccFile -Raw | ConvertFrom-Json
} else {
    $cc = [pscustomobject]@{}
}
if (-not $cc.env) { $cc | Add-Member -NotePropertyName env -NotePropertyValue ([pscustomobject]@{}) -Force }
$cc.env | Add-Member -NotePropertyName 'ANTHROPIC_BASE_URL' -NotePropertyValue "$tunnel" -Force
$cc.env | Add-Member -NotePropertyName 'ANTHROPIC_AUTH_TOKEN' -NotePropertyValue "$apiKey" -Force
# Gateway model discovery: make the /model picker show the full gateway catalog.
$cc.env | Add-Member -NotePropertyName 'CLAUDE_CODE_USE_GATEWAY' -NotePropertyValue 'true' -Force
$cc.env | Add-Member -NotePropertyName 'CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY' -NotePropertyValue 'true' -Force
$json = $cc | ConvertTo-Json -Depth 12
[System.IO.File]::WriteAllText($ccFile, $json, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ''
Write-Host '  Claude Code now points at the VPS provider farm:' -ForegroundColor Green
Write-Host "    BASE_URL : $tunnel"
Write-Host "    API KEY  : $apiKey   (keep private)"
Write-Host ''
Write-Host '  Restart Claude Code / the Desktop Code tab for it to take effect.' -ForegroundColor Cyan
Write-Host '  To switch back to the local gateway:  omni-local.ps1' -ForegroundColor DarkGray
