<#
.SYNOPSIS
  One-click setup for the free-model OmniRoute gateway + Cookie Pusher kit.

.DESCRIPTION
  Reproduces the entire working setup on a fresh Windows machine:
    - installs OmniRoute (the ONLY thing fetched from the internet)
    - configures the gateway on the port in config/local.env (default 20128)
    - adds the NVIDIA NIM + OpenCode Zen free providers (keys from config/local.env)
    - applies the Cloudflare user-agent + rate-limit fixes that make Zen work
    - mints a fresh per-machine admin API key for the Cookie Pusher extension
    - copies the extension to ~\omniroute-cookie-pusher
    - registers the gateway to auto-start at login

  Everything except the single npm install lives inside this repo.

.PARAMETER SkipInstall
  Skip the omniroute npm install (assume it is already installed).

.PARAMETER SkipProviders
  Skip adding/updating the NIM + Zen provider connections.

.PARAMETER SkipExtension
  Skip the extension copy and API-key minting.

.PARAMETER SkipClaudeCode
  Skip wiring Claude Code (ANTHROPIC_* env) to the gateway.

.PARAMETER SkipBridge
  Skip installing the Google Flow image bridge (gemini_webapi venv + gflow registration).

.PARAMETER SkipFlowBridge
  Skip installing the flowui bridge (Google Flow via real Chrome session + flowui registration).

.PARAMETER SkipAutoStart
  Skip registering the login auto-start launcher.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File setup.ps1
#>
[CmdletBinding()]
param(
    [switch]$SkipInstall,
    [switch]$SkipProviders,
    [switch]$SkipExtension,
    [switch]$SkipClaudeCode,
    [switch]$SkipBridge,
    [switch]$SkipFlowBridge,
    [switch]$SkipAutoStart
)

$ErrorActionPreference = 'Stop'
$KitRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host "    $m" -ForegroundColor Green }
function Write-Skip($m) { Write-Host "    $m" -ForegroundColor DarkGray }
function Write-Warn($m) { Write-Host "    $m" -ForegroundColor Yellow }

function Read-EnvFile($path) {
    $h = @{}
    if (Test-Path $path) {
        Get-Content $path | ForEach-Object {
            $line = $_.Trim()
            if ($line -and -not $line.StartsWith('#')) {
                $i = $line.IndexOf('=')
                if ($i -gt 0) { $h[$line.Substring(0, $i).Trim()] = $line.Substring($i + 1).Trim() }
            }
        }
    }
    return $h
}

# ---------- 1. config ----------
$envPath = Join-Path $KitRoot 'config\local.env'
if (-not (Test-Path $envPath)) {
    Write-Host "config/local.env not found next to setup.ps1. Aborting." -ForegroundColor Red
    exit 1
}
$cfg  = Read-EnvFile $envPath
$Port = if ($cfg.OMNIROUTE_PORT) { $cfg.OMNIROUTE_PORT } else { '20128' }
$Pass = if ($cfg.DASHBOARD_PASSWORD) { $cfg.DASHBOARD_PASSWORD } else { 'CHANGEME' }
$NimKey = $cfg.NVIDIA_NIM_API_KEY
$ZenKey = $cfg.OPENCODE_ZEN_API_KEY
$GemKey = $cfg.GEMINI_API_KEY
$Base   = "http://127.0.0.1:$Port"

# ---------- 2. node ----------
Write-Step 'Checking Node.js'
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Host "Node.js is required but not on PATH. Install LTS and re-run, e.g.:" -ForegroundColor Red
    Write-Host "    winget install OpenJS.NodeJS.LTS" -ForegroundColor Yellow
    exit 1
}
Write-Ok "node $(node --version)"

# ---------- 3. omniroute (the only internet fetch) ----------
$globalPrefix = (& npm prefix -g 2>$null | Select-Object -First 1).Trim()
if (-not $globalPrefix) { $globalPrefix = Join-Path $env:APPDATA 'npm' }
$omDir  = Join-Path $globalPrefix 'node_modules\omniroute'
$omCli  = Join-Path $globalPrefix 'omniroute.cmd'

