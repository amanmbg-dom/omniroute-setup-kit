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

.PARAMETER SkipCodex
  Skip installing/wiring the OpenAI Codex CLI (~/.codex/config.toml) to the gateway.

.PARAMETER SkipBridge
  Skip installing the Google Flow image bridge (gemini_webapi venv + gflow registration).

.PARAMETER SkipFlowBridge
  Skip installing the flowui bridge (Google Flow via real Chrome session + flowui registration).

.PARAMETER SkipMimoBridge
  Skip installing the MiMo web bridge (mimo-web/* chat via aistudio.xiaomimimo.com session).

.PARAMETER SkipAutoStart
  Skip registering the login auto-start launcher.

.PARAMETER Pull
  Run `git pull --ff-only` inside the kit folder before configuring, so the
  kit (skills, extension, commands, launchers) is refreshed from GitHub first.

.PARAMETER UpdateSkills
  Re-copy the kit's skills to ~/.claude/skills even if already installed,
  backing up any existing copy to <name>.bak-kit first. Without this flag,
  existing skills are left untouched to protect local customizations.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File setup.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File setup.ps1 -Pull -UpdateSkills
#>
[CmdletBinding()]
param(
    [switch]$SkipInstall,
    [switch]$SkipProviders,
    [switch]$SkipExtension,
    [switch]$SkipClaudeCode,
    [switch]$SkipCodex,
    [switch]$SkipBridge,
    [switch]$SkipFlowBridge,
    [switch]$SkipMimoBridge,
    [switch]$SkipAutoStart,
    [switch]$Pull,
    [switch]$UpdateSkills
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

# -Pull: refresh the kit itself from its git remote before configuring.
if ($Pull) {
    Write-Step 'Pulling latest kit from git remote'
    if (Test-Path (Join-Path $KitRoot '.git')) {
        git -C $KitRoot pull --ff-only 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        if ($LASTEXITCODE -ne 0) {
            Write-Warn 'git pull reported an error - continuing with the local copy (commit or stash local changes first if needed)'
        }
    } else {
        Write-Warn "No .git folder in $KitRoot - skipping pull (clone fresh or copy the folder again)"
    }
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
# freellm.net free-tier providers (all OpenAI-compatible; keys optional, skipped when blank)
$GroqKey      = $cfg.GROQ_API_KEY
$OrKey        = $cfg.OPENROUTER_API_KEY
$GhModelsKey  = $cfg.GITHUB_MODELS_API_KEY
$CfKey        = $cfg.CLOUDFLARE_API_KEY
$CfAccountId  = $cfg.CLOUDFLARE_ACCOUNT_ID
$MsKey        = $cfg.MODELSCOPE_API_KEY
$Llm7Key      = $cfg.LLM7_API_KEY
$OvhKey       = $cfg.OVHCLOUD_API_KEY
$OllamaKey    = $cfg.OLLAMA_API_KEY
$SambaKey     = $cfg.SAMBANOVA_API_KEY
$AionKey      = $cfg.AION_API_KEY
$AgnesKey     = $cfg.AGNES_API_KEY
$ChutesKey    = $cfg.CHUTES_API_KEY
$Ai21Key      = $cfg.AI21_API_KEY
$NscaleKey    = $cfg.NSCALE_API_KEY
$AliKey       = $cfg.ALIBABA_API_KEY
$ZaiKey       = $cfg.ZAI_API_KEY
$MistralKey   = $cfg.MISTRAL_API_KEY
$CohereKey    = $cfg.COHERE_API_KEY
$CerebrasKey  = $cfg.CEREBRAS_API_KEY
$HfKey        = $cfg.HUGGINGFACE_API_KEY
$DeepseekKey  = $cfg.DEEPSEEK_API_KEY
$XaiKey       = $cfg.XAI_API_KEY
$NebiusKey    = $cfg.NEBIUS_API_KEY
$SiliconKey   = $cfg.SILICONFLOW_API_KEY
$Base   = "http://127.0.0.1:$Port"

# ---------- 2. node ----------
Write-Step 'Checking Node.js'
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Host "Node.js is required but not on PATH." -ForegroundColor Red
    Write-Host "    On a fresh PC run:  powershell -ExecutionPolicy Bypass -File bootstrap.ps1" -ForegroundColor Yellow
    Write-Host "    (or just:           winget install OpenJS.NodeJS.LTS   then re-run)" -ForegroundColor Yellow
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

# Ship the model-cycle helper next to the launcher (stable location the /cycle-model command uses).
$cycleSrc = Join-Path $KitRoot 'cycle-model.ps1'
if (Test-Path $cycleSrc) {
    Copy-Item $cycleSrc (Join-Path $omHome 'cycle-model.ps1') -Force
    Write-Ok "cycle-model.ps1 -> ~\.omniroute\cycle-model.ps1 (used by /cycle-model)"

    # Ship the VPS deploy package + remote client launchers.
    $vpsSrc = Join-Path $KitRoot 'vps'
    if (Test-Path $vpsSrc) {
        Copy-Item -Recurse -Force $vpsSrc (Join-Path $omHome 'vps')
        Write-Ok 'vps/ -> ~\.omniroute\vps\ (setup-vps.sh + session helpers)'
    }
    # Ship + run the picker seeder (env vars + native-binary patch + cache) so
    # /model shows all gateway routes.
    $seedLive = Join-Path $omHome 'fix-model-cache.ps1'
    Copy-Item (Join-Path $KitRoot 'fix-model-cache.ps1') $seedLive -Force
    $patchLive = Join-Path $omHome 'patch-claude-picker.mjs'
    if (Test-Path (Join-Path $KitRoot 'patch-claude-picker.mjs')) {
        Copy-Item (Join-Path $KitRoot 'patch-claude-picker.mjs') $patchLive -Force
    }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $seedLive -Base "http://localhost:$Port" 2>&1 | ForEach-Object { Write-Ok $_ }

    foreach ($c in @('omni-remote.ps1', 'omni-local.ps1')) {
        $s = Join-Path $KitRoot $c
        if (Test-Path $s) {
            Copy-Item $s (Join-Path $omHome $c) -Force
            Write-Ok "$c -> ~\.omniroute\$c (remote client launcher)"
        }
    }
}

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
    Write-Step 'Adding free providers (NVIDIA NIM + OpenCode Zen + Gemini + freellm.net tier)'
    # GET /api/providers returns { connections: [...], total: N }
    $provResp = Invoke-RestMethod -WebSession $sess -Uri "$Base/api/providers" -TimeoutSec 10
    if ($provResp -is [System.Array]) { $conns = @($provResp) }
    elseif ($provResp.connections) { $conns = @($provResp.connections) }
    else { $conns = @() }

    # Provider ids verified against the gateway's registry (POST /api/providers).
    # OpenRouter free models are exposed as openrouter/<model>:free once the key
    # is set - they show up in the picker via fix-model-cache.ps1.
    $specs = @(
        @{ id = 'nvidia';        key = $NimKey;      name = 'NVIDIA NIM' },
        @{ id = 'opencode-zen';  key = $ZenKey;      name = 'OpenCode Zen' },
        @{ id = 'gemini';        key = $GemKey;      name = 'Google Gemini' },
        @{ id = 'groq';          key = $GroqKey;     name = 'Groq' },
        @{ id = 'openrouter';    key = $OrKey;       name = 'OpenRouter' },
        @{ id = 'github-models'; key = $GhModelsKey; name = 'GitHub Models' },
        @{ id = 'cloudflare-ai'; key = $CfKey;       name = 'Cloudflare Workers AI' },
        @{ id = 'modelscope';    key = $MsKey;       name = 'ModelScope' },
        @{ id = 'llm7';          key = $Llm7Key;     name = 'LLM7.io' },
        @{ id = 'ovhcloud';      key = $OvhKey;      name = 'OVHcloud AI Endpoints' },
        @{ id = 'ollama-cloud';  key = $OllamaKey;   name = 'Ollama Cloud' },
        @{ id = 'sambanova';     key = $SambaKey;    name = 'SambaNova' },
        @{ id = 'aion';          key = $AionKey;     name = 'Aion Labs' },
        @{ id = 'agnes';         key = $AgnesKey;    name = 'Agnes AI' },
        @{ id = 'chutes';        key = $ChutesKey;   name = 'Chutes.ai' },
        @{ id = 'ai21';          key = $Ai21Key;     name = 'AI21 Labs' },
        @{ id = 'nscale';        key = $NscaleKey;   name = 'Nscale' },
        @{ id = 'alibaba';       key = $AliKey;      name = 'Alibaba Model Studio' },
        @{ id = 'zai';           key = $ZaiKey;      name = 'Z AI (Zhipu)' },
        @{ id = 'mistral';       key = $MistralKey;  name = 'Mistral AI' },
        @{ id = 'cohere';        key = $CohereKey;   name = 'Cohere' },
        @{ id = 'cerebras';      key = $CerebrasKey; name = 'Cerebras' },
        @{ id = 'huggingface';   key = $HfKey;       name = 'Hugging Face' },
        @{ id = 'deepseek';      key = $DeepseekKey; name = 'DeepSeek' },
        @{ id = 'xai';           key = $XaiKey;      name = 'xAI (Grok)' },
        @{ id = 'nebius';        key = $NebiusKey;   name = 'Nebius' },
        @{ id = 'siliconflow';   key = $SiliconKey;  name = 'SiliconFlow' }
    )
    foreach ($sp in $specs) {
        if (-not $sp.key) { Write-Skip "$($sp.name): no key in config/local.env - skipped"; continue }
        $exists = @($conns | Where-Object { $_.provider -eq $sp.id })
        if ($exists.Count -gt 0) {
            Write-Ok "$($sp.name): already configured (id $($exists[0].id))"
        } else {
            $bodyObj = @{ provider = $sp.id; apiKey = $sp.key; name = $sp.name }
            # Cloudflare Workers AI builds its per-connection URL from the Account ID -
            # the API token alone is not enough (502 without it).
            if ($sp.id -eq 'cloudflare-ai' -and $CfAccountId) {
                $bodyObj.providerSpecificData = @{ accountId = $CfAccountId }
            }
            $body = $bodyObj | ConvertTo-Json -Depth 5
            Invoke-RestMethod -Method Post -WebSession $sess -Uri "$Base/api/providers" `
                -Body $body -ContentType 'application/json' -TimeoutSec 15 | Out-Null
            Write-Ok "$($sp.name): added"
        }
    }

    # Cloudflare: if the connection already exists but was added before the Account
    # ID plumbing, patch it so the 502 "requires an Account ID" goes away (idempotent).
    if ($CfKey -and $CfAccountId) {
        $cf = @($conns | Where-Object { $_.provider -eq 'cloudflare-ai' }) | Select-Object -First 1
        if ($cf) {
            $patch = @{ providerSpecificData = @{ accountId = $CfAccountId } } | ConvertTo-Json -Depth 5
            try {
                Invoke-RestMethod -Method Put -WebSession $sess -Uri "$Base/api/providers/$($cf.id)" `
                    -Body $patch -ContentType 'application/json' -TimeoutSec 15 | Out-Null
                Write-Ok 'cloudflare-ai: Account ID patched'
            } catch {
                Write-Warn 'cloudflare-ai: could not patch Account ID (set CLOUDFLARE_ACCOUNT_ID in config/local.env)'
            }
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

// Local cookie bridges (mimo-web-bridge on 20135) - cookies are pushed here
// directly instead of into a gateway connection.
export const BRIDGE_URL = 'http://127.0.0.1:20135';
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

# ---------- 8d. mimo-web bridge (free MiMo V2.5 chat via aistudio session) ----------
# No npm deps - plain node (>= 20) + global fetch. The Cookie Pusher's Grab &
# push sessions sends the aistudio.xiaomimimo.com cookies to the bridge directly
# (the gateway has no executor for xiaomimimo-web, so no gateway connection).
if (-not $SkipMimoBridge) {
    Write-Step 'Installing the MiMo web bridge (mimo-web/* chat via your MiMo AI Studio session)'
    $mimoDir = Join-Path $KitRoot 'bridge\mimo-web-bridge'
    $mimoOk = $true
    if (-not (Test-Path (Join-Path $mimoDir 'bridge.mjs'))) {
        Write-Warn 'bridge files missing - mimo bridge skipped'
        $mimoOk = $false
    }
    if ($mimoOk) {
        & node (Join-Path $mimoDir 'register-mimo-web.mjs')
        if ($LASTEXITCODE -eq 0) { Write-Ok 'mimo-web registered -> models mimo-web/mimo-v2.5, mimo-web/mimo-v2.5-pro, ...' }
        else { Write-Warn 'mimo-web registration failed - bridge skipped'; $mimoOk = $false }
    }
    if ($mimoOk) {
        Write-Ok 'bridge ready. Start it with: bridge\mimo-web-bridge\start-bridge.cmd'
        Write-Host "    then sign in at aistudio.xiaomimimo.com and run Cookie Pusher -> Grab & push sessions." -ForegroundColor DarkGray
        Write-Host '    (fix-model-cache.ps1 also auto-starts the bridge when it is not running.)' -ForegroundColor DarkGray
    }
}
$mimoBridgeOk = (-not $SkipMimoBridge) -and $mimoOk

# ---------- 9. Claude Code ----------
if (-not $SkipClaudeCode) {
    # The Claude Code CLI is what the gateway is wired into (terminal, VS Code
    # extension and Claude Desktop's Code tab all share it). Fresh PCs get it
    # installed right here - nothing else in this script works without it.
    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
        Write-Step 'Installing the Claude Code CLI (npm i -g @anthropic-ai/claude-code)'
        & npm install -g @anthropic-ai/claude-code 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Ok "claude $(claude --version)" }
        else { Write-Warn 'claude CLI install failed - re-run setup.ps1 after fixing npm' }
    }

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
    $cc.env | Add-Member -NotePropertyName 'ANTHROPIC_MODEL' -NotePropertyValue 'auto/coding:reliable' -Force
    $cc.env | Add-Member -NotePropertyName 'ANTHROPIC_SMALL_FAST_MODEL' -NotePropertyValue 'auto/best-fast' -Force
    # Gateway model discovery (Claude Code >= 2.1.233): USE_GATEWAY registers
    # the auth token as a gateway credential (bootstrap fetches the catalog),
    # ENABLE_GATEWAY_MODEL_DISCOVERY turns on the /v1/models bootstrap fetch,
    # and patch-claude-picker.mjs (run by fix-model-cache.ps1 below) removes the
    # claude/anthropic id filter so the /model picker shows the FULL gateway
    # catalog (auto/*, combo/*, mimo-web/*, lmarena/*, ...). Without the patch
    # the picker would only show claude-named routes.
    $cc.env | Add-Member -NotePropertyName 'CLAUDE_CODE_USE_GATEWAY' -NotePropertyValue 'true' -Force
    $cc.env | Add-Member -NotePropertyName 'CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY' -NotePropertyValue 'true' -Force
    $cc.env | Add-Member -NotePropertyName 'CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT' -NotePropertyValue '1' -Force

    # The /model picker shows only gateway-discovered models on this allowlist.
    # Mirror the picker's "majors" - the gateway's flagship auto/* routing routes
    # (auto/coding:reliable, auto/best-coding, auto/best-fast, auto/best-vision,
    # auto/best-reasoning, per-family auto/glm / auto/minimax / auto/zai, chaos,
    # offline, ...) - PLUS every ALIVE NVIDIA NIM (nvidia/*, dead/non-chat ones
    # excluded via config/nvidia-dead.json) PLUS the free OpenCode
    # (opencode-zen/*-free, oc/*-free, big-pickle) and OpenRouter
    # (openrouter/*:free) routes from the live gateway. The fix-model-cache.ps1
    # step below rebuilds availableModels from the same rules, so re-runs keep
    # the list trimmed (auto/* majors kept, dead NIM dropped).
    $nvidiaDead = @()
    $deadJson = @(
        (Join-Path $PSScriptRoot 'config\nvidia-dead.json'),
        (Join-Path $HOME 'omniroute-setup-kit\config\nvidia-dead.json')
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($deadJson) { $nvidiaDead = @((ConvertFrom-Json (Get-Content $deadJson -Raw))) }
    # NOTE: 'diffusion'/'translate' intentionally omitted - diffusiongemma-26b-a4b-it
    # and riva-translate-4b-instruct v1.1/v2 answer the chat endpoint (probed alive
    # 2026-08-14); dead variants are enumerated explicitly in nvidia-dead.json.
    $deadPattern = 'embed|rerank|asr|tts|whisper|fastpitch|tacotron|nvclip|flux|parse|detector|reward|neva|vila|kosmos|deplot|fuyu'
    $autoRoutes = @('auto')
    try {
        $catalog = Invoke-RestMethod -Uri "$Base/v1/models" -Headers @{ Authorization = 'Bearer omniroute' } -TimeoutSec 60
        $autoRoutes = @($catalog.data | ForEach-Object { $_.id } | Where-Object {
            $_ -like 'auto/*' -or
            ($_ -like 'nvidia/*' -and $_ -notin $nvidiaDead -and $_ -notmatch $deadPattern) -or
            (($_ -like 'opencode-zen/*' -or $_ -like 'oc/*') -and ($_ -like '*-free' -or $_ -like '*/big-pickle')) -or
            ($_ -like 'openrouter/*' -and $_ -like '*:free')
        } | Sort-Object -Unique)
        # combo/* family routes (combo/qwen, combo/glm, combo/deepseek, combo/lmarena)
        # are created by fix-model-cache.ps1 below and are NOT in the /v1/models
        # catalog, so mirror them explicitly into the picker allowlist.
        $autoRoutes = @('auto') + $autoRoutes + @('combo/qwen','combo/glm','combo/deepseek','combo/lmarena','combo/lmarena-fast','combo/lmarena-slow','combo/mimo')
        $autoRoutes = @($autoRoutes | Sort-Object -Unique)
    } catch { Write-Warn "could not discover routes from gateway ($_) - using auto only" }
    if ($autoRoutes.Count -eq 0) { $autoRoutes = @('auto') }
    $cc | Add-Member -NotePropertyName 'availableModels' -NotePropertyValue $autoRoutes -Force
    Write-Ok "availableModels -> $($autoRoutes.Count) routes (auto/* majors + combo/* + nvidia-alive + opencode-free + openrouter:free) in the /model picker"

    $prev = Get-Content $ccFile -Raw -ErrorAction SilentlyContinue
    $json = $cc | ConvertTo-Json -Depth 12
    if ($prev -and $prev.Trim() -ne $json.Trim()) {
        Copy-Item $ccFile "$ccFile.bak-kit" -Force
    }
    [System.IO.File]::WriteAllText($ccFile, $json, (New-Object System.Text.UTF8Encoding($false)))
    Write-Ok '~/.claude/settings.json -> ANTHROPIC_BASE_URL/AUTH_TOKEN/MODEL wired to the gateway'
    Write-Ok '   (existing permissions/hooks preserved; original backed up to settings.json.bak-kit)'

    # Claude Code caches the gateway model catalog in ~/.claude/cache, and when
    # it REFETCHES the catalog itself it filters it to claude-named models
    # (322 models / 2 auto routes) - which is why the picker kept showing only
    # auto/claude-opus + auto/claude-sonnet. Do NOT delete the cache (that
    # forces the filtered refetch). Instead seed it with the auto/ routes and a
    # far-future fetchedAt so the app treats it as fresh and never refetches.
    # Run AFTER the settings.json write above so the availableModels rebuild
    # (auto/* majors + combo/* + web-chat routes + NIM + free tiers) is not
    # clobbered by the base allowlist written just now.
    $seedScript = Join-Path $KitRoot 'fix-model-cache.ps1'
    if (Test-Path $seedScript) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $seedScript -Base "http://localhost:$Port" | ForEach-Object { Write-Ok $_ }
    } else {
        Write-Warn 'fix-model-cache.ps1 missing - /model picker may only show claude-named auto routes'
    }

    # Ship the kit's skills (single-page-site, ...) to ~/.claude/skills.
    # By default only copies folders that are not already installed, so local
    # customizations are never clobbered by re-runs. With -UpdateSkills,
    # existing copies are backed up to <name>.bak-kit and overwritten.
    $skillsSrc = Join-Path $PSScriptRoot 'skills'
    $skillsDst = Join-Path $ccDir 'skills'
    if (Test-Path $skillsSrc) {
        New-Item -ItemType Directory -Force -Path $skillsDst | Out-Null
        $installed = 0
        $backedUp = 0
        foreach ($skillDir in Get-ChildItem $skillsSrc -Directory) {
            $dstSkill = Join-Path $skillsDst $skillDir.Name
            if (-not (Test-Path (Join-Path $dstSkill 'SKILL.md')) -or $UpdateSkills) {
                if ($UpdateSkills -and (Test-Path $dstSkill)) {
                    $bakSkill = "$dstSkill.bak-kit"
                    if (Test-Path $bakSkill) { Remove-Item $bakSkill -Recurse -Force }
                    Rename-Item $dstSkill $bakSkill
                    $backedUp++
                }
                Copy-Item $skillDir.FullName $dstSkill -Recurse -Force
                $installed++
            }
        }
        if ($UpdateSkills) {
            Write-Ok "$installed kit skill(s) re-installed to ~/.claude/skills ($backedUp previous copy/ies backed up to .bak-kit)"
        } else {
            Write-Ok "$installed kit skill(s) installed to ~/.claude/skills (skipped existing; use -UpdateSkills to refresh)"
        }
    }

    # Ship the kit's Claude Code slash commands (~/.claude/commands), e.g. /images.
    $cmdsSrc = Join-Path $PSScriptRoot 'commands'
    $cmdsDst = Join-Path $ccDir 'commands'
    if (Test-Path $cmdsSrc) {
        New-Item -ItemType Directory -Force -Path $cmdsDst | Out-Null
        $cmdCount = 0
        foreach ($cmdFile in Get-ChildItem $cmdsSrc -File) {
            Copy-Item $cmdFile.FullName (Join-Path $cmdsDst $cmdFile.Name) -Force
            $cmdCount++
        }
        Write-Ok "$cmdCount Claude Code command(s) installed to ~/.claude/commands (e.g. /images)"
    }
}

