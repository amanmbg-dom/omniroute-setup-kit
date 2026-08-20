#!/data/data/com.termux/files/usr/bin/env bash
# =============================================================================
#  fix-model-cache.sh - Android (Termux) port of fix-model-cache.ps1
#
#  Makes EVERY OmniRoute gateway route visible in the coding-agent pickers on
#  the phone, exactly like the Windows kit does:
#    * Codex CLI    -> ~/.codex/model-catalogs/omniroute.json (full catalog)
#                      + config.toml wiring (model_provider omniroute)
#    * Claude Code  -> ~/.claude/cache/gateway-models.json (cache seed)
#                      + availableModels merged into ~/.claude/settings.json
#                      + the native-binary picker patch (byte-level, so the
#                        /model picker keeps EVERY route instead of filtering
#                        to claude/anthropic names)
#    * combo/* routes -> created on the gateway via the dashboard API
#                        (combo/qwen, combo/glm, combo/deepseek, combo/lmarena,
#                        combo/lmarena-fast, combo/lmarena-slow, combo/mimo,
#                        combo/mimo-web) - auto-fallback per family.
#
#  Idempotent and safe to run any time. Auto-runs from start-omniroute.sh
#  after the gateway is up, so pickers self-heal on every start.
#
#  Options:
#    NO_INSTALL=1   skip auto-installing the codex/claude CLIs if missing.
#    GW=http://...  override the gateway base URL (default local 20128).
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
  if ! command -v claude >/dev/null 2>&1; then
    say "installing Claude Code CLI (npm)..."
    npm install -g @anthropic-ai/claude-code >/dev/null 2>&1 && say "claude installed" || echo "  (claude install failed - run: npm i -g @anthropic-ai/claude-code)"
  fi
  if ! command -v codex >/dev/null 2>&1; then
    say "installing Codex CLI (npm)..."
    npm install -g @openai/codex >/dev/null 2>&1 && say "codex installed" || echo "  (codex install failed - run: npm i -g @openai/codex)"
  fi
fi