if (-not (Test-Path (Join-Path $omDir 'package.json'))) {
    if ($SkipInstall) {
        Write-Host "omniroute is not installed and -SkipInstall was given. Aborting." -ForegroundColor Red
        exit 1
    }
    Write-Step 'Installing OmniRoute (npm i -g omniroute@3.8.49) - the only download in this whole setup'
    & npm install -g omniroute@3.8.49
    if ($LASTEXITCODE -ne 0) {
        Write-Host "npm install failed. If it was a permissions error, run this once in an admin terminal:" -ForegroundColor Red
        Write-Host "    npm install -g omniroute@3.8.49" -ForegroundColor Yellow
        exit 1
    }
} else {
    $v = (Get-Content (Join-Path $omDir 'package.json') -Raw | ConvertFrom-Json).version
    Write-Ok "omniroute already installed (v$v)"
}

# ---------- 4. launcher ----------
Write-Step 'Preparing ~\.omniroute + launcher'
$omHome = Join-Path $HOME '.omniroute'
New-Item -ItemType Directory -Force -Path $omHome | Out-Null
$launcherSrc = Join-Path $KitRoot 'launcher\start-omniroute.cmd'
$launcherDst = Join-Path $omHome 'start-omniroute.cmd'
Copy-Item $launcherSrc $launcherDst -Force
Write-Ok "launcher -> $launcherDst"

# ---------- 5. server up ----------
function Test-Up([int]$tries = 30) {
    for ($i = 0; $i -lt $tries; $i++) {
        try {
            Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 -Uri "$Base/api/providers" | Out-Null
            return $true
        } catch {
            # any HTTP answer below 500 (401 counts) means something is listening
            if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -lt 500) { return $true }
            Start-Sleep -Seconds 2
        }
    }
    return $false
}

Write-Step "Ensuring the gateway is up on port $Port"
$up = Test-Up 3
if (-not $up) {
    Write-Warn 'gateway not running - starting it'
    Start-Process -FilePath $launcherDst -WindowStyle Hidden
    $up = Test-Up 30
}
if (-not $up) {
    Write-Host "Gateway did not come up on $Base. Check logs in $omHome\logs." -ForegroundColor Red
    exit 1
}
Write-Ok "gateway answering on $Base"

# ---------- 6. dashboard login ----------
function Invoke-Login {
    try {
        $null = Invoke-RestMethod -Method Post -Uri "$Base/api/auth/login" `
            -Body (@{ password = $Pass } | ConvertTo-Json) -ContentType 'application/json' `
            -SessionVariable s -TimeoutSec 10
        return $s
    } catch { return $null }
}

Write-Step 'Logging in to the dashboard'
$sess = Invoke-Login
if (-not $sess) {
    Write-Warn "login failed with the configured password - resetting it to the value in config/local.env"
    "$Pass" | & $omCli reset-password --password-stdin
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Could not reset the dashboard password. Check DASHBOARD_PASSWORD in config/local.env (min 8 chars)." -ForegroundColor Red
        exit 1
    }
    # 'reset-password' only takes effect after the server restarts - bounce it
    Write-Warn 'restarting the gateway so the new password takes effect'
    & $omCli stop 2>$null | Out-Null
    Start-Sleep -Seconds 3
    Start-Process -FilePath $launcherDst -WindowStyle Hidden
    $up = Test-Up 30
    if (-not $up) {
        Write-Host "Gateway did not come back up after the password reset. Check logs in $omHome\logs." -ForegroundColor Red
        exit 1
    }
    $sess = Invoke-Login
}
if (-not $sess) {
    Write-Host "Could not log in to the dashboard. Check DASHBOARD_PASSWORD in config/local.env." -ForegroundColor Red
    exit 1
}
Write-Ok 'dashboard login OK'

