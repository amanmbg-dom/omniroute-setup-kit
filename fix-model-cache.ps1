<#
.SYNOPSIS
  One command that (1) ensures the MiMo web bridge is running + registered,
  (2) creates the per-family combo/* routing routes for the cookie/web
  providers (combo/qwen, combo/glm, combo/deepseek, combo/lmarena, combo/mimo,
  combo/mimo-web, combo/lmarena-fast/slow) via the dashboard API, (3) enables Claude Code's gateway model
  discovery (env vars + native-binary patch) so the /model picker shows the FULL live gateway catalog,
  (4) seeds Claude Code's gateway-model cache (for older binaries that read it) so the
  /model picker shows the "auto" majors + combo/* routes + ALIVE NVIDIA NIM
  (nvidia/*) + the free OpenCode Zen routes (opencode-zen/*-free, oc/*-free,
  big-pickle) + the web-cookie chat routes (incl. mimo-web/*), and (5) mirrors all of it into
  availableModels - and keeps it that way across re-runs.

  -PickerOnly: ONLY the picker self-heal (env vars + binary patch on the VS Code
  extension AND the standalone ~/.local/bin/claude.exe CLI). Used by the gateway
  watchdog every 5 minutes so an auto-updated binary is re-patched within minutes
  instead of waiting for the next logon. Idempotent; retried automatically when a
  running Claude Code session locks the binary.
.DESCRIPTION
  Claude Code >= 2.1.233 filters the gateway catalog to claude/anthropic-named ids when
  building the /model picker - in TWO places: the [Bootstrap] fetch AND the
  [gatewayDiscovery] periodic refetch (the refetch replaces the cached model list,
  collapsing the picker back to claude-named models even after the bootstrap site is
  patched - the "it worked, then broke again" loop). This script sets
  CLAUDE_CODE_USE_GATEWAY + CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY and byte-patches
  BOTH filter sites in every installed Claude Code binary (the VS Code extension's
  native binary AND the standalone ~/.local/bin/claude.exe CLI) via
  patch-claude-picker.mjs (same-length byte replace, idempotent) so every gateway route
  shows in the picker. It also seeds ~/.claude/cache/gateway-models.json with the
  curated routes below (a superset of what the curated /v1/models refetch can return,
  so the refetch can never replace it with a claude-named-only subset) and pins
  fetchedAt ~1 year out for older Claude Code builds that read the cache directly.

  Dead NIM models (404 upstream on build.nvidia.com) and non-chat models
  (embed/rerank/asr/tts/image-gen/parse) are excluded, so the picker only shows
  routes that actually answer /v1/chat/completions.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File fix-model-cache.ps1
  powershell -ExecutionPolicy Bypass -File fix-model-cache.ps1 -Base http://localhost:20128
  powershell -ExecutionPolicy Bypass -File fix-model-cache.ps1 -PickerOnly   (watchdog fast heal: env vars + binary patch only)
#>
param(
    [string]$Base = 'http://localhost:20128',
    [string]$Token = 'omniroute',
    [switch]$CombosOnly,
    [switch]$PickerOnly
)
$ErrorActionPreference = 'Stop'

# ---- 0.5. self-healing Startup .vbs guard ----
# Keep the login .vbs launchers on the hardened template (%USERPROFILE% +
# On Error Resume Next + log fallback). The watchdog scheduled task runs the
# same check every 5 min (immune to vbs breakage); this copy just repairs
# immediately at login when the vbs chain itself is healthy.
$guardScript = $null
foreach ($cand in @(
    (Join-Path $PSScriptRoot 'guard-startup-vbs.ps1'),
    (Join-Path $HOME '.omniroute\guard-startup-vbs.ps1'),
    (Join-Path $HOME 'omniroute-setup-kit\guard-startup-vbs.ps1')
)) { if (Test-Path $cand) { $guardScript = $cand; break } }
if ($guardScript) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $guardScript 2>&1 | Out-Null
}

# ---- 1. NIM models known to be dead or non-chat. The canonical list lives in
#         config/nvidia-dead.json (shared with setup.ps1). 404 = retired from
#         build.nvidia.com; the rest are non-chat (image gen, parse, video) or
#         500 upstream. Verified by probing every nvidia/* route against
#         /v1/chat/completions on 2026-08-14. This embedded copy is the fallback
#         for standalone use of this script without the kit's config dir.
$nvidiaDead = @()
$deadJsonCandidates = @(
    (Join-Path $PSScriptRoot 'config\nvidia-dead.json'),
    (Join-Path $HOME 'omniroute-setup-kit\config\nvidia-dead.json'),
    (Join-Path $HOME '.omniroute\config\nvidia-dead.json')
)
foreach ($cand in $deadJsonCandidates) {
    if (Test-Path $cand) {
        # NB: direct call, not a pipeline - PS 5.1 ConvertFrom-Json unrolls
        # arrays when fed via the pipeline, silently turning 75 entries into 1.
        $nvidiaDead = @((ConvertFrom-Json (Get-Content $cand -Raw)))
        break
    }
}
if ($nvidiaDead.Count -eq 0) {
    $nvidiaDead = @(
        'nvidia/adept/fuyu-8b','nvidia/ai21labs/jamba-1.5-large-instruct','nvidia/aisingapore/sea-lion-7b-instruct',
        'nvidia/bigcode/starcoder2-15b','nvidia/01-ai/yi-large','nvidia/baai/bge-m3','nvidia/databricks/dbrx-instruct',
        'nvidia/deepseek-ai/deepseek-coder-6.7b-instruct','nvidia/google/codegemma-1.1-7b','nvidia/google/codegemma-7b',
        'nvidia/google/deplot','nvidia/google/gemma-2b','nvidia/google/gemma-3-4b-it','nvidia/google/gemma-3-12b-it',
        'nvidia/google/recurrentgemma-2b','nvidia/ibm/granite-3.0-3b-a800m-instruct','nvidia/ibm/granite-3.0-8b-instruct',
        'nvidia/ibm/granite-34b-code-instruct','nvidia/ibm/granite-8b-code-instruct','nvidia/meta/codellama-70b',
        'nvidia/meta/llama2-70b','nvidia/microsoft/kosmos-2','nvidia/mistralai/mistral-large',
        'nvidia/microsoft/phi-3-vision-128k-instruct','nvidia/microsoft/phi-3.5-moe-instruct',
        'nvidia/mistralai/codestral-22b-instruct-v0.1','nvidia/mistralai/mistral-7b-instruct-v0.3',
        'nvidia/mistralai/mistral-large-2-instruct','nvidia/mistralai/mixtral-8x22b-v0.1','nvidia/moonshotai/kimi-k2.6',
        'nvidia/nv-mistralai/mistral-nemo-12b-instruct','nvidia/nvidia/cosmos-reason2-8b','nvidia/nvidia/embed-qa-4',
        'nvidia/nvidia/llama-3.1-nemotron-51b-instruct','nvidia/nvidia/llama-3.1-nemotron-70b-instruct',
        'nvidia/nvidia/llama-3.1-nemotron-ultra-253b-v1','nvidia/nvidia/llama-3.2-nemoretriever-1b-vlm-embed-v1',
        'nvidia/nvidia/llama-3.2-nv-embedqa-1b-v1','nvidia/nvidia/llama-nemotron-embed-1b-v2',
        'nvidia/nvidia/llama-nemotron-embed-vl-1b-v2','nvidia/nvidia/mistral-nemo-minitron-8b-8k-instruct',
        'nvidia/nvidia/nemotron-3-embed-1b','nvidia/nvidia/llama3-chatqa-1.5-70b','nvidia/nvidia/nv-embed-v1',
        'nvidia/nvidia/nemotron-4-340b-instruct','nvidia/nvidia/nemotron-4-340b-reward','nvidia/nvidia/nemotron-nano-3-30b-a3b',
        'nvidia/nvidia/neva-22b','nvidia/nvidia/nv-embedcode-7b-v1','nvidia/nvidia/nv-embedqa-e5-v5',
        'nvidia/nvidia/nv-embedqa-mistral-7b-v2','nvidia/nvidia/nvclip','nvidia/nvidia/riva-translate-4b-instruct',
        'nvidia/nvidia/vila','nvidia/snowflake/arctic-embed-l','nvidia/writer/palmyra-creative-122b',
        'nvidia/writer/palmyra-fin-70b-32k','nvidia/writer/palmyra-med-70b','nvidia/writer/palmyra-med-70b-32k',
        'nvidia/nv-rerankqa-mistral-4b-v3','nvidia/zyphra/zamba2-7b-instruct','nvidia/parakeet-ctc-1.1b-asr',
        'nvidia/nv-embedqa-e5-v5','nvidia/openai/whisper-large-v3','nvidia/fastpitch','nvidia/tacotron2',
        'nvidia/black-forest-labs/flux.1-dev','nvidia/black-forest-labs/flux.1-schnell',
        'nvidia/black-forest-labs/flux.1-kontext-dev','nvidia/black-forest-labs/flux.2-klein-4b',
        'nvidia/nvidia/nemoretriever-parse','nvidia/nvidia/nemotron-parse',
        'nvidia/nvidia/ai-synthetic-video-detector','nvidia/mistralai/mistral-nemotron'
    )
}
# Safety net: never seed obvious non-chat model families even if not listed above.
# NOTE: 'diffusion' and 'translate' are intentionally NOT here - the live NIM
# catalog serves diffusiongemma-26b-a4b-it and riva-translate-4b-instruct
# v1.1/v2 via the chat endpoint (probed alive 2026-08-14), and the dead
# variants are already enumerated explicitly in config/nvidia-dead.json.
$deadPattern = 'embed|rerank|asr|tts|whisper|fastpitch|tacotron|nvclip|flux|parse|detector|reward|neva|vila|kosmos|deplot|fuyu'

# ---- 1.5. ensure the MiMo web bridge is running + registered ----
# mimo-web is a local OpenAI-compatible bridge (bridge/mimo-web-bridge/bridge.mjs)
# that translates OpenAI chat to the aistudio.xiaomimimo.com web API using your
# session cookie (pushed by the Cookie Pusher -> Grab & push sessions). It must
# be up BEFORE the catalog fetch below so the mimo-web/* routes are discovered.
if (-not $PickerOnly) {
$bridgePort = 20135
$bridgeUp = $false
try {
    $probe = Invoke-WebRequest -Uri "http://127.0.0.1:$bridgePort/healthz" -TimeoutSec 3 -UseBasicParsing
    $bridgeUp = ($probe.StatusCode -eq 200)
} catch { $bridgeUp = $false }
if (-not $bridgeUp) {
    $bridgeScript = $null
    foreach ($cand in @(
        (Join-Path $PSScriptRoot 'bridge\mimo-web-bridge\bridge.mjs'),
        (Join-Path $HOME 'omniroute-setup-kit\bridge\mimo-web-bridge\bridge.mjs'),
        (Join-Path $HOME '.omniroute\bridge\mimo-web-bridge\bridge.mjs')
    )) { if (Test-Path $cand) { $bridgeScript = $cand; break } }
    if ($bridgeScript) {
        $bridgeLog = Join-Path $HOME '.omniroute\mimo-web-bridge.log'
        # NB: PS 5.1 Start-Process REJECTS identical stdout/stderr redirect paths
        # ("RedirectStandardOutput and RedirectStandardError are same") - the
        # bridge-start branch silently crashed whenever the bridge was actually
        # down. Use a separate .err file.
        Start-Process -FilePath 'node' -ArgumentList @($bridgeScript) -WindowStyle Hidden `
            -RedirectStandardOutput $bridgeLog -RedirectStandardError "$bridgeLog.err"
        Start-Sleep -Seconds 2
        try {
            $probe = Invoke-WebRequest -Uri "http://127.0.0.1:$bridgePort/healthz" -TimeoutSec 3 -UseBasicParsing
            $bridgeUp = ($probe.StatusCode -eq 200)
        } catch { $bridgeUp = $false }
        if ($bridgeUp) { Write-Host "MiMo web bridge started ($bridgeScript)" -ForegroundColor Green }
        else { Write-Host 'MiMo web bridge NOT running (node missing?) - mimo-web routes will not appear' -ForegroundColor Yellow }
    } else {
        Write-Host 'MiMo web bridge script not found - mimo-web routes skipped' -ForegroundColor Yellow
    }
} else {
    Write-Host 'MiMo web bridge already running' -ForegroundColor DarkGray
}
if ($bridgeUp) {
    $registerScript = $null
    foreach ($cand in @(
        (Join-Path $PSScriptRoot 'bridge\mimo-web-bridge\register-mimo-web.mjs'),
        (Join-Path $HOME 'omniroute-setup-kit\bridge\mimo-web-bridge\register-mimo-web.mjs'),
        (Join-Path $HOME '.omniroute\bridge\mimo-web-bridge\register-mimo-web.mjs')
    )) { if (Test-Path $cand) { $registerScript = $cand; break } }
    if ($registerScript) {
        & node $registerScript | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Host 'mimo-web node + connection registered' -ForegroundColor DarkGray }
    }
}

# ---- 1.5.5. ensure the DeepSeek web bridge is running + registered ----
# deepseek-web is a local OpenAI-compatible bridge (bridge/deepseek-web-bridge/
# bridge.mjs) that answers deepseek-web/* with AUTO-CONTINUE: DeepSeek's web API
# ends long responses with status INCOMPLETE (the "Continue generating" button)
# and the gateway's built-in executor truncates there. The bridge continues the
# stream automatically (up to 8 rounds) so long chats complete. Token (userToken)
# is pushed by Cookie Pusher -> Grab & push sessions.
$dsBridgePort = 20136
$dsBridgeUp = $false
try {
    $probe = Invoke-WebRequest -Uri "http://127.0.0.1:$dsBridgePort/healthz" -TimeoutSec 3 -UseBasicParsing
    $dsBridgeUp = ($probe.StatusCode -eq 200)
} catch { $dsBridgeUp = $false }
if (-not $dsBridgeUp) {
    $dsBridgeScript = $null
    foreach ($cand in @(
        (Join-Path $PSScriptRoot 'bridge\deepseek-web-bridge\bridge.mjs'),
        (Join-Path $HOME 'omniroute-setup-kit\bridge\deepseek-web-bridge\bridge.mjs'),
        (Join-Path $HOME '.omniroute\bridge\deepseek-web-bridge\bridge.mjs')
    )) { if (Test-Path $cand) { $dsBridgeScript = $cand; break } }
    if ($dsBridgeScript) {
        $dsBridgeLog = Join-Path $HOME '.omniroute\deepseek-web-bridge.log'
        # NB: PS 5.1 Start-Process REJECTS identical stdout/stderr redirect paths
        # - use a separate .err file (same bug as the mimo bridge start).
        Start-Process -FilePath 'node' -ArgumentList @($dsBridgeScript) -WindowStyle Hidden `
            -RedirectStandardOutput $dsBridgeLog -RedirectStandardError "$dsBridgeLog.err"
        Start-Sleep -Seconds 2
        try {
            $probe = Invoke-WebRequest -Uri "http://127.0.0.1:$dsBridgePort/healthz" -TimeoutSec 3 -UseBasicParsing
            $dsBridgeUp = ($probe.StatusCode -eq 200)
        } catch { $dsBridgeUp = $false }
        if ($dsBridgeUp) { Write-Host "DeepSeek web bridge started ($dsBridgeScript, auto-continue)" -ForegroundColor Green }
        else { Write-Host 'DeepSeek web bridge NOT running (node missing?) - deepseek-web routes will not appear' -ForegroundColor Yellow }
    } else {
        Write-Host 'DeepSeek web bridge script not found - deepseek-web routes skipped' -ForegroundColor Yellow
    }
} else {
    Write-Host 'DeepSeek web bridge already running' -ForegroundColor DarkGray
}
if ($dsBridgeUp) {
    $dsRegisterScript = $null
    foreach ($cand in @(
        (Join-Path $PSScriptRoot 'bridge\deepseek-web-bridge\register-deepseek-web.mjs'),
        (Join-Path $HOME 'omniroute-setup-kit\bridge\deepseek-web-bridge\register-deepseek-web.mjs'),
        (Join-Path $HOME '.omniroute\bridge\deepseek-web-bridge\register-deepseek-web.mjs')
    )) { if (Test-Path $cand) { $dsRegisterScript = $cand; break } }
    if ($dsRegisterScript) {
        & node $dsRegisterScript | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Host 'deepseek-web node + connection registered' -ForegroundColor DarkGray }
    }
}

} # end -PickerOnly skip (bridges)

# ---- 1.6.5. fast modes ----
# -CombosOnly: skip the Claude Code picker patch, cache seed and availableModels
# rebuild (used by the gateway watchdog after a restart - it only needs the
# mimo-web bridge up + combo/* routes re-created + the Codex catalog refreshed).
# -PickerOnly: ONLY the Claude Code picker self-heal (env vars + binary patch on
# the VS Code extension AND the standalone ~/.local/bin/claude.exe CLI), used by
# the gateway watchdog every 5 min so an auto-updated binary is re-patched within
# minutes instead of waiting for the next logon. Idempotent; retried automatically
# when a running Claude Code session locks the binary (patcher exit 5).
if (-not $CombosOnly -or $PickerOnly) {

# ---- 1.7. Claude Code picker: env vars + native-binary patch (self-healing) ----
# Claude Code >= 2.1.233 builds the /model picker from the gateway catalog ONLY
# through "gateway model discovery", which (a) requires the env vars below and
# (b) filters the catalog to claude/anthropic-named ids in TWO places - the
# [Bootstrap] fetch and the [gatewayDiscovery] periodic refetch. The refetch
# REPLACES the cached model list with its filtered result, so patching only the
# bootstrap site made the picker collapse again on the next refetch ("worked,
# then broke again"). patch-claude-picker.mjs byte-patches EVERY filter site
# (same-length replace, idempotent) in the VS Code extension's native binary
# AND the standalone ~/.local/bin/claude.exe CLI, so every gateway route
# (auto/*, combo/*, mimo-web/*, lmarena/*, ...) shows in the picker. Re-applied
# automatically here after every Claude Code auto-update, and every 5 minutes
# by the gateway watchdog (-PickerOnly).
$ccFile = Join-Path $HOME '.claude\settings.json'
if (Test-Path $ccFile) {
    $ccEnv = Get-Content $ccFile -Raw | ConvertFrom-Json
    if (-not $ccEnv.env) { $ccEnv | Add-Member -NotePropertyName env -NotePropertyValue ([pscustomobject]@{}) }
    $needWrite = $false
    foreach ($kv in @(@('CLAUDE_CODE_USE_GATEWAY', 'true'), @('CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY', 'true'))) {
        if (-not ($ccEnv.env.PSObject.Properties.Name -contains $kv[0])) {
            $ccEnv.env | Add-Member -NotePropertyName $kv[0] -NotePropertyValue $kv[1] -Force
            $needWrite = $true
        }
    }
    if ($needWrite) {
        $json = $ccEnv | ConvertTo-Json -Depth 12
        [System.IO.File]::WriteAllText($ccFile, $json, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host 'settings.json env: CLAUDE_CODE_USE_GATEWAY + CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY added' -ForegroundColor Green
    }
}
$patcher = $null
foreach ($cand in @(
    (Join-Path $PSScriptRoot 'patch-claude-picker.mjs'),
    (Join-Path $HOME 'omniroute-setup-kit\patch-claude-picker.mjs'),
    (Join-Path $HOME '.omniroute\patch-claude-picker.mjs')
)) { if (Test-Path $cand) { $patcher = $cand; break } }
if (-not $patcher) {
    Write-Host 'patch-claude-picker.mjs not found - picker will only show claude-named routes' -ForegroundColor Yellow
}
function Invoke-PickerPatch([string]$exePath, [string]$label) {
    if (-not $patcher) { return }
    & node $patcher $exePath 2>&1 | ForEach-Object { Write-Host $_ -ForegroundColor Cyan }
    if ($LASTEXITCODE -eq 0) { Write-Host "Claude Code picker patch ok ($label)" -ForegroundColor Green }
    elseif ($LASTEXITCODE -eq 3) {
        Write-Host "Claude Code $label updated - picker patch anchor missing; this build needs re-review" -ForegroundColor Yellow
    }
    elseif ($LASTEXITCODE -eq 5) {
        Write-Host "Claude Code $label binary LOCKED (session running) - retrying on next run" -ForegroundColor Yellow
    }
}
# VS Code extension binary — two known locations across Claude Code versions:
# 1. Old path: ~/.vscode/extensions/anthropic.claude-code-*/resources/native-binary/claude.exe
# 2. New path (>= 0.3.220): ~/AppData/Roaming/Code/agent-host/sdk-cache/claude/*/win32-x64/.../claude.exe
$ccExt = Get-ChildItem (Join-Path $HOME '.vscode\extensions') -Directory -Filter 'anthropic.claude-code-*' -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1
if ($ccExt) {
    $nativeExe = Join-Path $ccExt.FullName 'resources\native-binary\claude.exe'
    if (Test-Path $nativeExe) { Invoke-PickerPatch $nativeExe $ccExt.Name }
}
# New SDK-cache path (Claude Code >= 0.3.220)
$sdkCache = Join-Path $HOME 'AppData\Roaming\Code\agent-host\sdk-cache\claude'
if (Test-Path $sdkCache) {
    $sdkExe = Get-ChildItem $sdkCache -Recurse -Filter 'claude.exe' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -like '*claude-agent-sdk*' } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($sdkExe) { Invoke-PickerPatch $sdkExe.FullName 'Claude Code SDK (>=0.3.220)' }
}
# Standalone CLI binary (~/.local/bin/claude.exe). This was never patched
# before, so the terminal `claude` /model picker stayed filtered forever -
# patch it with the same patcher (it finds ALL filter sites in any binary).
$cliExe = Join-Path $HOME '.local\bin\claude.exe'
if (Test-Path $cliExe) { Invoke-PickerPatch $cliExe 'CLI (~/.local/bin/claude.exe)' }

