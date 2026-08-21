#!/usr/bin/env node
// patch-claude-desktop.mjs — Auto-repatch Claude Desktop for free model access
//
// Patches applied:
//   1. Ro() → always returns true (all model names valid in picker, not just claude-named)
//   2. tr() → always returns true (MSIX install check bypassed)
//   3. KXt() → always returns {status:"supported"} (Cowork checks bypassed)
//   4. Electron fuse EnableEmbeddedAsarIntegrityValidation → disabled
//
// Usage:
//   node patch-claude-desktop.mjs              # patch once
//   node patch-claude-desktop.mjs --watch      # auto-repatch on updates (checks every 5 min)
//
// Run this after every Claude Desktop update, or use --watch to do it automatically.

import { execSync, spawn } from "node:child_process";
import { existsSync, readFileSync, writeFileSync, statSync } from "node:fs";
import { join } from "node:path";

const CLAUDE_BASE = join(process.env.LOCALAPPDATA, "AnthropicClaude");
const WATCH = process.argv.includes("--watch");
const CHECK_INTERVAL = 5 * 60 * 1000; // 5 minutes

function log(...args) {
  console.log(`[patch-claude ${new Date().toISOString()}]`, ...args);
}

function findClaudeExe() {
  // Find the latest app version directory
  const dirs = execSync(`ls "${CLAUDE_BASE}"`, { encoding: "utf-8" })
    .split("\n")
    .filter(d => d.startsWith("app-"))
    .sort()
    .reverse();
  if (dirs.length === 0) return null;
  const version = dirs[0];
  const exePath = join(CLAUDE_BASE, version, "claude.exe");
  const asarPath = join(CLAUDE_BASE, version, "resources", "app.asar");
  if (!existsSync(exePath) || !existsSync(asarPath)) return null;
  return { version, exePath, asarPath, versionDir: join(CLAUDE_BASE, version) };
}

// ── Patch 1: Ro() — model name validator ─────────────────────────
// Original: function Ro(e){let t=e.toLowerCase();return Dhe.test(t)?!1:The.test(t)||Ehe.some((e=>t.includes(e)))}
// Patched:  function Ro(e){let t=e.toLowerCase();return!0}
function patchRo(data) {
  const old = Buffer.from("function Ro(e){let t=e.toLowerCase();return Dhe.test(t)?!1:The.test(t)||Ehe.some((e=>t.includes(e)))}");
  const replacement = "function Ro(e){let t=e.toLowerCase();return!0}";
  if (data.includes(old)) {
    const padded = Buffer.concat([
      Buffer.from(replacement),
      Buffer.alloc(old.length - replacement.length, 0x20), // spaces
    ]);
    return { data: Buffer.concat([data.subarray(0, data.indexOf(old)), padded, data.subarray(data.indexOf(old) + old.length)]),
      patched: true };
  }
  // Already patched?
  if (data.includes(Buffer.from("function Ro(e){let t=e.toLowerCase();return!0"))) {
    return { data, patched: true, alreadyPatched: true };
  }
  return { data, patched: false };
}

// ── Patch 2: tr() — MSIX install check ───────────────────────────
// Original: function tr(){return $n===void 0?process.windowsStore?(er=`windowsStore`,$n=!0,!0):Tte()?(er=`appPath`,$n=!0,!0):(er=null,$n=!1,!1):$n}
// Patched:  function tr(){return!0}
function patchTr(data) {
  const old = Buffer.from("function tr(){return $n===void 0?process.windowsStore?(er=`windowsStore`,$n=!0,!0):Tte()?(er=`appPath`,$n=!0,!0):(er=null,$n=!1,!1):$n}");
  const replacement = "function tr(){return!0}";
  if (data.includes(old)) {
    const padded = Buffer.concat([
      Buffer.from(replacement),
      Buffer.alloc(old.length - replacement.length, 0x20),
    ]);
    return { data: Buffer.concat([data.subarray(0, data.indexOf(old)), padded, data.subarray(data.indexOf(old) + old.length)]),
      patched: true };
  }
  if (data.includes(Buffer.from("function tr(){return!0"))) {
    return { data, patched: true, alreadyPatched: true };
  }
  return { data, patched: false };
}

// ── Patch 3: KXt() — Cowork status check ─────────────────────────
// Replaces the entire KXt function (which checks MSIX, HCS, virtualization, etc.)
// with: function KXt(){return{status:`supported`}}
function patchKXt(data) {
  const text = data.toString("utf-8");
  const start = text.indexOf("function KXt(){");
  if (start < 0) {
    // Already patched?
    if (text.includes("function KXt(){return{status:`supported`}}")) {
      return { data, patched: true, alreadyPatched: true };
    }
    return { data, patched: false };
  }

  // Find matching closing brace
  let braceCount = 0;
  let end = -1;
  for (let i = start; i < Math.min(text.length, start + 5000); i++) {
    if (text[i] === "{") braceCount++;
    else if (text[i] === "}") {
      braceCount--;
      if (braceCount === 0) { end = i + 1; break; }
    }
  }
  if (end < 0) return { data, patched: false };

  const oldFunc = text.slice(start, end);
  const replacement = "function KXt(){return{status:`supported`}}";
  const oldBytes = Buffer.from(oldFunc, "utf-8");
  const newBytes = Buffer.from(replacement, "utf-8");

  if (newBytes.length < oldBytes.length) {
    // Pad with /* ... */ comment
    const padding = oldBytes.length - newBytes.length;
    const padded = Buffer.concat([
      newBytes.subarray(0, newBytes.length - 1), // remove trailing }
      Buffer.from("/*"),
      Buffer.alloc(padding - 4, 0x20), // spaces
      Buffer.from("*/}"),
    ]);
    return {
      data: Buffer.concat([data.subarray(0, start), padded, data.subarray(start + oldBytes.length)]),
      patched: true,
    };
  }
  return { data, patched: false };
}

