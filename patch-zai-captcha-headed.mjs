#!/usr/bin/env node
// patch-zai-captcha-headed.mjs — keep the OmniRoute z.ai captcha worker's
// Chrome VISIBLE, because zai's anti-bot REQUIRES a real browser.
//
// History: the gateway's ZAI_CAPTCHA_WORKER
// (dist/.build/next/server/zai-captcha-worker.js) launches a Playwright Chrome
// to solve z.ai's Aliyun "traceless captcha" whenever the account is challenged
// (HTTP 405 block page). We previously patched it to `headless:!0` to make it
// invisible — but Aliyun's anti-bot detects headless Chrome (verifyResult F001)
// and refuses every solve, so the 405 challenge could never clear and zai-web
// stayed broken (173 worker failures the day the patch was applied, vs 2 in the
// 5 days before). zai is the ONE component that cannot run headless: its
// captcha solver needs a real browser. The window appears only when z.ai issues
// a challenge (a few seconds), never otherwise.
//
// This script ensures the worker is HEADED (reverts the same-length byte patch
// `headless:!0` -> `headless: false`), idempotently, and re-applies it after
// every gateway npm update (wired into fix-model-cache.ps1 / FixModelCache.cmd).
//
// Usage: node patch-zai-captcha-headed.mjs [path-to-worker.js]
//   exit 0 = headed (already or just reverted)

import fs from "node:fs";

const CANDIDATES = [
  process.argv[2],
  process.env.APPDATA + "\\npm\\node_modules\\omniroute\\dist\\.build\\next\\server\\zai-captcha-worker.js",
  process.env.APPDATA + "/npm/node_modules/omniroute/dist/.build/next/server/zai-captcha-worker.js",
].filter(Boolean);

const file = CANDIDATES.find((p) => fs.existsSync(p));
if (!file) {
  console.log("[zai-headed] worker file not found - skipping (gateway not installed?)");
  process.exit(0);
}

const buf = fs.readFileSync(file);
const PATCHED = "headless:!0" + " ".repeat(15 - "headless:!0".length); // same length as ORIG
const ORIG = "headless: false";

if (buf.includes(Buffer.from(ORIG, "utf8"))) {
  console.log(`[zai-headed] worker already headed (${file})`);
  process.exit(0);
}

const start = buf.indexOf(Buffer.from(PATCHED, "utf8"));
if (start === -1) {
  console.log(`[zai-headed] neither headed nor patched anchor found in ${file} - this build needs re-review (exit 3)`);
  process.exit(3);
}
Buffer.from(ORIG, "utf8").copy(buf, start);
fs.writeFileSync(file, buf);
console.log(`[zai-headed] reverted to headed Chrome (${file}) - zai captcha requires a real browser`);
process.exit(0);
