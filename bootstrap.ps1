<#
.SYNOPSIS
  Zero-dependency bootstrap for a brand-new Windows PC (nothing installed).

.DESCRIPTION
  Assumes NOTHING except PowerShell + internet. It:
    1. installs the prerequisites (Git, Node.js LTS, Python, Google Chrome,
       GitHub CLI) using winget (installing winget itself first if needed)
    2. obtains the omniroute-setup-kit (git clone, or zip fallback)
    3. runs setup.ps1 -Pull -UpdateSkills to configure everything
       (OmniRoute gateway, free providers, image bridges, Claude Code wiring,
       Claude Desktop, MCP servers, skills, auto-start)

  How to run on a bare PC (works for a PUBLIC repo - paste into PowerShell):
    irm https://raw.githubusercontent.com/amanmbg-dom/omniroute-setup-kit/main/bootstrap.ps1 | iex

  For a PRIVATE repo (this kit is private): log into GitHub on the new PC,
  open the repo page, Download ZIP, extract, then double-click install.cmd
  (install.cmd calls bootstrap.ps1 -PrereqsOnly automatically).

.PARAMETER PrereqsOnly
  Only install the prerequisites; do not obtain the kit or run setup.ps1.

.PARAMETER SkipPrereqs
  Skip prerequisite installation entirely (assume git/node/python/chrome exist).

.PARAMETER RepoUrl
  GitHub URL of the kit to clone when it is not already present.

.PARAMETER KitDir
  Where the kit lives / should be cloned. Defaults to this script's folder if
  setup.ps1 sits next to it, otherwise $HOME\omniroute-setup-kit.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File bootstrap.ps1
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File bootstrap.ps1 -PrereqsOnly
#>
[CmdletBinding()]
param(
    [switch]$PrereqsOnly,
    [switch]$SkipPrereqs,
    [string]$RepoUrl = 'https://github.com/amanmbg-dom/omniroute-setup-kit.git',
    [string]$KitDir   = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
# Windows PowerShell 5.1 defaults to TLS 1.0/1.1 - force TLS 1.2+ so downloads work.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host "    $m" -ForegroundColor Green }
function Write-Warn($m) { Write-Host "    $m" -ForegroundColor Yellow }
function Test-Cmd($name) { return [bool](Get-Command $name -ErrorAction SilentlyContinue) }

# ---------------------------------------------------------------- locating the kit
$kitHere = $false
if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'setup.ps1'))) { $kitHere = $true }
if (-not $KitDir) {
    if ($kitHere) { $KitDir = $PSScriptRoot } else { $KitDir = Join-Path $HOME 'omniroute-setup-kit' }
}
$setupPs = Join-Path $KitDir 'setup.ps1'

# ---------------------------------------------------------------- PATH refresh
function Refresh-Path {
    # Reload PATH from the registry so tools installed this session are visible NOW.
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
}

# ---------------------------------------------------------------- winget
function Ensure-Winget {
    if (Test-Cmd winget) { return $true }
    Write-Step 'winget not found - installing the App Installer (winget)'
    try {
        $tmp = Join-Path $env:TEMP 'AppInstaller.msixbundle'
        Invoke-WebRequest -Uri 'https://aka.ms/getwinget' -OutFile $tmp -UseBasicParsing
        Add-AppxPackage -Path $tmp -ErrorAction Stop
        Refresh-Path
        if (Test-Cmd winget) { Write-Ok 'winget installed'; return $true }
        Write-Warn 'winget still not on PATH - open a NEW PowerShell window and re-run this script.'
        return $false
    } catch {
        Write-Warn "Could not install winget: $_"
        return $false
    }
}

# ---------------------------------------------------------------- tools
function Ensure-Tool {
    param(
        [string]$Display,
        [string]$WingetId,
        [string]$Bin,
        [string[]]$Paths = @()
    )
    if (Test-Cmd $Bin) { Write-Ok "$Display already installed"; return $true }
    # Some apps (Chrome) are not on PATH - check the known install locations too.
    foreach ($p in $Paths) { if (Test-Path $p) { Write-Ok "$Display already installed ($p)"; return $true } }
    Write-Step "Installing $Display"
    if (-not (Ensure-Winget)) {
        Write-Warn "winget unavailable - install $Display manually then re-run."
        return $false
    }
    & winget install --id $WingetId -e --accept-source-agreements --accept-package-agreements --silent --disable-interactivity 2>&1 | Out-Null
    Refresh-Path
    if (Test-Cmd $Bin) {
        Write-Ok "$Display installed"
        return $true
    }
    Write-Warn "$Display install did not land on PATH - open a NEW PowerShell window and re-run, or install manually."
    return $false
}