# ---------- 7. providers ----------
if (-not $SkipProviders) {
    Write-Step 'Adding free providers (NVIDIA NIM + OpenCode Zen + Google Gemini)'
    # GET /api/providers returns { connections: [...], total: N }
    $provResp = Invoke-RestMethod -WebSession $sess -Uri "$Base/api/providers" -TimeoutSec 10
    if ($provResp -is [System.Array]) { $conns = @($provResp) }
    elseif ($provResp.connections) { $conns = @($provResp.connections) }
    else { $conns = @() }

    $specs = @(
        @{ id = 'nvidia';       key = $NimKey; name = 'NVIDIA NIM' },
        @{ id = 'opencode-zen'; key = $ZenKey; name = 'OpenCode Zen' },
        @{ id = 'gemini';       key = $GemKey; name = 'Google Gemini' }
    )
    foreach ($sp in $specs) {
        if (-not $sp.key) { Write-Skip "$($sp.name): no key in config/local.env - skipped"; continue }
        $exists = @($conns | Where-Object { $_.provider -eq $sp.id })
        if ($exists.Count -gt 0) {
            Write-Ok "$($sp.name): already configured (id $($exists[0].id))"
        } else {
            $body = @{ provider = $sp.id; apiKey = $sp.key; name = $sp.name } | ConvertTo-Json
            Invoke-RestMethod -Method Post -WebSession $sess -Uri "$Base/api/providers" `
                -Body $body -ContentType 'application/json' -TimeoutSec 15 | Out-Null
            Write-Ok "$($sp.name): added"
        }
    }

    # The two fixes that make OpenCode Zen actually work (idempotent):
    # 1. opencode.ai's Cloudflare blocks node's default user-agent (403/1010)
    # 2. Zen's built-in free-tier queue budget 503s slow upstreams - widen it
    # Re-fetch the connections: $conns above was captured BEFORE the POSTs,
    # so on a fresh install it would not contain the Zen connection yet and
    # the patch below would silently no-op.
    $provResp = Invoke-RestMethod -WebSession $sess -Uri "$Base/api/providers" -TimeoutSec 10
    if ($provResp -is [System.Array]) { $conns = @($provResp) }
    elseif ($provResp.connections) { $conns = @($provResp.connections) }
    else { $conns = @() }
    $zen = @($conns | Where-Object { $_.provider -eq 'opencode-zen' }) | Select-Object -First 1
    if ($zen -and $ZenKey) {
        $patch = @{
            providerSpecificData = @{ customUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36' }
            rateLimitOverrides   = @{ rpm = 20; maxConcurrent = 2; minTime = 3000 }
        } | ConvertTo-Json -Depth 5
        try {
            Invoke-RestMethod -Method Put -WebSession $sess -Uri "$Base/api/providers/$($zen.id)" `
                -Body $patch -ContentType 'application/json' -TimeoutSec 15 | Out-Null
            Write-Ok 'opencode-zen: user-agent + rate-limit fixes applied'
        } catch {
            Write-Warn "opencode-zen patch failed: $($_.Exception.Message)"
        }
    }
}