# ---------- 9a2. VS Code keybinding for quick model switching ----------
Write-Step 'Adding VS Code keybinding: Ctrl+Alt+M -> focus Claude Code input (then /cycle-model)'
$vscodeUser = Join-Path $env:APPDATA 'Code\User'
$kbFile = Join-Path $vscodeUser 'keybindings.json'
New-Item -ItemType Directory -Force -Path $vscodeUser | Out-Null
$bindings = @()
if (Test-Path $kbFile) {
    try {
        $existing = Get-Content $kbFile -Raw | ConvertFrom-Json
        if ($existing) { $bindings = @($existing) }
    } catch { Write-Warn "keybindings.json unreadable - rewriting from scratch" }
}
$found = $false
foreach ($b in $bindings) {
    if ($b.command -eq 'claude-vscode.focus') { $found = $true }
}
if (-not $found) {
    $bindings += [pscustomobject]@{ key = 'ctrl+alt+m'; command = 'claude-vscode.focus'; when = 'editorTextFocus || terminalFocus' }
    $json = $bindings | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText($kbFile, $json, (New-Object System.Text.UTF8Encoding($false)))
    Write-Ok 'Ctrl+Alt+M -> Claude Code: Focus input (then type /cycle-model)'
} else {
    Write-Ok 'keybinding already present - skipped'
}

