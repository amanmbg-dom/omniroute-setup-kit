#!/data/data/com.termux/files/usr/bin/env bash
# =============================================================================
#  import-transfer.sh - run on the PHONE (Termux). Imports the PC's OmniRoute
#  progress packaged by make-transfer.sh (run on the PC):
#
#    * gateway state - storage.sqlite (ALL pushed web sessions, combos,
#      routes, tokens) + the STORAGE_ENCRYPTION_KEY that unlocks the sessions
#      (and the GitLab Duo OAuth client id for the free gitlab-duo provider)
#    * the omniroute-setup-kit + refresh of the phone's launcher scripts
#    * your Claude Code persona (permissions, agents, commands, skills,
#      memory, rules, scripts, projects)
#
#  Usage (after receiving omniroute-transfer.tar.gz via WhatsApp):
#    tar xzf omniroute-transfer.tar.gz import-transfer.sh
#    bash import-transfer.sh omniroute-transfer.tar.gz
#
#  The phone's own .env PORT/HOST/ZAI_CAPTCHA_WORKER are kept; the phone's
#  fresh storage.sqlite is backed up to ~/.omniroute/backups/import-*.
# =============================================================================
set -uo pipefail

TAR="${1:-omniroute-transfer.tar.gz}"
[ -f "$TAR" ] || { echo "FATAL: $TAR not found (run: tar xzf omniroute-transfer.tar.gz import-transfer.sh first)"; exit 1; }
TMP=~/.omniroute-transfer-import
rm -rf "$TMP"; mkdir -p "$TMP"
tar xzf "$TAR" -C "$TMP" || { echo "FATAL: could not extract $TAR (corrupted/truncated?)"; exit 1; }

say() { echo "[import] $*"; }
ok()  { echo "    ok: $*"; }
OMHOME=~/.omniroute

# ---- 1. stop the stack so the DB can be swapped safely ----
say "Stopping the stack..."
pkill -f "omniroute serve" 2>/dev/null
pkill -f "mimo-web-bridge/bridge.mjs" 2>/dev/null
pkill -f "gemini-bridge/bridge.py" 2>/dev/null
pkill -f "flow-browser/flow-bridge.mjs" 2>/dev/null
sleep 3

# ---- 2. backup the phone's current state ----
BK="$OMHOME/backups/import-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BK"
[ -f "$OMHOME/storage.sqlite" ] && cp "$OMHOME/storage.sqlite" "$BK/" 2>/dev/null
[ -f "$OMHOME/.env" ] && cp "$OMHOME/.env" "$BK/.env"
ok "phone state backed up to $BK"

# ---- 3. merge the PC .env into the phone .env ----
#      keep the phone's PORT/HOST/ZAI_CAPTCHA_WORKER; import the PC's
#      STORAGE_ENCRYPTION_KEY (unlocks the imported sessions) + GitLab Duo id.
if [ -f "$TMP/pc-env/.env" ]; then
  node - "$OMHOME/.env" "$TMP/pc-env/.env" <<'EOF'
const fs = require('fs');
const [phone, pc] = process.argv.slice(2);
const read = p => { try { return fs.readFileSync(p, 'utf8'); } catch { return ''; } };
const parse = s => Object.fromEntries(s.split('\n')
  .filter(l => l.includes('=') && !l.trim().startsWith('#'))
  .map(l => { const i = l.indexOf('='); return [l.slice(0, i).trim(), l.slice(i + 1).trim()]; }));
const p = parse(read(phone)), c = parse(read(pc));
const keep = ['PORT', 'HOST', 'ZAI_CAPTCHA_WORKER']; // phone-specific
for (const k of Object.keys(c)) if (!keep.includes(k)) p[k] = c[k];
const out = Object.entries(p).map(([k, v]) => `${k}=${v}`).join('\n') + '\n';
fs.writeFileSync(phone, out);
console.log('   env merged: STORAGE_ENCRYPTION_KEY + GitLab Duo imported; PORT/HOST/ZAI_CAPTCHA_WORKER kept');
EOF
  ok ".env merged"
else
  echo "    WARN: pc-env/.env missing - sessions in the imported DB will NOT decrypt"
fi

# ---- 4. import the gateway DB (sessions + combos + routes) ----
if [ -f "$TMP/gateway/storage.sqlite" ]; then
  rm -f "$OMHOME/storage.sqlite" "$OMHOME/storage.sqlite-wal" "$OMHOME/storage.sqlite-shm"
  cp "$TMP/gateway/storage.sqlite" "$OMHOME/storage.sqlite"
  ok "gateway DB imported (sessions + combos + routes)"
else
  echo "    WARN: gateway/storage.sqlite missing"
fi

