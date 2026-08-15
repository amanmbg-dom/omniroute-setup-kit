<#
.SYNOPSIS
  Seed Claude Code's gateway-model cache so the /model picker shows the single
  "auto" route, the ALIVE NVIDIA NIM (nvidia/*) direct models, and the free
  OpenCode Zen routes (opencode-zen/*-free, oc/*-free, big-pickle) - and keep it
  that way across re-runs.
.DESCRIPTION
  Claude Code caches the gateway catalog in ~/.claude/cache/gateway-models.json,
  but when it refetches the catalog itself it filters it to claude-named models.
  This script writes the cache directly with the routes below and pins fetchedAt
  ~1 year out, so the app treats the cache as fresh and never refetches-and-filters.

  Dead NIM models (404 upstream on build.nvidia.com) and non-chat models
  (embed/rerank/asr/tts/image-gen/parse) are excluded, so the picker only shows
  routes that actually answer /v1/chat/completions.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File fix-model-cache.ps1
  powershell -ExecutionPolicy Bypass -File fix-model-cache.ps1 -Base http://localhost:20128
#>
param(
    [string]$Base = 'http://localhost:20128',
    [string]$Token = 'omniroute'
)
$ErrorActionPreference = 'Stop'

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

# ---- 2. discover routes from the live gateway ----
Write-Host "Fetching catalog from $Base/v1/models ..." -ForegroundColor Cyan
$catalog = Invoke-RestMethod -Uri "$Base/v1/models" -Headers @{ Authorization = "Bearer $Token" } -TimeoutSec 60
# single bare "auto" route (auto-selects best available model) - NOT the auto/* aliases
$auto   = @('auto')
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
# Cookie/web providers (qwen-web, zai-web, lmarena) - chat-capable routes only.
# These were fixed 2026-08-14: qwen-web (real bx-umidtoken + ls+header cookie, chat
# reuse) and zai-web (SPA X-Signature + Aliyun traceless captcha worker) stream real
# content; lmarena no longer crashes the stream watcher (needs a logged-in re-grab
# of the arena session cookie to actually answer). Image/video/multimodal-gen ids are
# excluded so the picker only shows routes that answer /v1/chat/completions.
$webChat = @($catalog.data | ForEach-Object { $_.id } | Where-Object {
    $_ -like 'qwen-web/*' -or $_ -like 'zai-web/*' -or $_ -like 'lmarena/*' -or $_ -like 'no-think/lmarena/*'
} | Where-Object {
    $_ -notmatch 'flux|seedream|ideogram|krea|recraft|qwen-image|wan[0-9]|photon|hidream|gpt-image|image-preview|mimo|cosmos|mercury|detector|embed|rerank'
} | Sort-Object)
# Curated free/working models from the other keyed providers (verified live against
# /v1/messages on 2026-08-14 with real keys - a mix of fast + capable free models).
# Casing matters for HuggingFace (HF router is case-sensitive on model ids).
$curated = @(
    'groq/llama-3.1-8b-instant',
    'mistral/mistral-medium-2505',
    'aion/aion-labs/aion-2.0',
    'cohere/command-a-03-2025',
    'nscale/openai/gpt-oss-20b',
    'ollama-cloud/gpt-oss:20b',
    'huggingface/meta-llama/Llama-3.1-8B-Instruct'
)
# keep only curated ids that the gateway actually exposes (harmless if a provider is unkeyed)
$curated = @($curated | Where-Object { $_ -in @($catalog.data | ForEach-Object { $_.id }) })
$models = @($auto + $nvidia + $ocFree + $orFree + $webChat + $curated | Sort-Object -Unique)
if ($models.Count -eq 0) {
    Write-Host 'No routes discovered - gateway unreachable or catalog empty?' -ForegroundColor Red
    exit 1
}

# ---- 3. write the cache with a far-future fetchedAt (epoch ms) ----
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
Write-Host "Cache seeded: $($auto.Count) auto + $($nvidia.Count) nvidia/ + $($ocFree.Count) OpenCode free + $($orFree.Count) OpenRouter free + $($webChat.Count) web(qwen/zai/lmarena) + $($curated.Count) curated -> $cacheFile" -ForegroundColor Green

# ---- 4. rebuild availableModels to match (drops old auto/* aliases + dead NIM) ----
$ccFile = Join-Path $HOME '.claude\settings.json'
if (Test-Path $ccFile) {
    $cc = Get-Content $ccFile -Raw | ConvertFrom-Json
    $cur = @($cc.availableModels)
    # keep: bare auto, alive nvidia, opencode free, openrouter free, curated free
    $keep = @($cur | Where-Object {
        $_ -eq 'auto' -or
        ($_ -like 'nvidia/*' -and $_ -notin $nvidiaDead -and $_ -notmatch $deadPattern) -or
        (($_ -like 'opencode-zen/*' -or $_ -like 'oc/*') -and ($_ -like '*-free' -or $_ -like '*/big-pickle')) -or
        ($_ -like 'openrouter/*' -and $_ -like '*:free') -or
        ($_ -like 'qwen-web/*' -or $_ -like 'zai-web/*' -or $_ -like 'lmarena/*' -or $_ -like 'no-think/lmarena/*') -or
        $_ -in $curated
    })
    $merged = @($keep + $models | Sort-Object -Unique)
    if ($merged.Count -ne $cur.Count) {
        $cc | Add-Member -NotePropertyName 'availableModels' -NotePropertyValue $merged -Force
        $json = $cc | ConvertTo-Json -Depth 12
        [System.IO.File]::WriteAllText($ccFile, $json, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "availableModels rebuilt -> $($merged.Count) routes (old auto/* aliases and dead NIM removed)" -ForegroundColor Green
    }
}

Write-Host ''
Write-Host 'Done. Now FULLY quit VS Code and Claude Desktop (all windows, and' -ForegroundColor Yellow
Write-Host 'taskbar/processes) and reopen - the picker will show auto + NIM + OpenCode free +' -ForegroundColor Yellow
Write-Host 'OpenRouter free + qwen-web/zai-web/lmarena (chat) routes.' -ForegroundColor Yellow
