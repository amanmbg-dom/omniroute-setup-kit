#!/usr/bin/env node
// patch-claude-picker.mjs — Comprehensive Claude Code binary patcher
// v3: Patches ALL Bootstrap skip conditions + filter regex
//
// Patches applied:
//   1. Filter regex: (claude|anthropic) → (.{0,0}|anthropic)  (all filter sites)
//   2. ALL return!1 near CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY → return!0
//   3. ONLY specific Bootstrap SKIP conditions (not success/error returns):
//      - "Skipped gateway /v1/models" (env var gate)
//      - "Skipped: Nonessential traffic disabled"
//      - "Skipped: 3P provider"
//      - "Response failed validation"

import fs from "node:fs";

const exe = process.argv[2];
const OLD_FILTER = Buffer.from("(claude|anthropic)");
const NEW_FILTER = Buffer.from("(.{0,0}|anthropic)");
const TEST = "/i.test(";
const ENV_VAR = "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY";

// Only patch these specific skip conditions (NOT success returns like "Fetch ok")
const SKIP_MESSAGES = [
  Buffer.from("[Bootstrap] Skipped gateway /v1/models"),
  Buffer.from("[Bootstrap] Skipped: Nonessential traffic disabled"),
  Buffer.from("[Bootstrap] Skipped: 3P provider"),
  Buffer.from("[Bootstrap] Response failed validation"),
];

function findAll(buf, needle) {
  const sites = [];
  let idx = 0;
  while ((idx = buf.indexOf(needle, idx)) !== -1) {
    sites.push(idx);
    idx += needle.length;
  }
  return sites;
}

function findFilterSites(buf, needle) {
  const sites = [];
  let idx = 0;
  while ((idx = buf.indexOf(needle, idx)) !== -1) {
    const before = buf[idx - 1];
    const after = buf.subarray(idx + needle.length, idx + needle.length + TEST.length).toString("latin1");
    const isFilter = (before === 0x2f || before === 0x5e) && after === TEST;
    if (isFilter) sites.push(idx);
    idx += needle.length;
  }
  return sites;
}

if (!exe) { console.error("usage: node patch-claude-picker.mjs <claude.exe>"); process.exit(2); }
if (!fs.existsSync(exe)) { console.error(`not found: ${exe}`); process.exit(2); }

const buf = Buffer.from(fs.readFileSync(exe));
let totalPatches = 0;

// === PATCH 1: Filter patterns ===
const filterSites = findFilterSites(buf, OLD_FILTER);
const filterPatched = findFilterSites(buf, NEW_FILTER);

if (filterSites.length > 0) {
  if (OLD_FILTER.length !== NEW_FILTER.length) throw new Error("filter length mismatch");
  for (const s of filterSites) NEW_FILTER.copy(buf, s);
  totalPatches += filterSites.length;
  console.log(`Filter: patched ${filterSites.length} site(s)`);
} else if (filterPatched.length > 0) {
  console.log(`Filter: already patched (${filterPatched.length} site(s))`);
} else {
  console.log("Filter: no filter sites found (new version?)");
}

// === PATCH 2: ALL return!1 near env var → return!0 ===
const envVarSites = findAll(buf, Buffer.from(ENV_VAR));
let wiPatched = 0;
for (const envPos of envVarSites) {
  const start = Math.max(0, envPos - 300);
  const end = Math.min(buf.length, envPos + 300);
  const chunk = buf.subarray(start, end);
  let searchFrom = 0;
  while (true) {
    const ret1 = chunk.indexOf(Buffer.from("return!1"), searchFrom);
    if (ret1 === -1) break;
    const absPos = start + ret1;
    buf[absPos + 7] = 0x30; // '1' → '0'
    wiPatched++;
    console.log(`WIc: return!1→return!0 at offset ${absPos}`);
    searchFrom = ret1 + 1;
  }
}
if (wiPatched === 0) {
  console.log(`WIc: already patched or no return!1 found`);
}
totalPatches += wiPatched;

// === PATCH 3: ONLY specific Bootstrap skip conditions ===
let llPatched = 0;
for (const msg of SKIP_MESSAGES) {
  const sites = findAll(buf, msg);
  for (const msgPos of sites) {
    // Search backward 100 bytes for return w( or return w`
    const searchStart = Math.max(0, msgPos - 100);
    const chunk = buf.subarray(searchStart, msgPos);

    for (const [pattern, replacement] of [
      [Buffer.from("return w("), Buffer.from("0;     w(")],
      [Buffer.from("return w`"), Buffer.from("0;     w`")],
    ]) {
      const idx = chunk.lastIndexOf(pattern);
      if (idx !== -1) {
        const absPos = searchStart + idx;
        // Only patch if this is in the CODE section (>20000000), not the data section
        if (absPos > 20000000) {
          replacement.copy(buf, absPos);
          llPatched++;
          const msgText = msg.toString("latin1").slice(0, 45);
          console.log(`Ll_: ${pattern.toString()}→${replacement.toString()} at ${absPos}: ${msgText}`);
        }
      }
    }
  }
}
if (llPatched === 0) {
  console.log(`Ll_: already patched or no skip returns found`);
}
totalPatches += llPatched;

// === Write results ===
if (totalPatches > 0) {
  const bak = exe + ".bak-patcher";
  if (!fs.existsSync(bak)) { fs.copyFileSync(exe, bak); console.log(`backup: ${bak}`); }
  fs.writeFileSync(exe, buf);
  console.log(`\nTotal: ${totalPatches} new patches applied to ${exe}`);
} else {
  console.log(`\nTotal: nothing to patch (already up to date)`);
}