# ---- 5. install the kit + refresh the phone launcher scripts ----
if [ -d "$TMP/kit" ]; then
  mkdir -p ~/omniroute-setup-kit
  cp -r "$TMP/kit/." ~/omniroute-setup-kit/
  ok "kit installed to ~/omniroute-setup-kit"
  if [ -f ~/omniroute-setup-kit/android/fix-model-cache.sh ]; then
    mkdir -p ~/omniroute-android
    cp ~/omniroute-setup-kit/android/fix-model-cache.sh ~/omniroute-android/
    cp ~/omniroute-setup-kit/android/start-omniroute.sh ~/omniroute-android/ 2>/dev/null || true
    cp ~/omniroute-setup-kit/android/boot.sh ~/omniroute-android/ 2>/dev/null || true
    chmod +x ~/omniroute-android/fix-model-cache.sh ~/omniroute-android/start-omniroute.sh ~/omniroute-android/boot.sh
    ok "launcher scripts refreshed in ~/omniroute-android"
  fi
else
  echo "    WARN: kit/ missing"
fi

# ---- 6. Claude Code persona ----
#      settings.json: merge permissions ONLY - env comes from fix-model-cache,
#      and the PC's hooks reference Windows-only tools (rtk) that would
#      BLOCK tool use on the phone if copied verbatim.
if [ -d "$TMP/claude" ]; then
  mkdir -p ~/.claude
  node - "$TMP/claude/settings.json" <<'EOF' || true
const fs = require('fs');
const pc = process.argv[2];
const cur = {};
try { Object.assign(cur, JSON.parse(fs.readFileSync(process.env.HOME + '/.claude/settings.json', 'utf8'))); } catch {}
try {
  const pcj = JSON.parse(fs.readFileSync(pc, 'utf8'));
  if (pcj.permissions) cur.permissions = Object.assign({}, cur.permissions, pcj.permissions);
  fs.writeFileSync(process.env.HOME + '/.claude/settings.json', JSON.stringify(cur, null, 2) + '\n');
  console.log('   permissions merged (PC hooks skipped - Windows-only)');
} catch (e) { console.log('   settings merge skipped:', e.message); }
EOF
  for d in agents commands skills memory rules scripts projects; do
    if [ -d "$TMP/claude/$d" ]; then
      mkdir -p ~/.claude/$d
      cp -r "$TMP/claude/$d/." ~/.claude/$d/
      ok "claude/$d imported"
    fi
  done
fi

rm -rf "$TMP"

# ---- 7. restart the stack + sync the pickers ----
say "Restarting the stack..."
bash ~/omniroute-android/start-omniroute.sh
say "Syncing Codex / Claude Code pickers..."
if [ -x ~/omniroute-android/fix-model-cache.sh ]; then
  bash ~/omniroute-android/fix-model-cache.sh || echo "    (picker sync failed - claude/codex not installed? rerun later)"
else
  echo "    (fix-model-cache.sh missing)"
fi

# ---- 8. Claude Code MCP servers (the same set as the PC) ----
if command -v claude >/dev/null 2>&1; then
  say "Registering Claude Code MCP servers..."
  # flowui (the stack's image bridge) - phone path, Windows path was PC-only
  claude mcp remove flowui >/dev/null 2>&1 || true
  claude mcp add -s user flowui -- node ~/omniroute-android/bridge/flow-browser/flowui-mcp.mjs >/dev/null 2>&1 \
    && ok "mcp: flowui (image gen - needs the flowui bridge up)" \
    || echo "    (mcp flowui failed - run: claude mcp add -s user flowui -- node ~/omniroute-android/bridge/flow-browser/flowui-mcp.mjs)"
  # portable npx servers - mirror of the PC's ~/.claude.json mcpServers
  # (downloads happen on first use, not now)
  declare -A MCP=(
    [playwright]="npx -y @playwright/mcp@latest"
    [context7]="npx -y @context7/mcp-server@latest"
    [chrome-devtools]="npx -y chrome-devtools-mcp@latest"
    [sequential-thinking]="npx -y @modelcontextprotocol/server-sequential-thinking@latest"
    [everything]="npx -y @modelcontextprotocol/server-everything@latest"
    [fetch]="npx -y @modelcontextprotocol/server-fetch@latest"
    [memory]="npx -y @modelcontextprotocol/server-memory@latest --storage-path ~/.claude/memory/memory.json"
    [filesystem]="npx -y @modelcontextprotocol/server-filesystem@latest ~"
    [github]="npx -y @modelcontextprotocol/server-github@latest"
  )
  for name in "${!MCP[@]}"; do
    claude mcp remove "$name" >/dev/null 2>&1 || true
    if claude mcp add -s user "$name" -- ${MCP[$name]} >/dev/null 2>&1; then
      ok "mcp: $name"
    else
      echo "    (mcp $name failed - add later: claude mcp add -s user $name -- ${MCP[$name]})"
    fi
  done
  echo "    note: github needs a GITHUB_TOKEN to answer; npx servers download on first use"
else
  echo "    (claude CLI not installed - MCP servers skipped; run fix-model-cache.sh after installing claude)"
fi

echo
echo "DONE - your PC progress is on the phone:"
echo "  * gateway sessions/combos/routes imported (same encryption key)"
echo "  * kit at ~/omniroute-setup-kit"
echo "  * Claude persona (skills/agents/commands) at ~/.claude"
echo "Verify: curl -s http://127.0.0.1:20128/v1/models | grep -c combo"
