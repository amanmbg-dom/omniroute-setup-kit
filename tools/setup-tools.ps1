# setup-tools.ps1 — Wire OmniRoute Tools into Claude Code and deploy bridges
# Run this after setup.ps1 or manually to add the tools layer.

param(
    [string]$KitDir = "$HOME\omniroute-setup-kit",
    [string]$DataDir = "$HOME\.omniroute"
)

$ErrorActionPreference = 'Continue'

Write-Host "`n=== OmniRoute Tools Setup ===" -ForegroundColor Cyan

# 1. Copy tools to deployed location
$toolsSrc = Join-Path $KitDir 'tools'
$toolsDst = Join-Path $DataDir 'tools'
if (Test-Path $toolsSrc) {
    if (-not (Test-Path $toolsDst)) { New-Item -ItemType Directory -Path $toolsDst -Force | Out-Null }
    Copy-Item "$toolsSrc\*" $toolsDst -Recurse -Force
    Write-Host "Tools copied to $toolsDst" -ForegroundColor Green
}

# 2. Copy meta-web-bridge to deployed location
$metaSrc = Join-Path $KitDir 'bridge\meta-web-bridge'
$metaDst = Join-Path $DataDir 'bridge\meta-web-bridge'
if (Test-Path $metaSrc) {
    if (-not (Test-Path $metaDst)) { New-Item -ItemType Directory -Path $metaDst -Force | Out-Null }
    Copy-Item "$metaSrc\*" $metaDst -Recurse -Force
    Write-Host "Meta Web Bridge copied to $metaDst" -ForegroundColor Green
}

# 3. Wire MCP server into Claude Code settings
$settingsFile = "$HOME\.claude\settings.json"
if (Test-Path $settingsFile) {
    $settings = Get-Content $settingsFile -Raw | ConvertFrom-Json
    
    # Ensure mcpServers exists
    if (-not $settings.mcpServers) {
        $settings | Add-Member -NotePropertyName 'mcpServers' -NotePropertyValue @{} -Force
    }
    
    $toolsPath = Join-Path $toolsDst 'omniroute-tools.mjs'
    
    # Add omniroute-tools MCP server
    $mcpConfig = @{
        command = "node"
        args = @($toolsPath)
    }
    
    if (-not $settings.mcpServers.'omniroute-tools') {
        $settings.mcpServers | Add-Member -NotePropertyName 'omniroute-tools' -NotePropertyValue $mcpConfig -Force
        $json = $settings | ConvertTo-Json -Depth 12
        [System.IO.File]::WriteAllText($settingsFile, $json, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "MCP server 'omniroute-tools' added to Claude Code settings" -ForegroundColor Green
    } else {
        Write-Host "MCP server 'omniroute-tools' already configured" -ForegroundColor DarkGray
    }
} else {
    Write-Host "Claude Code settings not found — MCP server not wired" -ForegroundColor Yellow
}

# 4. Create bridges.json if it doesn't exist
$bridgesFile = Join-Path $DataDir 'bridges.json'
if (-not (Test-Path $bridgesFile) -and (Test-Path "$toolsSrc\bridges.json")) {
    Copy-Item "$toolsSrc\bridges.json" $bridgesFile
    Write-Host "bridges.json created at $bridgesFile" -ForegroundColor Green
}

# 5. Add Meta Web Bridge to watchdog bridge health checks
$watchdogFile = Join-Path $DataDir 'watchdog.ps1'
if (Test-Path $watchdogFile) {
    $wd = Get-Content $watchdogFile -Raw
    if ($wd -notmatch 'meta-web') {
        Write-Host "Note: Add Meta Web Bridge to watchdog.ps1 bridges array (port 20136)" -ForegroundColor Yellow
    }
}

Write-Host "`n=== Setup Complete ===" -ForegroundColor Cyan
Write-Host "Tools: $toolsDst"
Write-Host "MCP Server: node $toolsDst\omniroute-tools.mjs"
Write-Host "Bridge Plugin: node $toolsDst\bridge-plugin-system.mjs list"
Write-Host "`nTo add new bridges: edit $bridgesFile" -ForegroundColor DarkGray
