<#
.SYNOPSIS
  Seed Claude Code's gateway-model cache so the /model picker shows ALL
  auto/ routes (and nothing else) — and keep it that way.
.DESCRIPTION
  Claude Code caches the gateway catalog in ~/.claude/cache/gateway-models.json,
  but when it refetches the catalog itself it filters it to claude-named models
  (322 models / 2 auto routes). That's why the picker keeps showing only
  auto/claude-opus + auto/claude-sonnet. This script writes the cache directly
  with just the auto/ routes and pins fetchedAt ~1 year out, so the app treats
  the cache as fresh and never refetches-and-filters.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File fix-model-cache.ps1
  powershell -ExecutionPolicy Bypass -File fix-model-cache.ps1 -Base http://localhost:20128
#>
param(
    [string]$Base = 'http://localhost:20128',
    [string]$Token = 'omniroute'
)
$ErrorActionPreference = 'Stop'

# ---- 1. discover auto/ routes from the live gateway ----
Write-Host "Fetching catalog from $Base/v1/models ..." -ForegroundColor Cyan
$catalog = Invoke-RestMethod -Uri "$Base/v1/models" -Headers @{ Authorization = "Bearer $Token" } -TimeoutSec 60
$auto = @($catalog.data | ForEach-Object { $_.id } | Where-Object { $_ -like 'auto/*' } | Sort-Object)
if ($auto.Count -eq 0) {
    Write-Host 'No auto/ routes discovered - gateway unreachable or catalog empty?' -ForegroundColor Red
    exit 1
}

# ---- 2. write the cache with a far-future fetchedAt (epoch ms) ----
$ccCache = Join-Path $HOME '.claude\cache'
New-Item -ItemType Directory -Force -Path $ccCache | Out-Null
$cacheFile = Join-Path $ccCache 'gateway-models.json'
if (Test-Path $cacheFile) {
    Copy-Item $cacheFile "$cacheFile.bak-filtered" -Force
}
$cache = [ordered]@{
    baseUrl   = "$Base"
    fetchedAt = [DateTimeOffset]::UtcNow.AddYears(1).ToUnixTimeMilliseconds()
    models    = @($auto | ForEach-Object { [ordered]@{ id = $_ } })
}
$json = $cache | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText($cacheFile, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Cache seeded: $($auto.Count) auto/ routes -> $cacheFile" -ForegroundColor Green

# ---- 3. make sure availableModels lists them too ----
$ccFile = Join-Path $HOME '.claude\settings.json'
if (Test-Path $ccFile) {
    $cc = Get-Content $ccFile -Raw | ConvertFrom-Json
    $cur = @($cc.availableModels)
    $merged = @($cur + $auto | Sort-Object -Unique)
    if ($merged.Count -ne $cur.Count) {
        $cc | Add-Member -NotePropertyName 'availableModels' -NotePropertyValue $merged -Force
        $json = $cc | ConvertTo-Json -Depth 12
        [System.IO.File]::WriteAllText($ccFile, $json, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "availableModels updated -> $($merged.Count) routes" -ForegroundColor Green
    }
}

Write-Host ''
Write-Host 'Done. Now FULLY quit VS Code and Claude Desktop (all windows, and' -ForegroundColor Yellow
Write-Host 'taskbar/processes) and reopen - the picker will show all auto/ routes.' -ForegroundColor Yellow
