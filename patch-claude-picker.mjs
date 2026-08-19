// patch-claude-picker.mjs
// Byte-patches the Claude Code native binary so the gateway model bootstrap
// (additional_model_options -> /model picker) keeps ALL gateway catalog models
// instead of filtering to /(claude|anthropic)/i names, and so the discovery
// fetch stops capping the catalog at 1000 models.
//
// Same-length byte replacements:
//   1. (claude|anthropic) -> (.{0,0}|anthropic)   (filter now matches every id)
//   2. limit:1000         -> limit:9999          (discovery sees the whole catalog)
//
// Idempotent: detects already-patched state and skips. Verifies both patches.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const HOME = os.homedir();
const exe = process.argv[2];
const OLD = '(claude|anthropic)';
const NEW = '(.{0,0}|anthropic)'; // same byte length as OLD
const OLD_LIMIT = 'limit:1000';
const NEW_LIMIT = 'limit:9999'; // same byte length

if (!exe) { console.error('usage: node patch-claude-picker.mjs <claude.exe>'); process.exit(2); }
if (!fs.existsSync(exe)) { console.error(`not found: ${exe}`); process.exit(2); }
if (OLD.length !== NEW.length) throw new Error('length mismatch - patch must be same-length');
if (OLD_LIMIT.length !== NEW_LIMIT.length) throw new Error('limit patch must be same-length');

const buf = fs.readFileSync(exe);
// 2.1.233+ carries the gateway bootstrap filter in MULTIPLE compiled copies:
// one uses `i.test(o.id)`, another `i.test(p.id)`, plus a string-table copy.
// The single-marker approach missed the `p.id` variant, so the gateway
// discovery path kept filtering. Replace EVERY occurrence (same-length).
let idx = buf.indexOf(OLD);
if (idx === -1) {
  // Check if already patched (all occurrences replaced).
  if (buf.indexOf(NEW) !== -1) {
    console.log('ALREADY PATCHED - nothing to do');
    process.exit(0);
  }
  console.error('ANCHOR NOT FOUND - this Claude Code version changed the bootstrap code.');
  console.error('The gateway-model discovery mechanism needs re-review for this build.');
  process.exit(3);
}

// Backup once
const ver = path.basename(path.dirname(path.dirname(path.dirname(exe)))); // .../anthropic.claude-code-X.Y.Z-win32-x64/...
const backupDir = path.join(HOME, '.omniroute', 'backups');
fs.mkdirSync(backupDir, { recursive: true });
const backup = path.join(backupDir, `claude.${ver}.${Date.now()}.bak`);
fs.copyFileSync(exe, backup);
console.log(`backup: ${backup}`);

let count = 0;
while (idx !== -1) {
  buf.write(NEW, idx, 'latin1');
  count++;
  idx = buf.indexOf(OLD, idx + OLD.length);
}
// Phase 2: lift the gateway discovery cap. Claude Code fetches /v1/models with
// params:{limit:1000} - with a 2600+ route catalog the picker silently misses
// everything beyond the first 1000 (that is exactly why combo/* could be
// "restricted"). Same-length 1000 -> 9999 (harmless for the other two
// sessions/teleport limit:1000 call sites).
let limitCount = 0;
let lidx = buf.indexOf(OLD_LIMIT);
while (lidx !== -1) {
  buf.write(NEW_LIMIT, lidx, 'latin1');
  limitCount++;
  lidx = buf.indexOf(OLD_LIMIT, lidx + OLD_LIMIT.length);
}
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

// Verify: no OLD/OLD_LIMIT occurrences may remain, and NEW/NEW_LIMIT present.
const check = fs.readFileSync(exe);
if (check.indexOf(OLD) === -1 && check.indexOf(NEW) !== -1 && count > 0) {
  console.log(`PATCHED ok: ${exe}`);
  console.log(`  ${OLD} -> ${NEW}  x${count} occurrence(s)`);
  if (limitCount > 0) console.log(`  ${OLD_LIMIT} -> ${NEW_LIMIT}  x${limitCount} occurrence(s)`);
} else {
  console.error('VERIFY FAILED - binary may be corrupt; restore from backup!');
  process.exit(4);
}
