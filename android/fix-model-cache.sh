#!/data/data/com.termux/files/usr/bin/env bash
# =============================================================================
#  fix-model-cache.sh - Android (Termux) port of fix-model-cache.ps1
#
#  Makes the OmniRoute gateway present ONE curated free-model catalog on the
#  phone, exactly like the Windows kit does on the laptop:
#    * GATEWAY CURATION  -> hides every non-curated route in the gateway DB, so
#      /v1/models returns ONLY the curated list. That is what fixes the phone:
#      Claude's discovery (limit 1000) can no longer cut off combo/*, the
#      "restricted by your organization's settings" gate stops rejecting
#      `claude -m combo/qwen` (every curated route is in the list), and the
#      picker shows exactly the good free models - no gazillions.
#    * Claude Code       -> ~/.claude/cache/gateway-models.json (curated seed)
#                           + env FORCED in ~/.claude/settings.json
#                           + availableModels = curated
#                           + native-binary patch (filter flips so the /model
#                             picker keeps EVERY route + limit:1000 -> 9999 so
#                             discovery can't truncate the catalog again)
#    * Codex CLI         -> ~/.codex/model-catalogs/omniroute.json (curated)
#                           + config.toml wiring
#    * combo/* routes    -> created on the gateway via the dashboard API
#                           (combo/qwen, combo/glm, combo/deepseek, combo/lmarena,
#                           combo/lmarena-fast, combo/lmarena-slow, combo/mimo,
#                           combo/mimo-web) - auto-fallback per family. The
#                           admin token is read from the Cookie Pusher extension
#                           config (minted fresh if missing) so these are clean
#                           OK's, not 403's.
#
#  Idempotent and safe to run any time. Auto-runs from start-omniroute.sh
#  after the gateway is up, so pickers self-heal on every start.
#
#  Options:
#    NO_INSTALL=1   skip auto-installing the codex/claude CLIs if missing.
#    GW=http://...  override the gateway base URL (default local 20128).
#    SKIP_CURATE=1  do NOT hide the non-curated routes (report only).
# =============================================================================
set -uo pipefail

GW="${GW:-http://127.0.0.1:20128}"
TOKEN="${TOKEN:-}"

say() { echo "[fix-model-cache] $*"; }

# ---- 0. wait for the gateway (it cold-starts slowly on Android) ----
for i in $(seq 1 40); do
  if curl -sf --max-time 5 "$GW/v1/models" >/dev/null 2>&1; then break; fi
  [ "$i" = "40" ] && { echo "FATAL: gateway not answering at $GW - start the stack first (bash ~/omniroute-android/start-omniroute.sh)"; exit 1; }
  sleep 2
done
say "gateway is up"

# ---- 0.5. install the CLIs if missing (skip with NO_INSTALL=1) ----
if [ "${NO_INSTALL:-0}" != "1" ]; then
  # Claude Code on Termux: npm 'latest' (>= 2.1.113) ships a glibc native binary
  # Android's kernel refuses to exec (anthropics/claude-code#50270). The
  # claude-code-termux launcher downloads Anthropic's official linux-arm64 build
  # and ELF-patches it to Termux's glibc loader - the only way to run current
  # Claude Code on the phone. Fallback: pin the last JS-based build (2.1.112),
  # which always runs but lacks the gateway-model picker.
  if ! command -v claude >/dev/null 2>&1; then
    say "installing Claude Code (Termux launcher; npm latest is broken on Android)..."
    if curl -fsSL https://raw.githubusercontent.com/gtbuchanan/claude-code-termux/main/install.sh | bash >/dev/null 2>&1 && command -v claude >/dev/null 2>&1; then
      say "claude installed (claude-code-termux launcher)"
    else
      say "claude-code-termux failed - falling back to pinned 2.1.112 (JS build, works everywhere)"
      npm install -g --allow-scripts=@anthropic-ai/claude-code @anthropic-ai/claude-code@2.1.112 >/dev/null 2>&1 \
        && say "claude 2.1.112 installed" \
        || echo "  (claude install failed - run: npm i -g --allow-scripts=@anthropic-ai/claude-code @anthropic-ai/claude-code@2.1.112)"
    fi
  fi
  # Codex on Termux is broken upstream (openai/codex#17787 - npm won't install
  # the linux-arm64 optional dep on android, and the binary is glibc). Skip it
  # on the phone; use codex from a PC pointed at the gateway instead.
  if ! command -v codex >/dev/null 2>&1; then
    echo "  (codex skipped on Termux - broken upstream openai/codex#17787; use it from a PC)"
  fi
