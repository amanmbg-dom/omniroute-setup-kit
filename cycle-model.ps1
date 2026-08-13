<#
.SYNOPSIS
  Cycle the Claude Code default model through the free-pool fast routes.
.DESCRIPTION
  Rotates ~/.claude/settings.json -> env.ANTHROPIC_MODEL through:
      auto/coding:reliable -> auto/best-coding -> auto/best-fast
  Use -To to jump straight to a specific slot instead of the next one.
  Changing settings.json sets the DEFAULT for new sessions; the current
  session still needs /model (printed below) to apply it immediately.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File cycle-model.ps1
  powershell -ExecutionPolicy Bypass -File cycle-model.ps1 -To fast
#>
param(
    [string]$SettingsPath = "$env:USERPROFILE\.claude\settings.json",
    [ValidateSet('reliable','coding','fast','')]
    [string]$To = ''
)

$ErrorActionPreference = 'Stop'
$cycle = @('auto/coding:reliable', 'auto/best-coding', 'auto/best-fast')
$labels = @{ 'reliable' = 'auto/coding:reliable'; 'coding' = 'auto/best-coding'; 'fast' = 'auto/best-fast' }

# ---- read current settings ----
$settings = $null
if (Test-Path $SettingsPath) {
    $raw = Get-Content $SettingsPath -Raw
    if ($raw -and $raw.Trim()) { $settings = $raw | ConvertFrom-Json }
}
if (-not $settings) { $settings = [pscustomobject]@{} }
if (-not $settings.env) { $settings | Add-Member -NotePropertyName 'env' -NotePropertyValue ([pscustomobject]@{}) -Force }

$current = $settings.env.ANTHROPIC_MODEL
if (-not $current) { $current = $cycle[0] }

# ---- decide next ----
$next = $null
if ($To) {
    $next = $labels[$To]
} else {
    $idx = [Array]::IndexOf($cycle, [string]$current)
    if ($idx -lt 0) { $idx = -1 }
    $next = $cycle[($idx + 1) % $cycle.Count]
}

# ---- write back ----
$settings.env.ANTHROPIC_MODEL = $next
# Write WITHOUT BOM (PS 5.1 Set-Content -Encoding UTF8 adds one, which breaks Claude Code's JSON.parse)
$json = $settings | ConvertTo-Json -Depth 12
[System.IO.File]::WriteAllText($SettingsPath, $json, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ""
Write-Host "  Model cycled:  $current  ->  $next" -ForegroundColor Green
Write-Host "  Default for NEW sessions updated in $SettingsPath" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  To apply to THIS session, run:  /model   then type/pick:  $next" -ForegroundColor Cyan
Write-Host ""
