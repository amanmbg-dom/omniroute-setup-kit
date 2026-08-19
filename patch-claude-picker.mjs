// patch-claude-picker.mjs
// Byte-patches a Claude Code native binary so the gateway model discovery
// (additional_model_options -> /model picker) keeps ALL gateway catalog models
// instead of filtering to /(claude|anthropic)/i names.
//
// Claude Code >= 2.1.233 has TWO gateway-discovery filter sites:
//   1. the [Bootstrap] fetch          -> /(claude|anthropic)/i.test(o.id)
//   2. the [gatewayDiscovery] refetch -> /(claude|anthropic)/i.test(p.id)
// The refetch REPLACES the cached model list with its filtered result, so an
// unpatched refetch collapses the picker back to claude-named models even
// after the bootstrap site is patched - the "it worked, then broke again"
// loop. This patcher finds EVERY /(claude|anthropic)/i.test(...) filter site
// in the binary (any minified variable name) and applies the same-length byte
// replace (claude|anthropic) -> (.{0,0}|anthropic) to all of them.
//
// Same-length replacement: (claude|anthropic) and (.{0,0}|anthropic) are both
// 18 bytes, so offsets never shift. Idempotent: sites already patched are
// skipped; when no unpatched filter site remains it reports ALREADY PATCHED
// and exits 0. Verifies after write. Works on the VS Code extension's
// resources/native-binary/claude.exe AND the standalone ~/.local/bin/claude.exe.
//
// Exit codes: 0 ok (patched or already patched) | 2 usage/not found |
// 3 anchor not found (this build changed the gateway-discovery code - needs
//   re-review) | 4 verify failed (binary may be corrupt - restore from backup) |
// 5 binary locked by a running Claude Code session (retry later).
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const HOME = os.homedir();
const exe = process.argv[2];
const OLD = '(claude|anthropic)';
const NEW = '(.{0,0}|anthropic)'; // same byte length as OLD
const TEST = '/i.test(';          // filter sites are /(claude|anthropic)/i.test(x.id)

// Offsets of every needle occurrence that is a regex filter literal (preceded
// by '/' and followed by '/i.test('). The binary also contains one inert
// string-table copy of OLD that is NOT a filter - it is left alone.
function findSites(buf, needle) {
  const sites = [];
  let idx = 0;
  while ((idx = buf.indexOf(needle, idx)) !== -1) {
    if (idx > 0 && buf[idx - 1] === 0x2f /* '/' */ &&
        buf.subarray(idx + needle.length, idx + needle.length + TEST.length).toString('latin1') === TEST) {
      sites.push(idx);
    }
    idx += needle.length;
  }
  return sites;
}

if (!exe) { console.error('usage: node patch-claude-picker.mjs <claude.exe>'); process.exit(2); }
if (!fs.existsSync(exe)) { console.error(`not found: ${exe}`); process.exit(2); }

const buf = fs.readFileSync(exe);
const sites = findSites(buf, OLD);
const patched = findSites(buf, NEW);

if (sites.length === 0) {
  if (patched.length > 0) {
    console.log(`ALREADY PATCHED - nothing to do (${patched.length} filter site(s) patched)`);
    process.exit(0);
  }
  console.error('ANCHOR NOT FOUND - this Claude Code version changed the gateway-discovery code.');
  console.error('The /model picker patch needs re-review for this build.');
  process.exit(3);
}

if (OLD.length !== NEW.length) throw new Error('length mismatch - patch must be same-length');

// Backup once (only when something will actually be patched).
const verMatch = exe.match(/anthropic\.claude-code-([0-9.]+)/);
const ver = verMatch ? verMatch[1] : 'standalone-cli';
const backupDir = path.join(HOME, '.omniroute', 'backups');
fs.mkdirSync(backupDir, { recursive: true });
const backup = path.join(backupDir, `claude.exe.${ver}.${Date.now()}.bak`);
fs.copyFileSync(exe, backup);
console.log(`backup: ${backup}`);

for (const site of sites) buf.write(NEW, site, 'latin1');
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
const remaining = findSites(check, OLD);
const patchedAfter = findSites(check, NEW);
if (remaining.length === 0 && patchedAfter.length >= 1) {
  const was = patched.length > 0 ? ` (${patched.length} site(s) were already patched)` : '';
  console.log(`PATCHED ok: ${exe}`);
  console.log(`  ${OLD} -> ${NEW} at ${sites.join(', ')} - ${sites.length} filter site(s) patched${was}; ${patchedAfter.length} patched total`);
} else {
  console.error(`VERIFY FAILED - binary may be corrupt; restore from backup! (${remaining.length} unpatched site(s) left)`);
  process.exit(4);
}