# ---------- 8. extension ----------
if (-not $SkipExtension) {
    Write-Step 'Setting up the Cookie Pusher extension'
    $extSrc = Join-Path $KitRoot 'extension'
    $extDst = Join-Path $HOME 'omniroute-cookie-pusher'
    New-Item -ItemType Directory -Force -Path $extDst | Out-Null
    & robocopy $extSrc $extDst /E /NFL /NDL /NJH /NJS /NC /NS | Out-Null
    if ($LASTEXITCODE -ge 8) { Write-Host "robocopy failed to copy the extension." -ForegroundColor Red; exit 1 }

    # Replace any API key this kit minted on a previous run, then mint a fresh
    # per-machine token. Tokens created manually (name without "(kit)") are kept.
    $kitTokens = @((Invoke-RestMethod -WebSession $sess -Uri "$Base/api/cli/tokens" -TimeoutSec 10).tokens |
        Where-Object { $_.name -eq 'OmniRoute Cookie Pusher (kit)' -and -not $_.revokedAt })
    foreach ($t in $kitTokens) {
        try { Invoke-RestMethod -Method Delete -WebSession $sess -Uri "$Base/api/cli/tokens/$($t.id)" -TimeoutSec 10 | Out-Null } catch { }
    }
    $tokResp = Invoke-RestMethod -Method Post -WebSession $sess -Uri "$Base/api/cli/tokens" `
        -Body (@{ name = 'OmniRoute Cookie Pusher (kit)'; scope = 'admin' } | ConvertTo-Json) `
        -ContentType 'application/json' -TimeoutSec 10
    $token = $tokResp.token
    if (-not $token) { throw 'Could not read the minted API token from the response.' }

    $cfgJs = @"
// Generated by setup.ps1 - per-machine admin token for OmniRoute.
// To rotate: omniroute tokens create --name "Cookie Pusher" --scope admin
export const DEFAULT_URL = 'http://127.0.0.1:$Port';
export const DEFAULT_API_KEY = '$token';
"@
    [System.IO.File]::WriteAllText(
        (Join-Path $extDst 'config.js'),
        $cfgJs,
        (New-Object System.Text.UTF8Encoding($false))
    )
    Write-Ok "extension -> $extDst (fresh per-machine admin token minted)"
}

# ---------- 8b. google flow bridge (free Nano Banana via session token) ----------
if (-not $SkipBridge) {
    Write-Step 'Installing the Google Flow image bridge (gflow/nano-banana-2)'
    $bridgeDir = Join-Path $KitRoot 'bridge\gemini-bridge'
    $venvPy = Join-Path $bridgeDir '.venv\Scripts\python.exe'
    $bridgeOk = $true

    if (-not (Test-Path $venvPy)) {
        Write-Host '    creating Python venv + installing gemini_webapi (one-time download)...'
        & python -m venv (Join-Path $bridgeDir '.venv')
        if ($LASTEXITCODE -ne 0) { Write-Warn 'venv creation failed - bridge skipped'; $bridgeOk = $false }
        else {
            & $venvPy -m pip install --quiet --disable-pip-version-check -r (Join-Path $bridgeDir 'requirements.txt')
            if ($LASTEXITCODE -ne 0) { Write-Warn 'pip install failed - bridge skipped'; $bridgeOk = $false }
        }
    } else {
        Write-Ok 'venv already present'
    }

    if ($bridgeOk) {
        & node (Join-Path $bridgeDir 'register-gflow.mjs')
        if ($LASTEXITCODE -eq 0) { Write-Ok 'gflow registered -> model gflow/nano-banana-2' }
        else { Write-Warn 'gflow registration failed - bridge skipped'; $bridgeOk = $false }
    }
    if ($bridgeOk) {
        Write-Ok 'bridge ready. Start it with: bridge\gemini-bridge\start-bridge.cmd'
        Write-Host "    then push your google.com session once (Cookie Pusher -> Grab & push sessions with gemini.google.com signed in)." -ForegroundColor DarkGray
    }
}

