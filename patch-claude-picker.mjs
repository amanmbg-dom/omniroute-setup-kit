#!/usr/bin/env node
// patch-claude-picker.mjs — Patch Claude Code's gateway-discovery filter
// Supports both old /(claude|anthropic)/ and new ^(claude|anthropic) patterns.

import fs from "node:fs";
import os from "node:os";

const exe = process.argv[2];
const OLD = Buffer.from("(claude|anthropic)");
const NEW = Buffer.from("(.{0,0}|anthropic)");
const TEST = "/i.test(";

function findSites(buf, needle) {
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

const buf = fs.readFileSync(exe);
const sites = findSites(buf, OLD);
const patched = findSites(buf, NEW);

if (sites.length === 0) {
  if (patched.length > 0) {
    console.log(`ALREADY PATCHED - nothing to do (${patched.length} filter site(s) patched)`);
    process.exit(0);
  }
  console.error("ANCHOR NOT FOUND - this Claude Code version changed the gateway-discovery code.");
  process.exit(3);
}

if (OLD.length !== NEW.length) throw new Error("length mismatch");

const bak = exe + ".bak-filtered";
if (!fs.existsSync(bak)) { fs.copyFileSync(exe, bak); console.log(`backup: ${bak}`); }

const b2 = Buffer.from(buf);
for (const s of sites) NEW.copy(b2, s);
fs.writeFileSync(exe, b2);

console.log(`Patched ${sites.length} filter site(s) in ${exe}`);
for (const s of sites) {
  const ctx = b2.subarray(Math.max(0, s - 10), s + OLD.length + 20).toString("utf8").replace(/[^\x20-\x7E]/g, ".");
  console.log(`  offset ${s}: ...${ctx}...`);
}