// ── Patch 4: Disable Electron ASAR integrity fuse ─────────────────
function disableFuse(exePath) {
  try {
    execSync(`npx @electron/fuses write --app "${exePath}" EnableEmbeddedAsarIntegrityValidation=off`, {
      stdio: "pipe",
      timeout: 30000,
    });
    return true;
  } catch (e) {
    // Check if already disabled
    try {
      const out = execSync(`npx @electron/fuses read --app "${exePath}"`, {
        stdio: "pipe",
        timeout: 30000,
        encoding: "utf-8",
      });
      if (out.includes("EnableEmbeddedAsarIntegrityValidation is Disabled")) return true;
    } catch {}
    log(`Fuse disable failed: ${e.message}`);
    return false;
  }
}

// ── Main ──────────────────────────────────────────────────────────

function patchAll() {
  const info = findClaudeExe();
  if (!info) {
    log("Claude Desktop not found. Install it first.");
    return false;
  }

  log(`Found Claude Desktop ${info.version}`);

  // Check if already patched
  const data = readFileSync(info.asarPath);
  const text = data.toString("utf-8");
  const alreadyRo = text.includes("function Ro(e){let t=e.toLowerCase();return!0");
  const alreadyTr = text.includes("function tr(){return!0");
  const alreadyKXt = text.includes("function KXt(){return{status:`supported`}}");

  if (alreadyRo && alreadyTr && alreadyKXt) {
    // Check fuse too
    try {
      const out = execSync(`npx @electron/fuses read --app "${info.exePath}"`, {
        stdio: "pipe", timeout: 30000, encoding: "utf-8",
      });
      if (out.includes("EnableEmbeddedAsarIntegrityValidation is Disabled")) {
        log("Already fully patched. Skipping.");
        return true;
      }
    } catch {}
  }

  // Backup
  const bakPath = info.asarPath + ".bak";
  if (!existsSync(bakPath)) {
    execSync(`cp "${info.asarPath}" "${bakPath}"`);
    log("Backup created: app.asar.bak");
  }

  let patched = data;

  // Patch 1: Ro()
  const roResult = patchRo(patched);
  if (roResult.patched && !roResult.alreadyPatched) {
    patched = roResult.data;
    log("✓ Patched Ro() — all model names valid");
  } else if (roResult.alreadyPatched) {
    log("✓ Ro() already patched");
  } else {
    log("✗ Ro() patch failed (pattern not found)");
  }

  // Patch 2: tr()
  const trResult = patchTr(patched);
  if (trResult.patched && !trResult.alreadyPatched) {
    patched = trResult.data;
    log("✓ Patched tr() — MSIX check bypassed");
  } else if (trResult.alreadyPatched) {
    log("✓ tr() already patched");
  } else {
    log("✗ tr() patch failed (pattern not found)");
  }

  // Patch 3: KXt()
  const kxtResult = patchKXt(patched);
  if (kxtResult.patched && !kxtResult.alreadyPatched) {
    patched = kxtResult.data;
    log("✓ Patched KXt() — Cowork checks bypassed");
  } else if (kxtResult.alreadyPatched) {
    log("✓ KXt() already patched");
  } else {
    log("✗ KXt() patch failed (pattern not found)");
  }

  // Write patched asar
  writeFileSync(info.asarPath, patched);
  log("✓ Patched app.asar written");

  // Patch 4: Disable fuse
  if (disableFuse(info.exePath)) {
    log("✓ ASAR integrity fuse disabled");
  } else {
    log("✗ Fuse disable failed");
  }

  log("Done! All patches applied.");
  log("");
  log("To use with OmniRoute:");
  log("  1. Start the proxy: node claude-desktop-proxy.mjs");
  log("  2. Set Gateway URL to: http://localhost:20228");
  log("  3. Set API Key to: omniroute");
  return true;
}

if (WATCH) {
  log("Watch mode — checking every 5 minutes for updates...");
  let lastVersion = null;

  function check() {
    const info = findClaudeExe();
    if (info && info.version !== lastVersion) {
      if (lastVersion !== null) log(`Claude Desktop updated to ${info.version} — re-patching...`);
      lastVersion = info.version;
      patchAll();
    }
  }

  check();
  setInterval(check, CHECK_INTERVAL);
} else {
  patchAll();
}