# ---------- 8c. flowui bridge (Google Flow via real Chrome session) ----------
if (-not $SkipFlowBridge) {
    Write-Step 'Installing the flowui bridge (Google Flow in Chrome, flowui/nano-banana-2)'
    $flowDir = Join-Path $KitRoot 'bridge\flow-browser'
    $flowOk = $true

    if (-not (Test-Path (Join-Path $flowDir 'node_modules\playwright'))) {
        Write-Host '    npm install (playwright + mcp sdk, one-time download)...'
        Push-Location $flowDir
        & npm install --omit=dev
        Pop-Location
        if ($LASTEXITCODE -ne 0) { Write-Warn 'npm install failed - flowui bridge skipped'; $flowOk = $false }
    } else {
        Write-Ok 'node_modules already present'
    }

    if ($flowOk -and -not (Test-Path (Join-Path $flowDir 'config\flow.config.json'))) {
        # Copy the example and point it at this machine's Chrome install.
        $example = Join-Path $flowDir 'config\flow.config.example.json'
        if (Test-Path $example) {
            Copy-Item $example (Join-Path $flowDir 'config\flow.config.json')
            Write-Host "    created config\flow.config.json - edit chromePath / expectedAccount if needed." -ForegroundColor DarkGray
        }
    }

    if ($flowOk) {
        & node (Join-Path $flowDir 'register-flowui.mjs')
        if ($LASTEXITCODE -eq 0) { Write-Ok 'flowui registered -> model flowui/nano-banana-2' }
        else { Write-Warn 'flowui registration failed - bridge skipped'; $flowOk = $false }
    }
    if ($flowOk) {
        Write-Ok 'bridge ready. Start it with: bridge\flow-browser\start-flow-browser.cmd'
        Write-Host '    headless by default - your signed-in profile (~\.flow-browser-profile) is reused.' -ForegroundColor DarkGray
        Write-Host '    if the session expires, run: bridge\flow-browser\re-sign-in.cmd' -ForegroundColor DarkGray

        # Register the flowui MCP server in Claude Code so EVERY image request
        # funnels through generate_image -> the same bridge (consistent quality).
        $claude = Get-Command claude -ErrorAction SilentlyContinue
        if ($claude) {
            & claude mcp remove flowui 2>$null | Out-Null
            & claude mcp add -s user flowui -- node (Join-Path $flowDir 'flowui-mcp.mjs')
            if ($LASTEXITCODE -eq 0) { Write-Ok 'flowui MCP server registered in Claude Code (tool: generate_image)' }
            else { Write-Warn 'claude mcp add failed - MCP server not registered; the skill still works via curl fallback' }
        } else {
            Write-Warn 'claude CLI not found - flowui MCP server not registered'
            Write-Host "    register later with: claude mcp add -s user flowui -- node <kit>\bridge\flow-browser\flowui-mcp.mjs" -ForegroundColor DarkGray
        }
    }
}

# flow bridge state for the auto-start step below
$flowBridgeOk = (-not $SkipFlowBridge) -and $flowOk

# ---------- 9. Claude Code ----------
if (-not $SkipClaudeCode) {
    Write-Step 'Wiring Claude Code to the gateway'
    # Claude Code appends /v1/messages itself; the token 'omniroute' is the
    # gateway's localhost magic token (no secret stored in settings.json).
    $ccDir = Join-Path $HOME '.claude'
    $ccFile = Join-Path $ccDir 'settings.json'
    New-Item -ItemType Directory -Force -Path $ccDir | Out-Null

    if (Test-Path $ccFile) {
        $cc = Get-Content $ccFile -Raw | ConvertFrom-Json
    } else {
        $cc = [pscustomobject]@{}
    }
    if (-not $cc.env) { $cc | Add-Member -NotePropertyName env -NotePropertyValue ([pscustomobject]@{}) }
    $cc.env | Add-Member -NotePropertyName 'ANTHROPIC_BASE_URL' -NotePropertyValue "http://localhost:$Port" -Force
    $cc.env | Add-Member -NotePropertyName 'ANTHROPIC_AUTH_TOKEN' -NotePropertyValue 'omniroute' -Force
    $cc.env | Add-Member -NotePropertyName 'ANTHROPIC_MODEL' -NotePropertyValue 'auto' -Force
    $cc.env | Add-Member -NotePropertyName 'ANTHROPIC_SMALL_FAST_MODEL' -NotePropertyValue 'auto/best-fast' -Force
    $cc.env | Add-Member -NotePropertyName 'CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY' -NotePropertyValue '1' -Force
    $cc.env | Add-Member -NotePropertyName 'CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT' -NotePropertyValue '1' -Force

    # Only 'auto' shows in the /model picker (gateway-discovered models are
    # filtered by this allowlist). Add more ids here to expose them again.
    $cc | Add-Member -NotePropertyName 'availableModels' -NotePropertyValue @('auto') -Force

    $prev = Get-Content $ccFile -Raw -ErrorAction SilentlyContinue
    $json = $cc | ConvertTo-Json -Depth 12
    if ($prev -and $prev.Trim() -ne $json.Trim()) {
        Copy-Item $ccFile "$ccFile.bak-kit" -Force
    }
    [System.IO.File]::WriteAllText($ccFile, $json, (New-Object System.Text.UTF8Encoding($false)))
    Write-Ok '~/.claude/settings.json -> ANTHROPIC_BASE_URL/AUTH_TOKEN/MODEL wired to the gateway'
    Write-Ok '   (existing permissions/hooks preserved; original backed up to settings.json.bak-kit)'

    # Ship the kit's skills (single-page-site, ...) to ~/.claude/skills.
    # Only copies folders that are not already installed, so local
    # customizations are never clobbered by re-runs.
    $skillsSrc = Join-Path $PSScriptRoot 'skills'
    $skillsDst = Join-Path $ccDir 'skills'
    if (Test-Path $skillsSrc) {
        New-Item -ItemType Directory -Force -Path $skillsDst | Out-Null
        $installed = 0
        foreach ($skillDir in Get-ChildItem $skillsSrc -Directory) {
            $dstSkill = Join-Path $skillsDst $skillDir.Name
            if (-not (Test-Path (Join-Path $dstSkill 'SKILL.md'))) {
                Copy-Item $skillDir.FullName $dstSkill -Recurse -Force
                $installed++
            }
        }
        Write-Ok "$installed kit skill(s) installed to ~/.claude/skills (skipped existing)"
    }
}

