#!/usr/bin/env node
// patch-claude-picker.mjs — Patch Claude Code's gateway-discovery filter AND Bootstrap env var gate
// v2: Now patches 3 things:
//   1. Filter regex: (claude|anthropic) → (.{0,0}|anthropic)
//   2. WIc() return!1 → return!0 (always enable gateway discovery)
//   3. Ll_() return w( → 0;     w( (remove Bootstrap skip return)

import fs from "node:fs";

const exe = process.argv[2];
const OLD_FILTER = Buffer.from("(claude|anthropic)");
const NEW_FILTER = Buffer.from("(.{0,0}|anthropic)");
const TEST = "/i.test(";
const ENV_VAR = "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY";

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

// === PATCH 2: WIc() return!1 → return!0 ===
const envVarSites = findAll(buf, Buffer.from(ENV_VAR));
let wiPatched = 0;
for (const envPos of envVarSites) {
  // Search backward 100 bytes for "return!1"
  const searchStart = Math.max(0, envPos - 100);
  const chunk = buf.subarray(searchStart, envPos);
  const retIdx = chunk.lastIndexOf(Buffer.from("return!1"));
  if (retIdx !== -1) {
    const absPos = searchStart + retIdx;
    buf[absPos + 7] = 0x30; // change '1' to '0'
    wiPatched++;
    console.log(`WIc: return!1→return!0 at offset ${absPos}`);
  }
}
if (wiPatched === 0) {
  // Check if already patched
  const hasReturn0 = envVarSites.some(pos => {
    const chunk = buf.subarray(Math.max(0, pos - 100), pos);
    return chunk.includes(Buffer.from("return!0"));
  });
  console.log(`WIc: ${hasReturn0 ? "already patched" : "no return!1 found near env var checks"}`);
}
totalPatches += wiPatched;

// === PATCH 3: Ll_() return w( → 0;     w( ===
const skipMsgs = findAll(buf, Buffer.from("[Bootstrap] Skipped gateway"));
let llPatched = 0;
for (const msgPos of skipMsgs) {
  const searchStart = Math.max(0, msgPos - 50);
  const chunk = buf.subarray(searchStart, msgPos);
  const rwIdx = chunk.lastIndexOf(Buffer.from("return w("));
  if (rwIdx !== -1) {
    const absPos = searchStart + rwIdx;
    const replacement = Buffer.from("0;     w(");
    replacement.copy(buf, absPos);
    llPatched++;
    console.log(`Ll_: return w(→0;     w( at offset ${absPos}`);
  }
}
if (llPatched === 0) {
  const alreadyPatched = skipMsgs.some(pos => {
    const chunk = buf.subarray(Math.max(0, pos - 50), pos);
    return chunk.includes(Buffer.from("0;     w("));
  });
  console.log(`Ll_: ${alreadyPatched ? "already patched" : "no return w( found near skip messages"}`);
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
