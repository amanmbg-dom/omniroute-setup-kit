<#
.SYNOPSIS
  Creates a private GitHub repo for this kit and pushes it.

.DESCRIPTION
  Requires the GitHub CLI (gh) and a login. If gh is not authenticated it
  prints the one command to run first (opens a browser for the OAuth flow).
  Creates the repo as PRIVATE - config/local.env contains live API keys.

.EXAMPLE
  gh auth login
  powershell -ExecutionPolicy Bypass -File push-to-github.ps1
#>
[CmdletBinding()]
param(
    [string]$RepoName = 'omniroute-setup-kit',
    [string]$Description = 'One-click Windows setup: free-model OmniRoute gateway + Cookie Pusher extension + Claude Code wiring'
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host 'GitHub CLI not found. Install it with:' -ForegroundColor Red
    Write-Host '    winget install GitHub.cli' -ForegroundColor Yellow
    exit 1
}

gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host 'Not logged in to GitHub. Run this once (opens a browser for the OAuth flow), then re-run this script:' -ForegroundColor Yellow
    Write-Host '    gh auth login' -ForegroundColor Yellow
    exit 1
}

Write-Host "Creating/pushing private repo: $RepoName" -ForegroundColor Cyan
& gh repo create $RepoName --private --source . --push --description $Description
if ($LASTEXITCODE -ne 0) {
    # repo already exists - point the remote at it and push
    $url = gh repo view $RepoName --json url -q .url
    git remote remove origin 2>$null
    git remote add origin $url
    git push -u origin main
}

Write-Host ''
Write-Host 'Done. Clone it anywhere with:' -ForegroundColor Green
$url = gh repo view $RepoName --json url -q .url
Write-Host "    git clone $url" -ForegroundColor Yellow
Write-Host ''
Write-Host 'Security reminder: config/local.env contains live API keys. Keep this repo private' -ForegroundColor Yellow
Write-Host '(it was created private). If you ever plan to share it, empty the keys in config/local.env first.' -ForegroundColor Yellow