# -PickerOnly (watchdog fast heal): env vars + binary patch is all we need -
# no bridge, no catalog, no combos, no cache. Exit before any of that runs.
if ($PickerOnly) {
    Write-Host 'Picker-only mode done (watchdog fast heal) - cache/combos untouched.' -ForegroundColor DarkGray
    exit 0
}

} # end -CombosOnly skip (picker patch + cache + availableModels)

# ---- 1.8. zai captcha worker: keep Chrome HEADED (a real browser is REQUIRED) ----
# The gateway's ZAI_CAPTCHA_WORKER launches a Playwright Chrome to solve z.ai's
# Aliyun traceless captcha whenever the account is challenged (HTTP 405 block
# page). We tried making it headless - but Aliyun's anti-bot detects headless
# Chrome (verifyResult F001) and refuses every solve, so the 405 challenge
# could never clear and zai-web stayed broken (173 worker failures in a day vs
# 2 in the previous 5 days). zai is the ONE component that cannot run headless;
# its captcha window appears only for a few seconds when z.ai issues a
# challenge. patch-zai-captcha-headed.mjs ensures the worker is headed
# (idempotent; re-applied after every gateway npm update). Runs in both modes.
if (-not $PickerOnly) {
$zaiPatcher = $null
foreach ($cand in @(
    (Join-Path $PSScriptRoot 'patch-zai-captcha-headed.mjs'),
    (Join-Path $HOME 'omniroute-setup-kit\patch-zai-captcha-headed.mjs'),
    (Join-Path $HOME '.omniroute\patch-zai-captcha-headed.mjs')
)) { if (Test-Path $cand) { $zaiPatcher = $cand; break } }
if ($zaiPatcher) {
    & node $zaiPatcher 2>&1 | ForEach-Object { Write-Host $_ -ForegroundColor Cyan }
    if ($LASTEXITCODE -eq 3) {
        Write-Host 'zai captcha worker updated - headed/patched anchor missing; this build needs re-review' -ForegroundColor Yellow
    }
} else {
    Write-Host 'patch-zai-captcha-headed.mjs not found - zai captcha worker left as-is' -ForegroundColor Yellow
}

} # end -PickerOnly skip (zai patch)