fi

# ---- 1. do the real work in node (Node 24 has fetch + node:sqlite; no jq needed) ----
node - "$GW" "$TOKEN" <<'EOF'
const [gw, tokArg] = process.argv.slice(2);
const os = require('os'), fs = require('fs'), path = require('path');
const { execSync } = require('child_process');
const home = os.homedir();
const log = (...a) => console.log('   ', ...a);
const ok  = (...a) => console.log('    ok:', ...a);

function sh(cmd) { try { return execSync(cmd, { encoding: 'utf8' }).trim(); } catch { return ''; } }

(async () => {
  // ---- catalog ----
  let cat, ids;
  try {
    cat = await (await fetch(`${gw}/v1/models`, { signal: AbortSignal.timeout(25000) })).json();
    ids = [...new Set((cat.data || []).map(m => m.id))];
  } catch (e) {
    console.log('FATAL: could not fetch', gw + '/v1/models', '->', e.message);
    process.exit(1);
  }
  if (!ids.length) { console.log('FATAL: gateway catalog is empty'); process.exit(1); }
  log('gateway catalog:', ids.length, 'routes');

  // ---- token: CLI arg -> Cookie Pusher extension config (~ + /sdcard) -> mint ----
  let token = tokArg || '';
  const readKey = (p) => { try { const m = fs.readFileSync(p, 'utf8').match(/DEFAULT_API_KEY\s*=\s*'([^']+)'/); return m && m[1] ? m[1] : null; } catch { return null; } };
  const extCandidates = [path.join(home, 'omniroute-cookie-pusher', 'config.js'), '/sdcard/omniroute-cookie-pusher/config.js'];
  for (const p of extCandidates) { const k = readKey(p); if (k && k !== 'omniroute') { token = k; break; } }
  if (!token) {
    // mint a fresh admin token via the gateway's own CLI, stash it in the extension configs
    const minted = sh('omniroute tokens create --name "Cookie Pusher" --scope admin 2>/dev/null').trim();
    if (minted && !/error|usage/i.test(minted)) {
      token = minted.split(/\s+/).pop();
      for (const p of extCandidates) {
        try {
          const c = fs.readFileSync(p, 'utf8').replace(/DEFAULT_API_KEY\s*=\s*'[^']*'/, `DEFAULT_API_KEY = '${token}'`);
          fs.writeFileSync(p, c);
        } catch {}
      }
      ok('admin token minted + written to the Cookie Pusher config');
    } else token = 'omniroute';
  }

  // ---- mimo-web bridge probe (20135) ----
  let mimoWeb = [];
  try {
    const br = await (await fetch('http://127.0.0.1:20135/v1/models', { signal: AbortSignal.timeout(8000) })).json();
    mimoWeb = [...new Set((br.data || []).map(m => 'mimo-web/' + m.id))].sort();
  } catch {}
  if (mimoWeb.length) log('mimo-web bridge routes:', mimoWeb.length);

  // ---- deepseek-web bridge probe (20136, auto-continue) ----
  let deepseekWeb = [];
  try {
    const br = await (await fetch('http://127.0.0.1:20136/v1/models', { signal: AbortSignal.timeout(8000) })).json();
    deepseekWeb = [...new Set((br.data || []).map(m => 'deepseek-web/' + m.id))].sort();
  } catch {}
  if (deepseekWeb.length) log('deepseek-web bridge routes:', deepseekWeb.length);

  // ---- combo/* routes via the dashboard API (best-effort, real admin token) ----
  const webChat = ids.filter(i => /^(qwen-web|zai-web|lmarena|no-think\/lmarena|deepseek-web)\//.test(i))
    .filter(i => !/(flux|seedream|ideogram|krea|recraft|qwen-image|wan[0-9]|photon|hidream|gpt-image|image-preview|mimo|cosmos|mercury|detector|embed|rerank)/.test(i));
  const byPrefix = (list, prefix) => [...new Set([...list.filter(i => ids.includes(i)),
    ...webChat.filter(i => i.startsWith(prefix) && !list.includes(i)).sort()])];
  const families = {
    qwen:       byPrefix(['qwen-web/qwen3.8-max','qwen-web/qwen3.7-max','qwen-web/qwen3.7-plus'], 'qwen-web/'),
    glm:        byPrefix(['zai-web/glm-5.2','zai-web/GLM-5.1','zai-web/GLM-5-Turbo','zai-web/GLM-5v-Turbo','zai-web/glm-4.7','zai-web/glm-4.6v','zai-web/GLM-4.1V-Thinking-FlashX','zai-web/glm-4-flash','zai-web/glm-4-air-250414','zai-web/deep-research','zai-web/zero'], 'zai-web/'),
    deepseek:   byPrefix(['deepseek-web/deepseek-v4-pro','deepseek-web/deepseek-v4-pro-think','deepseek-web/deepseek-v4-flash','deepseek-web/deepseek-v4-flash-think','deepseek-web/deepseek-chat','deepseek-web/deepseek-reasoner','deepseek-web/DeepSeek-V3.2','deepseek-web/DeepSeek-R1'], 'deepseek-web/'),
    lmarena:    byPrefix(['lmarena/claude-sonnet-5','lmarena/claude-sonnet-5-high','lmarena/claude-opus-5','lmarena/claude-opus-5-high','lmarena/claude-haiku-4-5-20251001','lmarena/glm-5.1','lmarena/deepseek-v4-pro','lmarena/deepseek-v4-flash','lmarena/gpt-5.2-high','lmarena/gemini-3.1-pro'], 'lmarena/'),
  };
  const lmFast = webChat.filter(i => i.startsWith('lmarena/') && /-(low|medium)$/.test(i)).sort();
  const lmSlow = webChat.filter(i => i.startsWith('lmarena/') && /-(high|xhigh)$/.test(i)).sort();
  if (lmFast.length) families['lmarena-fast'] = lmFast;
  if (lmSlow.length) families['lmarena-slow'] = lmSlow;
  if (mimoWeb.length) {
    const flagships = ['mimo-web/mimo-v2.5-pro','mimo-web/mimo-v2.5','mimo-web/mimo-v2-pro','mimo-web/mimo-v2-flash','mimo-web/mimo-v2-omni'];
    families['mimo-web'] = [...new Set([...flagships.filter(i => mimoWeb.includes(i)),
      ...mimoWeb.filter(i => !flagships.includes(i))])];
  }
  const mimoPool = ids.filter(i => /mimo/i.test(i)).sort();
  if (mimoPool.length) {
    const flagships = ['oc/mimo-v2.5-free','opencode-zen/mimo-v2.5-free','openrouter/xiaomi/mimo-v2.5','openrouter/xiaomi/mimo-v2.5-pro','lmarena/mimo-v2.5','lmarena/mimo-v2.5-pro','llm7/XiaomiMiMo/MiMo-V2.5','llm7/XiaomiMiMo/MiMo-V2.5-Pro','huggingchat/XiaomiMiMo/MiMo-V2.5','huggingchat/XiaomiMiMo/MiMo-V2.5-Pro','hf/XiaomiMiMo/MiMo-V2.5','hf/XiaomiMiMo/MiMo-V2.5-Pro','mcode/mimo-auto'];
    families.mimo = [...new Set([...flagships.filter(i => mimoPool.includes(i)),
      ...mimoPool.filter(i => !flagships.includes(i))])];
  }

  let existing = [];
  try {
    const r = await fetch(`${gw}/api/combos`, { headers: { Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(15000) });
    if (r.ok) existing = (await r.json()).combos.map(c => c.name);
  } catch {}
  let created = 0;
  for (const [name, models] of Object.entries(families)) {
    if (!models.length) continue;
    if (existing.includes(name)) continue;
    try {
      const r = await fetch(`${gw}/api/combos`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, models, strategy: 'priority' }),
        signal: AbortSignal.timeout(15000),
      });
      if (r.ok) { created++; ok(`combo/${name} created (${models.length} models)`); }
      else log(`combo/${name}: HTTP ${r.status} (need admin token - cookie pusher key)`);
    } catch (e) { log(`combo/${name} skipped: ${e.message}`); }
  }
  if (!created) log('combos already present (or API skipped)');

  // re-fetch so combo/* ids are in the catalog
  try {
    cat = await (await fetch(`${gw}/v1/models`, { signal: AbortSignal.timeout(25000) })).json();
    ids = [...new Set((cat.data || []).map(m => m.id))];
  } catch {}

  // ---- CURATED list (mirror of the Windows kit's fix-model-cache.ps1) ----
  const autoMajors = ids.filter(i => i.startsWith('auto/')).sort();
  // NIM models known to be dead or non-chat (same list as the Windows kit).
  const nvidiaDead = [
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
  ];
  const deadPattern = 'embed|rerank|asr|tts|whisper|fastpitch|tacotron|nvclip|flux|parse|detector|reward|neva|vila|kosmos|deplot|fuyu';
  const nvidia = ids.filter(i => i.startsWith('nvidia/') && !nvidiaDead.includes(i) && !new RegExp(deadPattern).test(i)).sort();
  const ocFree = ids.filter(i => (i.startsWith('opencode-zen/') || i.startsWith('oc/')) && (i.endsWith('-free') || i.includes('/big-pickle'))).sort();
  const orFree = ids.filter(i => i.startsWith('openrouter/') && i.includes(':free')).sort();
  const mimo = ids.filter(i => /mimo/i.test(i)).sort();
  const curatedFree = ['groq/llama-3.1-8b-instant','mistral/mistral-medium-2505','aion/aion-labs/aion-2.0',
    'cohere/command-a-03-2025','nscale/openai/gpt-oss-20b','ollama-cloud/gpt-oss:20b',
    'huggingface/meta-llama/Llama-3.1-8B-Instruct'].filter(i => ids.includes(i));
  const comboRoutes = Object.keys(families).map(n => 'combo/' + n);
  const curated = [...new Set(['auto', ...autoMajors, ...nvidia, ...ocFree, ...orFree, ...webChat, ...mimo, ...mimoWeb, ...deepseekWeb, ...comboRoutes, ...curatedFree])].sort();
  log('curated catalog:', curated.length, 'routes (auto majors + combo/* + web-cookie chat + free tiers)');

  // ---- GATEWAY CURATION: hide every non-curated route so /v1/models (and all
  //      pickers) show exactly the curated list. Same contract as the
  //      dashboard's hide eye: modelCompatOverrides rows, isHidden flag.
  //      SKIP_CURATE=1 -> report only. ----
  const dbPath = path.join(home, '.omniroute', 'storage.sqlite');
  if (process.env.SKIP_CURATE === '1') {
    log('SKIP_CURATE=1 - not hiding non-curated routes (picker may show more than the curated list)');
  } else if (!fs.existsSync(dbPath)) {
    log('gateway DB not found at ' + dbPath + ' - curation skipped');
  } else {
    try {
      const { DatabaseSync } = require('node:sqlite');
      const curatedSet = new Set(curated);
      const NS = 'modelCompatOverrides';
      const CUSTOM_NS = 'customModels';
      const byProvider = new Map();
      for (const id of ids) {
        const p = id.includes('/') ? id.split('/')[0] : id;
        if (!byProvider.has(p)) byProvider.set(p, []);
        byProvider.get(p).push(id);
      }
      const db = new DatabaseSync(dbPath, { timeout: 30000 });
      const getList = (ns, key) => {
        try {
          const row = db.prepare('SELECT value FROM key_value WHERE namespace = ? AND key = ?').get(ns, key);
          if (!row || !row.value) return [];
          const j = JSON.parse(row.value);
          return Array.isArray(j) ? j : [];
        } catch { return []; }
      };
      let hidden = 0, shown = 0, touched = 0;
      const writes = [];
      for (const [provider, providerIds] of byProvider) {
        const existing = getList(NS, provider);
        const byId = new Map(existing.map(e => [e && e.id, e]));
        const out = [];
        let pHidden = 0;
        for (const id of providerIds) {
          const want = curatedSet.has(id);
          const cur = byId.get(id);
          if (want) {
            if (cur && cur.isHidden) out.push({ ...cur, isHidden: false });
            shown++;
          } else {
            if (!cur) out.push({ id, isHidden: true });
            else if (!cur.isHidden) out.push({ ...cur, isHidden: true });
            else out.push(cur);
            pHidden++; hidden++;
          }
        }
        for (const e of existing) if (e && e.id && !byId.has(e.id)) out.push(e);
        if (out.length === 0) continue;
        const same = out.length === existing.length && out.every((e, i) => JSON.stringify(e) === JSON.stringify(existing[i]));
        if (same) continue;
        writes.push([provider, out]);
        if (pHidden > 0) touched++;
      }
      // un-hide curated models hidden via customModels rows
      const customProviders = new Set([...curatedSet].filter(i => i.includes('/')).map(i => i.split('/')[0]));
      for (const provider of customProviders) {
        const existing = getList(CUSTOM_NS, provider);
        if (!existing.length) continue;
        let dirty = false;
        const out = existing.map(e => {
          if (e && e.id && curatedSet.has(e.id) && e.isHidden) { dirty = true; return { ...e, isHidden: false }; }
          return e;
        });
        if (dirty) writes.push([provider, out]);
      }
      if (writes.length) {
        const write = db.prepare('INSERT OR REPLACE INTO key_value (namespace, key, value) VALUES (?, ?, ?)');
        db.exec('BEGIN');
        try {
          for (const [p, list] of writes) write.run(NS, p, JSON.stringify(list));
          db.exec('COMMIT');
        } catch (e2) { db.exec('ROLLBACK'); throw e2; }
        ok('gateway curated: keeping ' + shown + ' routes, hiding ' + hidden + ' (' + touched + ' providers written)');
      } else {
        ok('gateway already curated: ' + shown + ' routes visible');
      }
      db.close();
    } catch (e) {
      log('gateway curation skipped: ' + e.message);
    }
  }

  // ---- Claude Code: cache seed (curated only) ----
  const ccCache = path.join(home, '.claude', 'cache');
  fs.mkdirSync(ccCache, { recursive: true });
  const cacheFile = path.join(ccCache, 'gateway-models.json');
  const cache = { baseUrl: gw, fetchedAt: Date.now() + 31536000000, models: curated.map(id => ({ id })) };
  fs.writeFileSync(cacheFile, JSON.stringify(cache));
  ok(`claude cache seeded -> ${cacheFile} (${curated.length} curated models)`);

  // ---- Claude Code: settings.json env (FORCED - stale values cannot survive)
  //      + availableModels = curated (no BOM) ----
  const ccFile = path.join(home, '.claude', 'settings.json');
  let cc = {};
  try { cc = JSON.parse(fs.readFileSync(ccFile, 'utf8')); } catch { cc = {}; }
  cc.env = cc.env || {};
  Object.assign(cc.env, {
    ANTHROPIC_BASE_URL: gw,
    ANTHROPIC_AUTH_TOKEN: token,
    ANTHROPIC_MODEL: 'auto/coding:reliable',
    ANTHROPIC_SMALL_FAST_MODEL: 'auto/best-fast',
    CLAUDE_CODE_USE_GATEWAY: 'true',
    CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY: 'true',
    CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT: '1',
    // Never let claude self-update: the Termux build is ELF-patched (a stock
    // glibc update breaks exec), and 2.1.113+ can't run on Android at all.
    DISABLE_AUTOUPDATER: '1',
    DISABLE_UPDATES: '1',
  });
  cc.availableModels = [...new Set(curated)].sort();
  fs.writeFileSync(ccFile, JSON.stringify(cc, null, 2) + '\n');
  ok(`claude settings.json: env forced + ${cc.availableModels.length} curated availableModels`);

  // ---- Claude Code: native-binary picker patch (same-length byte replace) ----
  // 1) flip the /(claude|anthropic)/ filter so EVERY route shows in /model
  // 2) lift limit:1000 -> limit:9999 so discovery can't truncate the catalog.
  // On Termux the real binary is NOT `command -v claude` - that's the
  // claude-code-termux launcher; the ELF-patched claude lives at
  // $PREFIX/opt/claude-code-termux/ (native installer puts it under
  // ~/.local/share/claude/versions/). Try all of them.
  const prefix = process.env.PREFIX || '/data/data/com.termux/files/usr';
  const candidates = [];
  const optDir = path.join(prefix, 'opt', 'claude-code-termux');
  try {
    if (fs.existsSync(optDir)) {
      for (const e of fs.readdirSync(optDir)) {
        if (e === 'current' || /^claude-/.test(e)) {
          const p = path.join(optDir, e);
          try { candidates.push(fs.realpathSync(p)); } catch { candidates.push(p); }
        }
      }
    }
  } catch {}
  try {
    const verDir = path.join(home, '.local', 'share', 'claude', 'versions');
    if (fs.existsSync(verDir)) {
      for (const v of fs.readdirSync(verDir)) candidates.push(path.join(verDir, v, 'claude'));
    }
  } catch {}
  const ccBin = sh('command -v claude');
  if (ccBin) {
    try { candidates.push(fs.realpathSync(ccBin)); } catch { candidates.push(ccBin); }
  }
  let ccWired = false;
  for (const cand of [...new Set(candidates)]) {
    if (!cand || !fs.existsSync(cand)) continue;
    ccWired = true;
    try {
      const buf = fs.readFileSync(cand);
      const oldS = Buffer.from('(claude|anthropic)');
      const newS = Buffer.from('(.{0,0}|anthropic)');
      let at = buf.indexOf(oldS);
      const oldL = Buffer.from('limit:1000');
      const newL = Buffer.from('limit:9999');
      let lat = buf.indexOf(oldL);
      if (at < 0 && lat < 0) {
        if (buf.indexOf('(.{0,0}|anthropic)') >= 0 && buf.indexOf('limit:9999') >= 0) ok('claude picker already patched: ' + cand);
        else log('claude binary: no patch anchors in ' + cand + ' (JS build / launcher - nothing to patch)');
        continue;
      }
      if (!fs.existsSync(cand + '.bak-filtered')) fs.copyFileSync(cand, cand + '.bak-filtered');
      let count = 0;
      while (at >= 0) { newS.copy(buf, at); count++; at = buf.indexOf(oldS, at + oldS.length); }
      let lcount = 0;
      while (lat >= 0) { newL.copy(buf, lat); lcount++; lat = buf.indexOf(oldL, lat + oldL.length); }
      fs.writeFileSync(cand, buf);
      ok(`claude picker patch applied (${count} filter + ${lcount} limit) - every curated route in /model: ${cand}`);
    } catch (e) { log('claude binary patch skipped (' + cand + '):', e.message); }
  }
  if (!ccWired) log('claude CLI not installed - skipping claude wiring');

  // ---- Codex: catalog (curated) + config.toml ----
  if (sh('command -v codex')) {
    const codexDir = path.join(home, '.codex');
    fs.mkdirSync(path.join(codexDir, 'model-catalogs'), { recursive: true });
    const catFile = path.join(codexDir, 'model-catalogs', 'omniroute.json');
    const entries = curated.map((id, i) => ({
      slug: id, display_name: id,
      description: `OmniRoute route (${id}) via ${gw}`,
      context_window: 200000, max_context_window: 200000,
      visibility: 'list', supported_in_api: true,
      priority: i, availability_nux: null, upgrade: null,
    }));
    fs.writeFileSync(catFile, JSON.stringify({ models: entries }));
    ok(`codex catalog -> ${catFile} (${entries.length} curated routes)`);

    const cfg = path.join(codexDir, 'config.toml');
    let raw = '';
    try { raw = fs.readFileSync(cfg, 'utf8'); } catch {}
    const out = [];
    let skip = false;
    for (const l of raw.split('\n')) {
      if (/^\s*\[/.test(l)) skip = /^\[model_providers\.omniroute\]/.test(l.trim());
      if (skip) continue;
      if (/^\s*model_catalog_json\s*=/.test(l)) continue;
      out.push(l);
    }
    let body = out.join('\n').replace(/\n{3,}/g, '\n\n').trim();
    const rootAdd = [];
    if (!/^\s*model\s*=/.test(body)) rootAdd.push('model = "auto/coding:reliable"');
    if (!/^\s*model_provider\s*=/.test(body)) rootAdd.push('model_provider = "omniroute"');
    rootAdd.push(`model_catalog_json = "${catFile.replace(/\\/g, '/')}"`);
    if (rootAdd.length) body = (body ? body + '\n\n' : '') + rootAdd.join('\n');
    const block = `\n[model_providers.omniroute]\nname = "OmniRoute free pool (localhost:20128)"\nbase_url = "${gw}/v1"\nexperimental_bearer_token = "${token}"\n`;
    fs.writeFileSync(cfg, body + '\n' + block);
    ok('codex config.toml wired (omniroute provider + curated catalog)');
  } else log('codex CLI not installed - skipping codex wiring');

  console.log('\nDone. The gateway now serves ONLY the curated free-model catalog:');
  console.log('  ' + curated.length + ' routes (auto/* majors, combo/*, qwen/zai/deepseek/lmarena/mimo-web, free tiers).');
  console.log('  - Claude Code: run `claude`, then /model (or /model <route>)');
  console.log('  - Codex:       run `codex`, then /model');
})();
EOF
