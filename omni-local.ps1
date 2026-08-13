<#
.SYNOPSIS
  Point Claude Code back at the LOCAL OmniRoute gateway (127.0.0.1:20128).
.DESCRIPTION
  Restores ~/.claude/settings.json from the .bak-local backup made by
  omni-remote.ps1, or re-writes the local defaults if no backup exists.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File "$HOME\.omniroute\omni-local.ps1"
#>
$ErrorActionPreference = 'Stop'
$ccFile = Join-Path $HOME '.claude\settings.json'
$bak = "$ccFile.bak-local"

if (-not (Test-Path $ccFile)) {
    Write-Host 'No settings.json to switch back.' -ForegroundColor Red
    exit 1
}

if (Test-Path $bak) {
    Move-Item $bak $ccFile -Force
    Write-Host 'Restored local settings from backup.' -ForegroundColor Green
} else {
    $cc = Get-Content $ccFile -Raw | ConvertFrom-Json
    $cc.env | Add-Member -NotePropertyName 'ANTHROPIC_BASE_URL' -NotePropertyValue 'http://localhost:20128' -Force
    $cc.env | Add-Member -NotePropertyName 'ANTHROPIC_AUTH_TOKEN' -NotePropertyValue 'omniroute' -Force
    $json = $cc | ConvertTo-Json -Depth 12
    [System.IO.File]::WriteAllText($ccFile, $json, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host 'Reset to local gateway defaults.' -ForegroundColor Green
}
Write-Host '  BASE_URL : http://localhost:20128   AUTH_TOKEN : omniroute'
Write-Host '  Restart Claude Code / the Desktop Code tab to apply.' -ForegroundColor Cyan