# ---- 2. discover routes from the live gateway ----
Write-Host "Fetching catalog from $Base/v1/models ..." -ForegroundColor Cyan
# /v1/models aggregates every provider and can take 30s+ after a gateway
# restart - a single 60s attempt kept timing out at logon, aborting the whole
# heal (ErrorActionPreference=Stop). Warm it up with a generous timeout, then
# retry the real fetch a few times before giving up.
$catalog = $null
try {
    Invoke-RestMethod -Uri "$Base/v1/models" -Headers @{ Authorization = "Bearer $Token" } -TimeoutSec 120 | Out-Null
    Write-Host 'catalog warmed (first request can be slow)' -ForegroundColor DarkGray
} catch {
    Write-Host "catalog warmup failed: $($_.Exception.Message)" -ForegroundColor Yellow
}
foreach ($attempt in 1..3) {
    try {
        $catalog = Invoke-RestMethod -Uri "$Base/v1/models" -Headers @{ Authorization = "Bearer $Token" } -TimeoutSec 60
        break
    } catch {
        Write-Host "catalog fetch attempt $attempt/3 failed: $($_.Exception.Message)" -ForegroundColor Yellow
        if ($attempt -lt 3) { Start-Sleep -Seconds 15 }
    }
}
if (-not $catalog) {
    Write-Host 'Catalog unreachable after retries - gateway down or wedged?' -ForegroundColor Red
    exit 1
}
# bare "auto" route (auto-selects best available model) PLUS the auto/* "majors"
# (auto/coding:reliable, auto/best-coding, auto/best-fast, auto/best-vision,
# auto/best-reasoning, per-family auto/glm / auto/minimax / auto/zai, chaos,
# offline, ...) from the live catalog. The majors are the gateway's flagship
# routing routes; they are mirrored into availableModels below so the VS Code
# /model picker shows the same majors as the terminal picker.
$auto   = @('auto')
$autoMajors = @($catalog.data | ForEach-Object { $_.id } | Where-Object { $_ -like 'auto/*' } | Sort-Object)
$nvidia = @($catalog.data | ForEach-Object { $_.id } | Where-Object {
    $_ -like 'nvidia/*' -and
    $_ -notin $nvidiaDead -and
    $_ -notmatch $deadPattern
} | Sort-Object)
# OpenCode Zen free tier: -free suffix, plus big-pickle (the free anonymous model)
$ocFree = @($catalog.data | ForEach-Object { $_.id } | Where-Object {
    ($_ -like 'opencode-zen/*' -or $_ -like 'oc/*') -and ($_ -like '*-free' -or $_ -like '*/big-pickle')
} | Sort-Object)
# OpenRouter free tier: :free suffix (e.g. openrouter/nvidia/nemotron-3-ultra-550b-a55b:free)
$orFree = @($catalog.data | ForEach-Object { $_.id } | Where-Object { $_ -like 'openrouter/*' -and $_ -like '*:free' } | Sort-Object)
# Xiaomi MiMo open-source V2.5/V2.5-Pro across every provider that serves the
# open weights (NOT the subscription "Claw" flagship). Kept in the picker so the
# raw routes are selectable alongside combo/mimo.
$mimo = @($catalog.data | ForEach-Object { $_.id } | Where-Object { $_ -match 'mimo' } | Sort-Object)
# MiMo WEB routes via the local mimo-web bridge (aistudio.xiaomimimo.com session
# cookie) - probed straight from the bridge, not the gateway catalog, because the
# gateway only discovers openai-compatible node models lazily. The bridge answers
# /v1/models with the live modelConfigList from /open-apis/bot/config.
$mimoWeb = @()
if ($bridgeUp) {
    try {
        $bridgeModels = Invoke-RestMethod -Uri "http://127.0.0.1:$bridgePort/v1/models" -TimeoutSec 10
        $mimoWeb = @($bridgeModels.data | ForEach-Object { "mimo-web/$($_.id)" } | Sort-Object)
        Write-Host "mimo-web routes from bridge: $($mimoWeb.Count)" -ForegroundColor DarkGray
    } catch {
        Write-Host "mimo-web bridge model probe failed: $($_.Exception.Message)" -ForegroundColor Yellow
        $mimoWeb = @()
    }
}
# Cookie/web providers (qwen-web, zai-web, lmarena, deepseek-web) - chat-capable
# routes only. These were fixed 2026-08-14/15: qwen-web (real bx-umidtoken + ls+header
# cookie, chat reuse), zai-web (SPA X-Signature + Aliyun traceless captcha worker) and
# lmarena (fresh arena session cookie + recaptcha) stream real content; deepseek-web
# (userToken localStorage) added once the logged-in session was pushed. Image/video/
# multimodal-gen ids are excluded so the picker only shows routes that answer
# /v1/chat/completions.
$webChat = @($catalog.data | ForEach-Object { $_.id } | Where-Object {
    $_ -like 'qwen-web/*' -or $_ -like 'zai-web/*' -or $_ -like 'lmarena/*' -or $_ -like 'no-think/lmarena/*' -or $_ -like 'deepseek-web/*'
} | Where-Object {
    $_ -notmatch 'flux|seedream|ideogram|krea|recraft|qwen-image|wan[0-9]|photon|hidream|gpt-image|image-preview|mimo|cosmos|mercury|detector|embed|rerank'
} | Sort-Object)
# Curated free/working models from the other keyed providers (verified live against
# /v1/chat/completions on 2026-08-19 - a mix of fast + capable free models).
# Casing matters for HuggingFace (HF router is case-sensitive on model ids).
# groq/aion (403 Cloudflare block) and ollama-cloud (502 empty response) were
# dropped 2026-08-19 after failing live probes.
$curated = @(
    'mistral/mistral-medium-2505',
    'cohere/command-a-03-2025',
    'nscale/openai/gpt-oss-20b',
    'huggingface/meta-llama/Llama-3.1-8B-Instruct'
)
# keep only curated ids that the gateway actually exposes (harmless if a provider is unkeyed)
$curated = @($curated | Where-Object { $_ -in @($catalog.data | ForEach-Object { $_.id }) })