# ---------- 9b. extra MCPs + skills.sh ----------
if (-not $SkipClaudeCode) {
    Write-Step 'Installing extra MCP servers + skills.sh (all idempotent)'

    # Global npm packages powering the MCP servers. Installed once; re-runs skip
    # (a package is 'present' when its bin command exists on PATH).
    $mcpBins = 'playwright-mcp', 'context7-mcp', 'chrome-devtools-mcp', 'mcp-server-memory', 'mcp-server-filesystem', 'mcp-server-sequential-thinking', 'mcp-server-everything', 'mcp-fetch', 'mcp-server-github', 'skills'
    $mcpPackages = @('@playwright/mcp', '@upstash/context7-mcp', 'chrome-devtools-mcp', '@modelcontextprotocol/server-memory', '@modelcontextprotocol/server-filesystem', '@modelcontextprotocol/server-sequential-thinking', '@modelcontextprotocol/server-everything', 'mcp-fetch', '@modelcontextprotocol/server-github', 'skills')
    $needInstall = @()
    for ($i = 0; $i -lt $mcpBins.Count; $i++) {
        if (-not (Get-Command $mcpBins[$i] -ErrorAction SilentlyContinue)) { $needInstall += $mcpPackages[$i] }
    }
    if ($needInstall.Count -gt 0) {
        Write-Host "    npm i -g $($needInstall -join ' ') (one-time)" -ForegroundColor DarkGray
        & npm install -g $needInstall 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Ok "installed $($needInstall.Count) global package(s)" }
        else { Write-Warn 'npm install failed - MCP servers may not start; re-run setup.ps1 to retry' }
    } else {
        Write-Ok 'all MCP packages already installed globally'
    }

    # Register each MCP server (idempotent: claude mcp add replaces existing).
    function Add-Mcp([string]$name, [string]$cmd, [string[]]$mcpArgs = @(), [hashtable]$mcpEnv = @{}) {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
            Write-Warn "$cmd not found - skipping MCP '$name'"
            return
        }
        # claude.exe writes errors to stderr even for benign cases (e.g. "no
        # MCP server named X" when removing an unregistered server). With
        # $ErrorActionPreference='Stop' that would abort the script, so scope
        # the preference down around the CLI calls and report via $LASTEXITCODE.
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'SilentlyContinue'
        try {
            & claude mcp remove $name 2>$null | Out-Null
            # Server flags go after `--` so the CLI passes them to the server
            # command instead of parsing them as its own options.
            $argList = @('-s', 'user', $name)
            foreach ($k in $mcpEnv.Keys) { $argList += '--env'; $argList += "$k=$($mcpEnv[$k])" }
            $argList += '--'
            $argList += $cmd
            foreach ($a in $mcpArgs) { $argList += $a }
            & claude mcp add @argList 2>$null | Out-Null
        } catch {
            # reported via $LASTEXITCODE below
        } finally {
            $ErrorActionPreference = $prevEap
        }
        if ($LASTEXITCODE -eq 0) { Write-Ok "MCP '$name' registered" }
        else { Write-Warn "claude mcp add $name failed" }
    }

    Add-Mcp 'playwright' 'playwright-mcp'
    Add-Mcp 'context7' 'context7-mcp'
    Add-Mcp 'chrome-devtools' 'chrome-devtools-mcp'
    Add-Mcp 'sequential-thinking' 'mcp-server-sequential-thinking'
    Add-Mcp 'everything' 'mcp-server-everything'
    Add-Mcp 'fetch' 'mcp-fetch'
    $memDir = Join-Path $ccDir 'memory'
    New-Item -ItemType Directory -Force -Path $memDir | Out-Null
    Add-Mcp 'memory' 'mcp-server-memory' @('--storage-path', (Join-Path $memDir 'memory.json'))
    Add-Mcp 'filesystem' 'mcp-server-filesystem' @($HOME)

    # GitHub MCP only if gh is authenticated on this machine.
    $ghToken = gh auth token 2>$null
    if ($ghToken) {
        Add-Mcp 'github' 'mcp-server-github' @() @{ GITHUB_PERSONAL_ACCESS_TOKEN = $ghToken }
    } else {
        Write-Warn 'gh not authenticated - skipping GitHub MCP (run "gh auth login" then re-run setup)'
    }

    # skills.sh CLI + a curated set of high-value skills for Claude Code.
    $curated = @('tdd', 'diagnosing-bugs', 'improve-codebase-architecture', 'grill-me', 'vercel-react-best-practices', 'deploy-to-vercel')
    & skills add mattpocock/skills --skill tdd --skill diagnosing-bugs --skill improve-codebase-architecture --skill grill-me -g -a claude-code --copy -y 2>&1 | Out-Null
    & skills add vercel-labs/agent-skills --skill vercel-react-best-practices --skill deploy-to-vercel -g -a claude-code --copy -y 2>&1 | Out-Null
    Write-Ok "skills.sh ready - curated skills installed: $($curated -join ', ')"
    Write-Host '    discover more with:  skills find <keyword>   |   browse skills.sh' -ForegroundColor DarkGray
    Write-Host '    add more with:       skills add <owner>/<repo> --skill <name> -g -a claude-code' -ForegroundColor DarkGray
}

