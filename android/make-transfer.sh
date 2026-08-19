#!/usr/bin/env bash
# =============================================================================
#  make-transfer.sh - run on the PC (Git Bash). Packages everything needed to
#  move the OmniRoute progress to the phone into ONE archive:
#
#    * gateway state - a consistent WAL-safe snapshot of storage.sqlite
#      (ALL pushed web sessions, combos, routes, tokens) + ~/.omniroute/.env
#      (the STORAGE_ENCRYPTION_KEY that unlocks those sessions, plus the
#      GitLab Duo OAuth client id for the free gitlab-duo Claude provider)
#    * the full omniroute-setup-kit (bridges, skills, commands, patch
#      scripts, vps, docs, the android installer)
#    * your Claude Code persona (settings/permissions, agents, commands,
#      skills, memory, rules, scripts, projects)
#
#  Output: ~/omniroute-setup-kit/omniroute-transfer.tar.gz
#
#  Then send that ONE file to the phone (WhatsApp), and on the phone:
#    tar xzf omniroute-transfer.tar.gz import-transfer.sh
#    bash import-transfer.sh omniroute-transfer.tar.gz
# =============================================================================
set -euo pipefail

KIT=~/omniroute-setup-kit
OUT="$KIT/transfer"
STAGE="$KIT/transfer-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE/gateway" "$STAGE/pc-env" "$STAGE/kit" "$STAGE/claude"

echo "[1/4] Gateway snapshot (WAL-safe copy of storage.sqlite)..."
node - "$HOME/.omniroute/storage.sqlite" "$STAGE/gateway/storage.sqlite" <<'EOF'
const { DatabaseSync } = require('node:sqlite');
const [src, dst] = process.argv.slice(2);
const db = new DatabaseSync(src, { readOnly: true });
db.exec(`VACUUM INTO '${dst.replace(/'/g, "''")}'`);
db.close();
console.log('   snapshot:', dst);
EOF
cp "$HOME/.omniroute/.env" "$STAGE/pc-env/.env"
echo "   .env copied (keys: $(grep -oE '^[A-Z_]+' "$HOME/.omniroute/.env" | tr '\n' ' '))"

echo "[2/4] Kit (omniroute-setup-kit, junk excluded)..."
tar cf - -C "$KIT" \
  --exclude='node_modules' --exclude='.venv' --exclude='venv' \
  --exclude='__pycache__' --exclude='screenshots-debug' --exclude='*.log' \
  --exclude='.git' --exclude='transfer' --exclude='transfer-stage' \
  --exclude='omniroute-transfer.tar.gz' . | (cd "$STAGE/kit" && tar xf -)

echo "[3/4] Claude Code persona..."
cp "$HOME/.claude/settings.json" "$STAGE/claude/" 2>/dev/null || true
for d in agents commands skills memory rules scripts projects; do
  if [ -d "$HOME/.claude/$d" ]; then
    echo "   ~/.claude/$d"
    # -L dereferences symlinked skills; broken symlinks (nonexistent targets)
    # are skipped - they are dead on the PC anyway.
    cp -rL "$HOME/.claude/$d" "$STAGE/claude/" 2>/dev/null \
      || echo "   (a few broken symlinks in $d were skipped - harmless)"
  fi
done

echo "[4/4] Archiving + embedding the importer..."
cp "$KIT/android/import-transfer.sh" "$STAGE/import-transfer.sh"
(cd "$STAGE" && tar czf "$KIT/omniroute-transfer.tar.gz" .)
rm -rf "$STAGE"

SIZE=$(ls -lh "$KIT/omniroute-transfer.tar.gz" | awk '{print $5}')
SHA=$(sha256sum "$KIT/omniroute-transfer.tar.gz" | awk '{print $1}')
echo
echo "DONE: $KIT/omniroute-transfer.tar.gz  ($SIZE)"
echo "sha256: $SHA"
echo
echo "Send this ONE file to the phone (WhatsApp), then in Termux:"
echo "  tar xzf omniroute-transfer.tar.gz import-transfer.sh"
echo "  bash import-transfer.sh omniroute-transfer.tar.gz"
