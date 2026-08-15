// patch-claude-picker.mjs
// Byte-patches the Claude Code native binary so the gateway model bootstrap
// (additional_model_options -> /model picker) keeps ALL gateway catalog models
// instead of filtering to /(claude|anthropic)/i names.
//
// Same-length byte replacement: (claude|anthropic) -> (.{0,0}|anthropic)
// The patched regex matches every id, so every gateway route shows in the picker.
//
// Idempotent: detects already-patched state and skips. Verifies the patch.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const HOME = os.homedir();
const exe = process.argv[2];
const MARKER = '/(claude|anthropic)/i.test(o.id)'; // unique to the bootstrap filter ((p) is the refetch)
const OLD = '(claude|anthropic)';
const NEW = '(.{0,0}|anthropic)'; // same byte length as OLD

if (!exe) { console.error('usage: node patch-claude-picker.mjs <claude.exe>'); process.exit(2); }
if (!fs.existsSync(exe)) { console.error(`not found: ${exe}`); process.exit(2); }

const buf = fs.readFileSync(exe);
const markerIdx = buf.indexOf(MARKER);
if (markerIdx === -1) {
  // Check if already patched (marker replaced by the patched regex).
  const patchedMarker = '/(.{0,0}|anthropic)/i.test(o.id)';
  if (buf.indexOf(patchedMarker) !== -1) {
    console.log('ALREADY PATCHED - nothing to do');
    process.exit(0);
  }
  console.error('ANCHOR NOT FOUND - this Claude Code version changed the bootstrap code.');
  console.error('The gateway-model discovery mechanism needs re-review for this build.');
  process.exit(3);
}

const oldStart = buf.indexOf(OLD, markerIdx);
if (oldStart === -1 || oldStart !== markerIdx + 1) {
  console.error(`unexpected layout at offset ${markerIdx}`);
  process.exit(3);
}
if (OLD.length !== NEW.length) throw new Error('length mismatch - patch must be same-length');

// Backup once
const ver = path.basename(path.dirname(path.dirname(path.dirname(exe)))); // .../anthropic.claude-code-X.Y.Z-win32-x64/...
const backupDir = path.join(HOME, '.omniroute', 'backups');
fs.mkdirSync(backupDir, { recursive: true });
const backup = path.join(backupDir, `claude.exe.${ver}.${Date.now()}.bak`);
fs.copyFileSync(exe, backup);
console.log(`backup: ${backup}`);

buf.write(NEW, oldStart, 'latin1');
try {
  fs.writeFileSync(exe, buf);
} catch (err) {
  if (err.code === 'EBUSY' || err.code === 'EPERM') {
    console.error('BINARY LOCKED - a Claude Code session is running. Close Claude Code');
    console.error('(VS Code panel + any `claude` terminals) and re-run this script.');
    process.exit(5);
  }
  throw err;
}

// Verify
const check = fs.readFileSync(exe);
if (check.indexOf(NEW, oldStart) === oldStart && check.indexOf(OLD, oldStart) === -1) {
  console.log(`PATCHED ok: ${exe}`);
  console.log(`  ${OLD} -> ${NEW} @ ${oldStart}`);
} else {
  console.error('VERIFY FAILED - binary may be corrupt; restore from backup!');
  process.exit(4);
}