# ---- 2.5. ensure per-family combo/* routes (combo/qwen, combo/glm, combo/deepseek,
#      combo/lmarena) via the dashboard API. The built-in auto/* majors are fixed;
#      a combo is the gateway-native way to get a per-family routing route that
#      picks the best live model from a web/cookie provider family (priority
#      order, flagship first, fallback down the list). Idempotent: existing combos
#      are left alone, missing ones are created. Requires a management token - the
#      Cookie Pusher's per-machine admin key (minted by setup.ps1) is used, with
#      the script's -Token as fallback.
$comboFamilies = [ordered]@{
    qwen     = @('qwen-web/qwen3.8-max','qwen-web/qwen3.7-max','qwen-web/qwen3.7-plus')
    glm      = @('zai-web/glm-5.2','zai-web/GLM-5.1','zai-web/GLM-5-Turbo','zai-web/GLM-5v-Turbo','zai-web/glm-4.7','zai-web/glm-4.6v','zai-web/GLM-4.1V-Thinking-FlashX','zai-web/glm-4-flash','zai-web/glm-4-air-250414','zai-web/deep-research','zai-web/zero')
    deepseek = @('deepseek-web/deepseek-v4-pro','deepseek-web/deepseek-v4-pro-think','deepseek-web/deepseek-v4-flash','deepseek-web/deepseek-v4-flash-think','deepseek-web/deepseek-chat','deepseek-web/deepseek-reasoner','deepseek-web/DeepSeek-V3.2','deepseek-web/DeepSeek-R1')
    lmarena  = @('lmarena/claude-sonnet-5','lmarena/claude-sonnet-5-high','lmarena/claude-opus-5','lmarena/claude-opus-5-high','lmarena/claude-haiku-4-5-20251001','lmarena/glm-5.1','lmarena/deepseek-v4-pro','lmarena/deepseek-v4-flash','lmarena/gpt-5.2-high','lmarena/gemini-3.1-pro')
    # lmarena thinking-speed combos, derived from the live arena chat list by
    # thinking-level suffix: -low/-medium = fast, -high/-xhigh = slow. Base ids
    # (no suffix) have no explicit speed level and stay in combo/lmarena (the
    # catch-all) - the speed combos are picked explicitly by the user.
    'lmarena-fast' = @($webChat | Where-Object { $_ -like 'lmarena/*' -and $_ -match '-(low|medium)$' } | Sort-Object)
    'lmarena-slow' = @($webChat | Where-Object { $_ -like 'lmarena/*' -and $_ -match '-(high|xhigh)$' } | Sort-Object)
    # Xiaomi MiMo open-source V2.5 / V2.5-Pro (NOT the "Claw" flagship - that one
    # is subscription-limited to ~4h usage/day). Spans many free providers
    # (opencode-zen/oc free tier, openrouter, lmarena, llm7, huggingchat/hf,
    # mcode), all of which serve the same open weights.
    mimo = @('oc/mimo-v2.5-free','opencode-zen/mimo-v2.5-free','openrouter/xiaomi/mimo-v2.5','openrouter/xiaomi/mimo-v2.5-pro','lmarena/mimo-v2.5','lmarena/mimo-v2.5-pro','llm7/XiaomiMiMo/MiMo-V2.5','llm7/XiaomiMiMo/MiMo-V2.5-Pro','huggingchat/XiaomiMiMo/MiMo-V2.5','huggingchat/XiaomiMiMo/MiMo-V2.5-Pro','hf/XiaomiMiMo/MiMo-V2.5','hf/XiaomiMiMo/MiMo-V2.5-Pro','mcode/mimo-auto')
    # MiMo WEB (aistudio.xiaomimimo.com session) - flagship-first across the live
    # bridge models, best-first (v2.5-pro, v2.5, v2-flash, ...).
    'mimo-web' = @('mimo-web/mimo-v2.5-pro','mimo-web/mimo-v2.5','mimo-web/mimo-v2-pro','mimo-web/mimo-v2-flash','mimo-web/mimo-v2-omni')
}
$adminToken = $Token
$extConfig = Join-Path $HOME 'omniroute-cookie-pusher\config.js'
if (Test-Path $extConfig) {
    $cfgJs = Get-Content $extConfig -Raw
    if ($cfgJs -match "DEFAULT_API_KEY\s*=\s*'([^']+)'") { $adminToken = $Matches[1] }
}
$catalogIds = @($catalog.data | ForEach-Object { $_.id })
$comboRoutes = @()
$combosApi = "$Base/api/combos"
try {
    $existingNames = @()
    try {
        $existingNames = @(((Invoke-RestMethod -Uri $combosApi -Headers @{ Authorization = "Bearer $adminToken" } -TimeoutSec 30).combos) | ForEach-Object { $_.name })
    } catch { $existingNames = @() }
    foreach ($name in $comboFamilies.Keys) {
        if ($name -eq 'mimo') {
            # mimo spans MANY provider prefixes, so append every mimo route the
            # live catalog serves (across oc/openrouter/lmarena/llm7/hf/mcode),
            # not just one family prefix - flagship-first then the rest.
            $modelIds = @($comboFamilies[$name] | Where-Object { $_ -in $catalogIds })
            $modelIds = @($modelIds + @($catalogIds | Where-Object { $_ -match 'mimo' -and $_ -notin $modelIds }) | Select-Object -Unique | Sort-Object)
        } elseif ($name -like 'lmarena-*') {
            # thinking-speed combos are already the complete filtered list - do
            # NOT append the family's other models (that would pull in the other
            # speed's thinking levels).
            $modelIds = @($comboFamilies[$name] | Where-Object { $_ -in $catalogIds } | Sort-Object)
        } elseif ($name -eq 'mimo-web') {
            # bridge models may not be in the gateway catalog yet, so source the
            # combo straight from the live bridge probe, flagship-first.
            $modelIds = @($mimoWeb | Sort-Object)
            if ($modelIds.Count -gt 0) {
                $ordered = @($comboFamilies[$name] | Where-Object { $_ -in $mimoWeb })
                $modelIds = @($ordered + @($mimoWeb | Where-Object { $_ -notin $ordered }) | Select-Object -Unique)
            }
        } else {
            # flagship-first order, filtered to ids the live catalog actually serves,
            # then append the family's remaining chat routes (so the route covers ALL
            # live models of that family, best-first).
            $ordered = @($comboFamilies[$name] | Where-Object { $_ -in $catalogIds })
            $familyPrefix = (($comboFamilies[$name][0] -split '/')[0]) + '/*'
            $rest = @($webChat | Where-Object { $_ -like $familyPrefix -and $_ -notin $ordered } | Sort-Object)
            $modelIds = @($ordered + $rest | Select-Object -Unique)
        }
        if ($modelIds.Count -eq 0) { continue }
        if ($name -in $existingNames) {
            Write-Host "combo/$name exists ($($modelIds.Count) live models)" -ForegroundColor DarkGray
        } else {
            $body = @{ name = $name; models = $modelIds; strategy = 'priority' } | ConvertTo-Json -Depth 4
            try {
                Invoke-RestMethod -Uri $combosApi -Method Post -Headers @{ Authorization = "Bearer $adminToken" } -ContentType 'application/json' -Body $body -TimeoutSec 30 | Out-Null
                Write-Host "combo/$name created ($($modelIds.Count) live models)" -ForegroundColor Green
            } catch {
                Write-Host "combo/$name create failed: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
        $comboRoutes += "combo/$name"
    }
} catch {
    Write-Host "combo route sync skipped (dashboard API unreachable): $($_.Exception.Message)" -ForegroundColor Yellow
}

$models = @($auto + $autoMajors + $nvidia + $ocFree + $orFree + $webChat + $mimo + $mimoWeb + $comboRoutes + $curated | Sort-Object -Unique)
if ($models.Count -eq 0) {
    Write-Host 'No routes discovered - gateway unreachable or catalog empty?' -ForegroundColor Red
    exit 1
}

# ---- 3. write the cache with a far-future fetchedAt (epoch ms) ----
if (-not $CombosOnly) {
$ccCache = Join-Path $HOME '.claude\cache'
New-Item -ItemType Directory -Force -Path $ccCache | Out-Null
$cacheFile = Join-Path $ccCache 'gateway-models.json'
if (Test-Path $cacheFile) {
    Copy-Item $cacheFile "$cacheFile.bak-filtered" -Force
}
$cache = [ordered]@{
    baseUrl   = "$Base"
    fetchedAt = [DateTimeOffset]::UtcNow.AddYears(1).ToUnixTimeMilliseconds()
    models    = @($models | ForEach-Object { [ordered]@{ id = $_ } })
}
$json = $cache | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText($cacheFile, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Cache seeded: $($auto.Count) auto + $($autoMajors.Count) auto/* majors + $($comboRoutes.Count) combo/* routes + $($nvidia.Count) nvidia/ + $($ocFree.Count) OpenCode free + $($orFree.Count) OpenRouter free + $($webChat.Count) web(qwen/zai/lmarena/deepseek) + $($mimo.Count) mimo + $($mimoWeb.Count) mimo-web + $($curated.Count) curated -> $cacheFile" -ForegroundColor Green

} # end -CombosOnly skip (cache seed)

# ---- 3.9. RESILIENCE SETTINGS: fast failover for faster responses ----
# The default gateway resilience budget is extremely conservative (90s x 5 retries
# = 300s total), which makes auto/* and combo/* routes take 27s+ when any upstream
# provider is slow or rate-limited. These settings cut the budget to 60s total
# (15s x 2 retries) so failing providers are skipped quickly.
if (-not $CombosOnly) {
    $dbPath = Join-Path $HOME '.omniroute\storage.sqlite'
    if (Test-Path $dbPath) {
        try {
            $sqlite = [System.Data.SQLite.SQLiteConnection]::new("Data Source=$dbPath;Version=3;Read Only=False")
            $sqlite.Open()
            $cmd = $sqlite.CreateCommand()
            $cmd.CommandText = "SELECT value FROM key_value WHERE namespace='settings' AND key='resilienceSettings'"
            $existing = $cmd.ExecuteScalar()
            $current = if ($existing) { $existing | ConvertFrom-Json } else { @{} }

            $needsUpdate = $false
            $target = @{
                waitForCooldown = @{ enabled=$true; maxRetries=2; maxRetryWaitSec=15; maxRetryWaitMs=15000; budgetMs=60000 }
                comboCooldownWait = @{ enabled=$true; maxWaitMs=15000; maxAttempts=2; budgetMs=60000 }
                requestQueue = @{ maxWaitMs=15000 }
                providerCooldown = @{ minRetryCooldownMs=2000; maxRetryCooldownMs=30000; enabled=$true }
                streamRecovery = @{ enabled=$true; midstreamEnabled=$true }
                quotaShareConcurrencyLimit = @{ enabled=$true }
            }
            foreach ($key in $target.Keys) {
                if (-not $current.$key -or $current.$key.maxRetries -gt 3 -or $current.$key.budgetMs -gt 120000) {
                    $needsUpdate = $true
                    break
                }
            }
            if ($needsUpdate) {
                $json = $target | ConvertTo-Json -Depth 6 -Compress
                $cmd.CommandText = "INSERT OR REPLACE INTO key_value (namespace, key, value) VALUES ('settings', 'resilienceSettings', @val)"
                $cmd.Parameters.AddWithValue('@val', $json) | Out-Null
                $cmd.ExecuteNonQuery() | Out-Null
                Write-Host 'Resilience settings optimized: 15s x 2 retries = 60s budget (was 90s x 5 = 300s)' -ForegroundColor Green
            } else {
                Write-Host 'Resilience settings already optimized' -ForegroundColor DarkGray
            }
            $sqlite.Close()
        } catch {
            Write-Host "Resilience settings skipped: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

# ---- 4. rebuild availableModels to mirror the picker (auto/* majors kept, dead NIM dropped) ----
if (-not $CombosOnly) {
$ccFile = Join-Path $HOME '.claude\settings.json'
if (Test-Path $ccFile) {
    $cc = Get-Content $ccFile -Raw | ConvertFrom-Json
    $cur = @($cc.availableModels)
    # keep: bare auto, alive nvidia, opencode free, openrouter free, curated free
    $keep = @($cur | Where-Object {
        $_ -eq 'auto' -or
        $_ -like 'auto/*' -or
        $_ -like 'combo/*' -or
        ($_ -like 'nvidia/*' -and $_ -notin $nvidiaDead -and $_ -notmatch $deadPattern) -or
        (($_ -like 'opencode-zen/*' -or $_ -like 'oc/*') -and ($_ -like '*-free' -or $_ -like '*/big-pickle')) -or
        ($_ -like 'openrouter/*' -and $_ -like '*:free') -or
        ($_ -match 'mimo') -or
        ($_ -like 'mimo-web/*') -or
        ($_ -like 'qwen-web/*' -or $_ -like 'zai-web/*' -or $_ -like 'lmarena/*' -or $_ -like 'no-think/lmarena/*' -or $_ -like 'deepseek-web/*') -or
        $_ -in $curated
    })
    $merged = @($keep + $models | Sort-Object -Unique)
    if ($merged.Count -ne $cur.Count) {
        $cc | Add-Member -NotePropertyName 'availableModels' -NotePropertyValue $merged -Force
        $json = $cc | ConvertTo-Json -Depth 12
        [System.IO.File]::WriteAllText($ccFile, $json, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "availableModels rebuilt -> $($merged.Count) routes (auto/* majors + combo/* routes mirrored, dead NIM removed)" -ForegroundColor Green
    }
}

} # end -CombosOnly skip (availableModels)

# ---- 4.25. GATEWAY CURATION: hide every non-curated route so /v1/models (and
#      therefore the Claude/Codex discovery pickers, which read it LIVE) show
#      EXACTLY the curated free-model catalog - no gazillions, and no model is
#      ever "restricted by your organization's settings" (every curated route
#      is in the entitlement list). Writes modelCompatOverrides rows into
#      ~/.omniroute/storage.sqlite (same contract as the dashboard hide eye).
#      Idempotent; SKIP_CURATE=1 disables.
if (-not $CombosOnly -and $env:SKIP_CURATE -ne '1') {
    $curateScript = $null
    foreach ($cand in @(
        (Join-Path $PSScriptRoot 'curate-gateway.mjs'),
        (Join-Path $HOME 'omniroute-setup-kit\curate-gateway.mjs'),
        (Join-Path $HOME '.omniroute\curate-gateway.mjs')
    )) { if (Test-Path $cand) { $curateScript = $cand; break } }
    if ($curateScript) {
        $dbPath = Join-Path $HOME '.omniroute\storage.sqlite'
        if (Test-Path $dbPath) {
            $tmpList = Join-Path $env:TEMP "omniroute-curated-$([guid]::NewGuid().ToString('N')).txt"
            $models | Set-Content -Path $tmpList -Encoding UTF8
            try {
                & node $curateScript $dbPath $Base $adminToken $tmpList 2>&1 | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }
            } finally {
                Remove-Item $tmpList -Force -ErrorAction SilentlyContinue
            }
        } else {
            Write-Host 'Gateway DB not found - curation skipped (start the gateway once first)' -ForegroundColor Yellow
        }
    } else {
        Write-Host 'curate-gateway.mjs not found - skipping gateway curation' -ForegroundColor Yellow
    }
}