# ---- 1. do the real work in node (Node 24 has fetch; no jq needed) ----
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

  // ---- token: CLI arg -> extension config -> magic localhost token ----
  let token = tokArg || 'omniroute';
  const extCfg = path.join(home, 'omniroute-cookie-pusher', 'config.js');
  try {
    const m = fs.readFileSync(extCfg, 'utf8').match(/DEFAULT_API_KEY\s*=\s*'([^']+)'/);
    if (m && m[1]) token = m[1];
  } catch {}

  // ---- combo/* routes via the dashboard API (best-effort) ----
  const webChat = ids.filter(i => /^(qwen-web|zai-web|lmarena|no-think\/lmarena|deepseek-web)\//.test(i));
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
  const mimoWebIds = ids.filter(i => i.startsWith('mimo-web/')).sort();
  if (mimoWebIds.length) {
    const flagships = ['mimo-web/mimo-v2.5-pro','mimo-web/mimo-v2.5','mimo-web/mimo-v2-pro','mimo-web/mimo-v2-flash','mimo-web/mimo-v2-omni'];
    families['mimo-web'] = [...new Set([...flagships.filter(i => mimoWebIds.includes(i)),
      ...mimoWebIds.filter(i => !flagships.includes(i))])];
  }
  const metaWebIds = ids.filter(i => i.startsWith('meta-web/')).sort();
  if (metaWebIds.length) {
    const flagships = ['meta-web/meta/llama-4-maverick','meta-web/meta/llama-4-scout','meta-web/meta/llama-3.3-70b','meta-web/meta/llama-3.1-405b','meta-web/meta/llama-3.1-70b'];
    families['meta-web'] = [...new Set([...flagships.filter(i => metaWebIds.includes(i)),
      ...metaWebIds.filter(i => !flagships.includes(i))])];
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

  // re-fetch so combo/* ids are in the picker lists
  try {
    cat = await (await fetch(`${gw}/v1/models`, { signal: AbortSignal.timeout(25000) })).json();
    ids = [...new Set((cat.data || []).map(m => m.id))];
  } catch {}

  // ---- Claude Code: cache seed ----
  const ccCache = path.join(home, '.claude', 'cache');
  fs.mkdirSync(ccCache, { recursive: true });
  const cacheFile = path.join(ccCache, 'gateway-models.json');
  const cache = { baseUrl: gw, fetchedAt: Date.now() + 31536000000, models: ids.map(id => ({ id })) };
  fs.writeFileSync(cacheFile, JSON.stringify(cache));
  ok(`claude cache seeded -> ${cacheFile} (${ids.length} models)`);

  // ---- Claude Code: settings.json env + availableModels (no BOM) ----
  const ccFile = path.join(home, '.claude', 'settings.json');
  let cc = {};
  try { cc = JSON.parse(fs.readFileSync(ccFile, 'utf8')); } catch {}
  cc.env = cc.env || {};
  const env = {
    ANTHROPIC_BASE_URL: gw,
    ANTHROPIC_AUTH_TOKEN: token,
    ANTHROPIC_MODEL: 'auto/coding:reliable',
    ANTHROPIC_SMALL_FAST_MODEL: 'auto/best-fast',
    CLAUDE_CODE_USE_GATEWAY: 'true',
    CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY: 'true',
    CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT: '1',
  };
  for (const [k, v] of Object.entries(env)) cc.env[k] = cc.env[k] || v;
  const curAvail = Array.isArray(cc.availableModels) ? cc.availableModels : [];
  const merged = [...new Set([...curAvail, ...ids])].sort();
  cc.availableModels = merged;
  fs.writeFileSync(ccFile, JSON.stringify(cc, null, 2) + '\n');
  ok(`claude settings.json: env wired + ${merged.length} availableModels`);

  // ---- Claude Code: native-binary picker patch (same-length byte replace) ----
  // Patches EVERY /(claude|anthropic)/i.test(...) filter site - the [Bootstrap]
  // fetch AND the [gatewayDiscovery] periodic refetch (the refetch replaces the
  // cached model list with its filtered result, collapsing the picker again -
  // the "it worked, then broke again" loop). The binary also contains an inert
  // string-table copy of the regex - it is NOT a filter (no preceding '/') and
  // is left alone.
  const ccBin = sh('command -v claude');
  if (ccBin) {
    let real = ccBin;
    try { real = fs.realpathSync(ccBin); } catch {}
    try {
      const buf = fs.readFileSync(real);
      const oldS = Buffer.from('(claude|anthropic)');
      const newS = Buffer.from('(.{0,0}|anthropic)');
      const testS = Buffer.from('/i.test(');
      const isFilter = (b, at) => at > 0 && b[at - 1] === 0x2f &&
        b.subarray(at + oldS.length, at + oldS.length + testS.length).equals(testS);
      const sites = [];
      let idx = 0;
      while ((idx = buf.indexOf(oldS, idx)) !== -1) {
        if (isFilter(buf, idx)) sites.push(idx);
        idx += oldS.length;
      }
      const patched = [];
      idx = 0;
      while ((idx = buf.indexOf(newS, idx)) !== -1) {
        if (isFilter(buf, idx)) patched.push(idx);
        idx += newS.length;
      }
      if (sites.length === 0) {
        if (patched.length > 0) log(`claude picker already patched (${patched.length} filter site(s))`);
        else log('claude binary: picker filter marker not found (this build may not need it)');
      } else {
        if (!fs.existsSync(real + '.bak-filtered')) fs.copyFileSync(real, real + '.bak-filtered');
        const b2 = Buffer.from(buf);
        for (const s of sites) newS.copy(b2, s);
        fs.writeFileSync(real, b2);
        ok(`claude picker patch applied at ${sites.length} filter site(s) (every route now in /model)`);
      }
    } catch (e) { log('claude binary patch skipped:', e.message); }
  } else log('claude CLI not installed - skipping claude wiring');

  // ---- Codex: catalog + config.toml ----
  if (sh('command -v codex')) {
    const codexDir = path.join(home, '.codex');
    fs.mkdirSync(path.join(codexDir, 'model-catalogs'), { recursive: true });
    const catFile = path.join(codexDir, 'model-catalogs', 'omniroute.json');
    const entries = ids.map((id, i) => ({
      slug: id, display_name: id,
      description: `OmniRoute route (${id}) via ${gw}`,
      context_window: 200000, max_context_window: 200000,
      visibility: 'list', supported_in_api: true,
      priority: i, availability_nux: null, upgrade: null,
    }));
    fs.writeFileSync(catFile, JSON.stringify({ models: entries }));
    ok(`codex catalog -> ${catFile} (${entries.length} routes)`);

    const cfg = path.join(codexDir, 'config.toml');
    let raw = '';
    try { raw = fs.readFileSync(cfg, 'utf8'); } catch {}
    // strip old kit-managed lines + omniroute provider block, keep user's rest
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
    ok('codex config.toml wired (omniroute provider + catalog)');
  } else log('codex CLI not installed - skipping codex wiring');

  console.log('\nDone. All gateway routes are now in the pickers.');
  console.log('  - Claude Code: run `claude`, then /model (or /model <route>)');
  console.log('  - Codex:       run `codex`, then /model');
})();
EOF