# ---------------------------------------------------------------- 1. prerequisites
if (-not $SkipPrereqs) {
    Write-Step 'Prerequisites (Git, Node.js, Python, Chrome, GitHub CLI)'
    $allOk = $true
    $allOk = (Ensure-Tool -Display 'Git for Windows' -WingetId 'Git.Git'            -Bin 'git')     -and $allOk
    $allOk = (Ensure-Tool -Display 'Node.js LTS'     -WingetId 'OpenJS.NodeJS.LTS'  -Bin 'node')    -and $allOk
    $allOk = (Ensure-Tool -Display 'Python 3'        -WingetId 'Python.Python.3.12' -Bin 'python' -Paths @("$env:LOCALAPPDATA\Programs\Python\python.exe", "$env:LOCALAPPDATA\Programs\Python\Launcher\py.exe")) -and $allOk
    $allOk = (Ensure-Tool -Display 'Google Chrome'   -WingetId 'Google.Chrome'      -Bin 'chrome' -Paths @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe")) -and $allOk
    $allOk = (Ensure-Tool -Display 'GitHub CLI'      -WingetId 'GitHub.cli'         -Bin 'gh')      -and $allOk
    if (-not $allOk) {
        Write-Warn 'One or more prerequisites need attention - see messages above.'
    }
} else {
    Write-Step 'Skipping prerequisites (-SkipPrereqs)'
}
Refresh-Path

if ($PrereqsOnly) {
    Write-Host ''
    Write-Host 'Prerequisite step finished.' -ForegroundColor Cyan
    Write-Host 'Now run:  powershell -NoProfile -ExecutionPolicy Bypass -File setup.ps1 -Pull -UpdateSkills' -ForegroundColor Yellow
    exit 0
}

# ---------------------------------------------------------------- 2. obtain the kit
if (-not (Test-Path $setupPs)) {
    Write-Step "Kit not found at $KitDir - obtaining it"
    New-Item -ItemType Directory -Force -Path $KitDir | Out-Null
    if (Test-Cmd git) {
        # Preferred: git clone (works for private repos with your credentials).
        if (Test-Path (Join-Path $KitDir '.git')) {
            Write-Ok 'kit already cloned'
            Push-Location $KitDir
            & git pull --ff-only 2>&1 | Out-Null
            Pop-Location
        } else {
            Write-Host "    git clone $RepoUrl"
            & git clone $RepoUrl $KitDir
            if ($LASTEXITCODE -ne 0) {
                Write-Warn 'git clone failed (private repo needs auth: run "gh auth login" first, or Download ZIP from the repo page).'
            }
        }
    }
    if (-not (Test-Path $setupPs)) {
        # Fallback: codeload zip (public repos only).
        $zip = Join-Path $env:TEMP 'omniroute-setup-kit.zip'
        Write-Host '    downloading repo zip (public repo only)...'
        try {
            Invoke-WebRequest -Uri 'https://github.com/amanmbg-dom/omniroute-setup-kit/archive/refs/heads/main.zip' -OutFile $zip -UseBasicParsing
            Expand-Archive -Path $zip -DestinationPath $KitDir -Force
            $inner = Get-ChildItem $KitDir -Directory | Select-Object -First 1
            if ($inner -and -not (Test-Path $setupPs)) {
                Get-ChildItem $inner.FullName -Force | Move-Item -Destination $KitDir -Force
                Remove-Item $inner.FullName -Recurse -Force
            }
        } catch {
            Write-Warn "Could not download the kit: $_"
        }
    }
    if (-not (Test-Path $setupPs)) {
        Write-Host ''
        Write-Host 'Could not obtain the kit. Do one of:' -ForegroundColor Red
        Write-Host '  1. gh auth login, then re-run this script (private repo)'
        Write-Host '  2. On the GitHub repo page: Code -> Download ZIP, extract, run install.cmd'
        exit 1
    }
    Write-Ok "kit ready at $KitDir"
} else {
    Write-Ok "kit found at $KitDir"
}

# ---------------------------------------------------------------- 3. run setup
Write-Step 'Running setup.ps1 (gateway, providers, bridges, Claude Code, Claude Desktop, MCPs, skills)'
& powershell -NoProfile -ExecutionPolicy Bypass -File $setupPs -Pull -UpdateSkills
exit $LASTEXITCODE