# ---- 4.5. Codex CLI model catalog (model_catalog_json) ----
# Codex's /model picker only shows OpenAI's built-in models by default. Point it
# at a local catalog file (model_catalog_json) cloned from a bundled model so
# every gateway route (auto/*, combo/*, lmarena/*, mimo-web/*, ...) is
# selectable. The catalog is rebuilt from the SAME curated $models list the
# Claude Code picker cache uses, so both pickers stay in sync. Idempotent;
# config.toml is only touched to add the root-level model_catalog_json line +
# ensure the default model points at the gateway (user sections like
# [projects.*] trust are preserved).
if (Get-Command codex -ErrorAction SilentlyContinue) {
    $codexDir = Join-Path $HOME '.codex'
    New-Item -ItemType Directory -Force -Path (Join-Path $codexDir 'model-catalogs') | Out-Null
    $catalogFile = Join-Path $codexDir 'model-catalogs\omniroute.json'
    try {
        # Clone the first bundled model (full required field set incl. base_instructions).
        $bundled = (codex debug models --bundled 2>$null) | Out-String | ConvertFrom-Json
        $tpl = $bundled.models[0]
        if ($tpl) {
            $entries = @()
            $i = 0
            foreach ($id in $models) {
                $e = $tpl.PSObject.Copy()
                $e.slug = $id
                $e.display_name = $id
                $e.description = "OmniRoute gateway route ($id) - free pool via localhost:20128"
                $e.context_window = 200000
                $e.max_context_window = 200000
                $e.visibility = 'list'
                $e.supported_in_api = $true
                $e.priority = $i
                $e.availability_nux = $null
                $e.upgrade = $null
                $entries += $e
                $i++
            }
            $catalog = [ordered]@{ models = $entries }
            [System.IO.File]::WriteAllText($catalogFile, ($catalog | ConvertTo-Json -Depth 12), (New-Object System.Text.UTF8Encoding($false)))
            Write-Host "Codex catalog seeded: $($entries.Count) gateway routes -> $catalogFile" -ForegroundColor Green

            # config.toml: add model_catalog_json at ROOT + keep default model on the gateway.
            $codexCfg = Join-Path $codexDir 'config.toml'
            if (Test-Path $codexCfg) {
                $lines = @(Get-Content $codexCfg)
                # root section = everything before the first [table] line
                $rootEnd = $lines.Count
                for ($n = 0; $n -lt $lines.Count; $n++) { if ($lines[$n] -match '^\s*\[') { $rootEnd = $n; break } }
                $root = New-Object System.Collections.Generic.List[string]
                for ($n = 0; $n -lt $rootEnd; $n++) { $root.Add($lines[$n]) }
                $tail = @($lines | Select-Object -Skip $rootEnd)

                # default model -> gateway route (in case the user/Codex switched it away)
                $replaced = $false
                for ($n = 0; $n -lt $root.Count; $n++) {
                    if ($root[$n] -match '^\s*model\s*=' -and $root[$n] -notmatch 'model_provider' -and $root[$n] -notmatch 'model_catalog' -and $root[$n] -notmatch 'model_reasoning') {
                        $root[$n] = 'model = "auto/coding:reliable"'
                        $replaced = $true
                        break
                    }
                }
                if (-not $replaced) { $root.Insert(0, 'model = "auto/coding:reliable"') }

                if (-not ($root | Where-Object { $_ -match '^\s*model_provider\s*=' })) { $root.Add('model_provider = "omniroute"') }
                # TOML basic strings treat backslashes as escapes - use forward
                # slashes (Windows APIs accept them) so the path never breaks parsing.
                if (-not ($root | Where-Object { $_ -match 'model_catalog_json' })) { $root.Add('model_catalog_json = "' + ($catalogFile -replace '\\', '/') + '"') }

                # Match the file's existing line-ending style (Codex writes LF,
                # setup.ps1 writes CRLF) so idempotent re-runs never rewrite.
                $curRaw = Get-Content $codexCfg -Raw
                $nl = if ($curRaw -match "`r`n") { "`r`n" } else { "`n" }
                $newToml = ($root -join $nl) + $nl
                if ($tail.Count) { $newToml += (($tail -join $nl) + $nl) }
                if ($newToml -ne $curRaw) {
                    if (Test-Path "$codexCfg.bak-kit") { Remove-Item "$codexCfg.bak-kit" -Force }
                    Copy-Item $codexCfg "$codexCfg.bak-kit" -Force
                    [System.IO.File]::WriteAllText($codexCfg, $newToml, (New-Object System.Text.UTF8Encoding($false)))
                    Write-Host "~/.codex/config.toml updated (model_catalog_json + default model auto/coding:reliable; backup at config.toml.bak-kit)" -ForegroundColor Green
                }
            }
        }
    } catch {
        Write-Host "Codex catalog skipped: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Host 'Done. Now FULLY quit VS Code and Claude Desktop (all windows, and' -ForegroundColor Yellow
Write-Host 'taskbar/processes) and reopen - the picker will show auto + auto/* majors + combo/* + NIM +' -ForegroundColor Yellow
Write-Host 'OpenCode free + OpenRouter free + qwen-web/zai-web/lmarena/deepseek-web (chat) routes.' -ForegroundColor Yellow