# ---------- 9c. Claude Desktop (official app - Code tab uses the gateway) ----------
if (-not $SkipClaudeCode) {
    Write-Step 'Claude Desktop (official app - no extension needed)'
    $desktopExe = @(
        (Join-Path $env:LOCALAPPDATA 'AnthropicClaude\claude.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\claude\claude.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Claude\claude.exe')
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($desktopExe) {
        Write-Ok "Claude Desktop already installed: $desktopExe"
        Write-Ok '   the Code tab reads ~/.claude/settings.json, so it already routes through this gateway.'
    } else {
        Write-Host '    downloading the official Claude Desktop installer (claude.ai)...'
        $dl = Join-Path $env:TEMP 'claude-desktop-setup.exe'
        $launched = $false
        try {
            Invoke-WebRequest -Uri 'https://claude.ai/api/desktop/win32/x64/exe/latest/redirect' -OutFile $dl -UseBasicParsing -TimeoutSec 180
            # claude.ai sits behind a Cloudflare challenge - verify we actually got
            # an EXE (starts with 'MZ'), not a 'Just a moment...' HTML challenge page.
            $head = Get-Content -Path $dl -Encoding Byte -TotalCount 2
            $isExe = ($head[0] -eq 0x4D) -and ($head[1] -eq 0x5A)
            if (-not $isExe) { throw 'got a Cloudflare challenge page instead of the installer' }
            Write-Ok "downloaded to $dl - launching the installer now"
            Start-Process -FilePath $dl
            $launched = $true
        } catch {
            Write-Warn "Automatic download blocked: $_"
            Write-Warn '    Opening the official download page in your browser instead - click "Download for Windows"'
            Write-Warn '    there (a real browser passes the Cloudflare check that scripts cannot).'
            Start-Process 'https://claude.com/download'
        }
        Write-Host ''
        if ($launched) {
            Write-Host '    After installing: sign in with any Claude account, open the CODE tab,' -ForegroundColor Yellow
        } else {
            Write-Host '    After the browser download finishes, run the installer, sign in with any' -ForegroundColor Yellow
            Write-Host '    Claude account, open the CODE tab,' -ForegroundColor Yellow
        }
        Write-Host '    pick Local + a project folder, and start a session - it routes through' -ForegroundColor Yellow
        Write-Host '    http://localhost:20128 (your free gateway) automatically - no extension.' -ForegroundColor Yellow
        Write-Host '    (The app hides non-Claude model names in its picker, but ANTHROPIC_MODEL' -ForegroundColor DarkGray
        Write-Host '     pins auto/coding:reliable regardless - that is expected.)' -ForegroundColor DarkGray
        Write-Host '    Deep option - route the app itself (Chat tab included):' -ForegroundColor DarkGray
        Write-Host '      Settings -> Developer -> Inference provider = Gateway' -ForegroundColor DarkGray
        Write-Host "      Gateway base URL: $Base    Auth scheme: bearer    API key: omniroute" -ForegroundColor DarkGray
    }
}

# ---------- 9d. Codex CLI (OpenAI's agent CLI, wired through the gateway) ----------
# Current Codex (>= ~0.134) accepts ONLY the Responses API for custom providers
# (wire_api = "responses" is the only supported value), so this relies on the
# gateway's native /v1/responses endpoint - no adapter needed. The gateway's
# localhost magic token 'omniroute' is not a real secret, so it is stored
# inline (same philosophy as ANTHROPIC_AUTH_TOKEN for Claude Code).
if (-not $SkipCodex) {
    if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {
        Write-Step 'Installing the Codex CLI (npm i -g @openai/codex)'
        & npm install -g @openai/codex 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Ok "codex $(codex --version 2>$null)" }
        else { Write-Warn 'codex install failed - re-run setup.ps1 after fixing npm' }
    }

    Write-Step 'Wiring the Codex CLI to the gateway (Responses API)'
    $codexDir = Join-Path $HOME '.codex'
    New-Item -ItemType Directory -Force -Path $codexDir | Out-Null
    $codexCfg = Join-Path $codexDir 'config.toml'
    $codexToml = @"
# Codex CLI -> OmniRoute free gateway (localhost) - written by setup.ps1 (kit).
model = "auto/coding:reliable"
model_provider = "omniroute"

[model_providers.omniroute]
name = "OmniRoute free pool (localhost:$Port)"
base_url = "http://localhost:$Port/v1"
# The gateway's localhost magic token - not a real secret (localhost-only),
# same value the kit uses for Claude Code's ANTHROPIC_AUTH_TOKEN.
experimental_bearer_token = "omniroute"
"@
    $prevCodex = Get-Content $codexCfg -Raw -ErrorAction SilentlyContinue
    if ($prevCodex -and $prevCodex -notmatch 'model_providers\.omniroute') {
        Copy-Item $codexCfg "$codexCfg.bak-kit" -Force
        Write-Ok "existing $codexCfg backed up to config.toml.bak-kit (omniroute provider block was missing)"
    }
    [System.IO.File]::WriteAllText($codexCfg, $codexToml, (New-Object System.Text.UTF8Encoding($false)))
    Write-Ok '~/.codex/config.toml -> model_provider omniroute (Responses API - the only wire protocol current Codex accepts)'
    Write-Host '    switch models any time with: codex -m <model>   (e.g. codex -m auto/best-fast, codex -m combo/qwen)' -ForegroundColor DarkGray

    # Model profiles: `codex --profile <name>` overlays ~/.codex/<name>.config.toml
    # on top of the base config, so one flag switches the gateway route.
    $codexProfiles = @{
        fast      = 'auto/best-fast'
        coding    = 'auto/best-coding'
        reasoning = 'auto/best-reasoning'
        vision    = 'auto/best-vision'
    }
    foreach ($p in ($codexProfiles.Keys | Sort-Object)) {
        $pf = Join-Path $codexDir "$p.config.toml"
        $pt = "# Codex profile '$p' - written by setup.ps1 (kit).`nmodel = `"$($codexProfiles[$p])`"`n"
        [System.IO.File]::WriteAllText($pf, $pt, (New-Object System.Text.UTF8Encoding($false)))
    }
    Write-Ok "Codex profiles: $((($codexProfiles.Keys | Sort-Object) -join ', ')) - use 'codex --profile <name>'"

    # Codex's /model picker only lists OpenAI's built-in models by default.
    # fix-model-cache.ps1 generates a model_catalog_json from the live gateway
    # catalog (auto/*, combo/*, lmarena/*, mimo-web/*, ...) and reconciles
    # config.toml (adds the root-level model_catalog_json + keeps the default
    # model on the gateway), so the picker shows every gateway route. Run it
    # AFTER writing the base config above so the catalog line survives.
    $codexCacheScript = Join-Path $KitRoot 'fix-model-cache.ps1'
    if (Test-Path $codexCacheScript) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $codexCacheScript -Base $Base -CombosOnly | ForEach-Object { Write-Ok $_ }
        Write-Ok "Codex /model picker -> gateway routes via model_catalog_json (~/.codex/model-catalogs/omniroute.json)"
    } else {
        Write-Warn 'fix-model-cache.ps1 missing - Codex picker will only show OpenAI built-ins'
    }
}