# ---------- 10. auto-start ----------
if (-not $SkipAutoStart) {
    Write-Step 'Registering auto-start at login'
    $startup = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
    if (Test-Path $startup) {
        Copy-Item $launcherSrc (Join-Path $startup 'OmniRoute.cmd') -Force
        Write-Ok 'OmniRoute.cmd -> Startup folder (gateway starts at login)'
        if ($flowBridgeOk) {
            Copy-Item (Join-Path $flowDir 'start-flow-browser.cmd') (Join-Path $startup 'FlowUI-Bridge.cmd') -Force
            Write-Ok 'FlowUI-Bridge.cmd -> Startup folder (flowui image bridge starts at login, headless)'
        }
    } else {
        Write-Warn 'Startup folder not found - skipping auto-start'
    }
}

# ---------- 11. summary ----------
Write-Host ''
Write-Host '=================================================' -ForegroundColor Cyan
Write-Host '  Setup complete' -ForegroundColor Cyan
Write-Host '=================================================' -ForegroundColor Cyan
Write-Host "  Gateway   : $Base          (auto-starts at login)"
Write-Host "  Dashboard : $Base/admin    (password from config/local.env - change it!)"
Write-Host "  Extension : $HOME\omniroute-cookie-pusher"
if (-not $SkipClaudeCode) { Write-Host "  Claude Code: wired (run 'claude' - model 'auto', list all with /model)" }
if ($flowBridgeOk) {
    Write-Host '  Flow images : flowui/nano-banana-2 via bridge\flow-browser\start-flow-browser.cmd (headless, auto-starts)'
    Write-Host '                image requests route through the generate_image MCP tool -> same engine, same quality'
}
Write-Host ''
Write-Host '  Last step, once, ~1 minute:' -ForegroundColor Yellow
Write-Host "    1. Open edge://extensions (or chrome://extensions)"
Write-Host '    2. Turn on Developer mode'
Write-Host "    3. Load unpacked -> $HOME\omniroute-cookie-pusher"
Write-Host '    4. Click the extension icon -> Grab & push sessions'
Write-Host ''
Write-Host '  Models:  nvidia/<model>   (Nemotron Ultra 550B, Omni vision, DeepSeek V4 Pro, GLM-5.2, ...)'
Write-Host '           opencode-zen/<model>  (deepseek-v4-flash-free, GPT-5.x line)'
Write-Host '           auto            (fallback pool: felo, opencode built-in, agy, blackbox, ...)'
Write-Host '=================================================' -ForegroundColor Cyan