# ---------- 10. auto-start (fully hidden - no console windows at login) ----------
if (-not $SkipAutoStart) {
    Write-Step 'Registering auto-start at login (hidden - no console windows)'
    $startup = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
    if (Test-Path $startup) {
        # Every service starts through a tiny .vbs launcher that runs its .cmd
        # with window style 0 (hidden): no console window, no flash at login.
        # The .cmd files stay the source of truth in the kit (visible when run
        # manually), the Startup copy is just the invisible wrapper. Targets use
        # %USERPROFILE% at runtime so the same files work on any machine.
        # IMPORTANT: ExpandEnvironmentStrings only expands %VAR% tokens - a bare
        # name (e.g. "USERPROFILE") is returned unchanged, which made every
        # Startup .vbs build a bogus relative path (USERPROFILE\.omniroute\...) and
        # pop a "file not found" dialog at every login. Use %USERPROFILE% here.
        # Also: if the target is ever missing, log to ~\.omniroute\vbs-errors.log
        # instead of showing a dialog (On Error Resume Next + existence check),
        # so the logon can never be interrupted by an error box again.
        $vbsTpl = @'
On Error Resume Next
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
target = sh.ExpandEnvironmentStrings("%USERPROFILE%") & "<TARGET>"
If fso.FileExists(target) Then
  sh.Run """" & target & """", 0, False
Else
  Set log = fso.OpenTextFile(sh.ExpandEnvironmentStrings("%USERPROFILE%") & "\.omniroute\vbs-errors.log", 8, True)
  log.WriteLine Now & " MISSING: " & target
  log.Close
End If
'@
        function Write-HiddenStartup([string]$name, [string]$target) {
            $content = $vbsTpl.Replace('<TARGET>', $target)
            [System.IO.File]::WriteAllText(
                (Join-Path $startup "$name.vbs"),
                $content,
                (New-Object System.Text.UTF8Encoding($false))
            )
        }

        # Remove the old visible .cmd Startup entries this script used to create
        # (they opened + held console windows at every login).
        foreach ($old in @('OmniRoute.cmd','FlowUI-Bridge.cmd','Gemini-Bridge.cmd','MiMo-Bridge.cmd','FixModelCache.cmd')) {
            $oldPath = Join-Path $startup $old
            if (Test-Path $oldPath) { Remove-Item $oldPath -Force }
        }

        Write-HiddenStartup 'OmniRoute' '\.omniroute\start-omniroute.cmd'
        Write-Ok 'OmniRoute.vbs -> Startup folder (gateway starts at login, hidden)'
        if ($flowOk) {
            Write-HiddenStartup 'FlowUI-Bridge' '\omniroute-setup-kit\bridge\flow-browser\start-flow-browser.cmd'
            Write-Ok 'FlowUI-Bridge.vbs -> Startup folder (flowui image bridge starts at login, hidden + headless)'
        }
        if ($mimoBridgeOk) {
            Write-HiddenStartup 'MiMo-Bridge' '\.omniroute\bridge\mimo-web-bridge\start-bridge.cmd'
            Write-Ok 'MiMo-Bridge.vbs -> Startup folder (mimo-web chat bridge starts at login, hidden)'
        }
        if ($bridgeOk) {
            Write-HiddenStartup 'Gemini-Bridge' '\omniroute-setup-kit\bridge\gemini-bridge\start-bridge.cmd'
            Write-Ok 'Gemini-Bridge.vbs -> Startup folder (gflow image bridge starts at login, hidden)'
        }
        if (Test-Path (Join-Path $KitRoot 'fix-model-cache.cmd')) {
            Write-HiddenStartup 'FixModelCache' '\omniroute-setup-kit\fix-model-cache.cmd'
            # The logon cmd resolves fix-model-cache.ps1 from ~\.omniroute (it
            # cannot ship the ps1 next to the Startup copy), so keep the script +
            # its patch helpers fresh there - the logon self-heal silently did
            # nothing before this (no ps1 next to the Startup .cmd).
            foreach ($f in @('fix-model-cache.ps1', 'patch-claude-picker.mjs', 'patch-zai-captcha-headed.mjs', 'guard-startup-vbs.ps1')) {
                $src = Join-Path $KitRoot $f
                if (Test-Path $src) { Copy-Item $src (Join-Path $omHome $f) -Force }
            }
            Write-Ok 'FixModelCache.vbs -> Startup folder (/model picker patch + zai headless patch re-applied at every login, hidden)'
        }

        # Gateway + bridge watchdog: probes every 5 min, restarts a wedged
        # gateway (listening but not answering HTTP), re-syncs combo/* routes
        # after a restart, and restarts any down bridge - all hidden. Runs from
        # the stable ~/.omniroute copy, not this worktree. The logon run is a
        # Startup .vbs (below) - Register-ScheduledTask and schtasks /XML are
        # blocked (Access denied) on some machines, while plain schtasks /SC
        # MINUTE and Startup .vbs both work, so we use those.
        $wdSrc = Join-Path $KitRoot 'launcher\watchdog.ps1'
        $wdDst = Join-Path $omHome 'watchdog.ps1'
        if (Test-Path $wdSrc) {
            Copy-Item $wdSrc $wdDst -Force
            $wdTask = "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$wdDst`""
            schtasks /Create /TN 'OmniRoute-Watchdog' /TR $wdTask /SC MINUTE /MO 5 /F | Out-Null
            Write-Ok 'OmniRoute-Watchdog scheduled task -> gateway + bridges probed every 5 min, all restarts hidden'

            # Logon run: hidden .vbs that waits 90s (let the Startup services
            # cold-start first) then runs the watchdog once.
            # Same %USERPROFILE% fix as the template above - the bare name was
            # returned unexpanded, so the logon watchdog run silently pointed at
            # a relative path and never executed.
            $wdVbs = @"
' Watchdog.vbs - run the OmniRoute watchdog 90s after logon, fully hidden.
WScript.Sleep 90000
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & sh.ExpandEnvironmentStrings("%USERPROFILE%") & "\.omniroute\watchdog.ps1""", 0, False
"@
            [System.IO.File]::WriteAllText(
                (Join-Path $startup 'Watchdog.vbs'),
                $wdVbs,
                (New-Object System.Text.UTF8Encoding($false))
            )
            Write-Ok 'Watchdog.vbs -> Startup folder (watchdog also runs once 90s after logon, hidden)'
        } else {
            Write-Warn 'launcher\watchdog.ps1 missing - no gateway watchdog scheduled task'
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
if (-not $SkipClaudeCode) { Write-Host "  Claude Code: wired (run 'claude' or the Claude Desktop Code tab - /model shows the gateway routes)" }
if (-not $SkipCodex) { Write-Host "  Codex CLI   : wired (run 'codex' - auto/coding:reliable via the gateway, /model shows the gateway routes)" }
Write-Host '  Watchdog    : OmniRoute-Watchdog scheduled task - wedged gateway auto-restarted + combo/* re-synced every 5 min'
if ($flowOk) {
    Write-Host '  Flow images : flowui/nano-banana-2 via bridge\flow-browser\start-flow-browser.cmd (headless, auto-starts)'
    Write-Host '                image requests route through the generate_image MCP tool -> same engine, same quality'
}
if ($bridgeOk) {
    Write-Host '  gflow images: gflow/nano-banana-2 via bridge\gemini-bridge\start-bridge.cmd (token method, auto-starts)'
}
if ($mimoBridgeOk) {
    Write-Host '  MiMo web    : mimo-web/mimo-v2.5, mimo-web/mimo-v2.5-pro, combo/mimo-web via bridge\mimo-web-bridge (auto-starts)'
    Write-Host '                sign in at aistudio.xiaomimimo.com, then Cookie Pusher -> Grab & push sessions once'
}
Write-Host ''
Write-Host '  Last step, once, ~1 minute:' -ForegroundColor Yellow
Write-Host "    1. Open edge://extensions (or chrome://extensions)"
Write-Host '    2. Turn on Developer mode'
Write-Host "    3. Load unpacked -> $HOME\omniroute-cookie-pusher"
Write-Host '    4. Click the extension icon -> Grab & push sessions'
Write-Host ''
Write-Host '  Models:  nvidia/<model>   (Nemotron Ultra 550B, Omni vision, DeepSeek V4 Pro, GLM-5.2, ...)'
Write-Host '           opencode-zen/*-free  (deepseek-v4-flash-free, mimo-v2.5-free, big-pickle, ...)'
Write-Host '           openrouter/*:free    (OpenRouter free tier - needs OPENROUTER_API_KEY)'
Write-Host '           auto            (fallback pool: felo, opencode built-in, agy, blackbox, ...)'
Write-Host '=================================================' -ForegroundColor Cyan
