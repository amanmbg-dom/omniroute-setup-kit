#!/usr/bin/env node
// site-images.mjs — background image pipeline for the single-page-site skill.
//
// Generates every image slot for a one-pager through the flowui bridge
// (Google Flow / Nano Banana 2, your real signed-in Chrome session) while the
// agent builds the rest of the site in parallel, then records results in a
// manifest the agent reads when assembling the final HTML with HOSTED links.
//
// Usage:
//   node site-images.mjs site-images.json --out images [--upload] [--base-url https://...] [--bridge http://127.0.0.1:20134]
//
// site-images.json:
//   {
//     "slots": [
//       { "key": "hero",  "prompt": "Professional photograph of ...", "size": "1792x1024" },
//       { "key": "about", "prompt": "...", "size": "1024x1024" }
//     ]
//   }
//
// Hosting (how the "url" per slot is decided):
//   --upload     upload the chosen image to catbox.moe (free, anonymous,
//                direct hotlink URLs) -> real links immediately
//   --base-url   prefix for the URL (e.g. the client's hosting:
//                https://client.com/images/) -> url = base + filename
//   neither      url = "/images/<key>-1.jpg" relative path -> the client
//                uploads the images/ folder to their host and it just works
//
// Manifest (written to <out>/images-manifest.json after EACH slot, so the
// agent can poll progress): { "done": bool, "slots": { "<key>": {
//   "status": "ok"|"error", "file": "...", "url": "...",
//   "candidates": ["..."], "error": "..." } } }

import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function parseArgs(argv) {
  const out = { slotsFile: argv[2], outDir: 'images', upload: false, baseUrl: '', bridge: 'http://127.0.0.1:20134' };
  for (let i = 3; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--upload') out.upload = true;
    else if (a === '--out') out.outDir = argv[++i];
    else if (a === '--base-url') out.baseUrl = String(argv[++i]).replace(/\/+$/, '') + '/';
    else if (a === '--bridge') out.bridge = String(argv[++i]).replace(/\/+$/, '');
  }
  return out;
}

function log(...args) {
  console.log(`[site-images ${new Date().toISOString()}]`, ...args);
}

async function bridgeHealth(bridge) {
  try {
    const res = await fetch(`${bridge}/health`, { signal: AbortSignal.timeout(5000) });
    return res.ok ? await res.json() : null;
  } catch {
    return null;
  }
}

async function waitForBridge(bridge, maxWaitMs = 180000) {
  if (await bridgeHealth(bridge)) return true;
  log('bridge not up — launching start-flow-browser.cmd (headless)');
  const launcher = process.env.FLOWUI_LAUNCHER || path.join(__dirname, '..', '..', 'bridge', 'flow-browser', 'start-flow-browser.cmd');
  try {
    spawn('cmd.exe', ['/c', `"${launcher}"`], { detached: true, stdio: 'ignore', windowsHide: true }).unref();
  } catch { /* ignore */ }
  const start = Date.now();
  while (Date.now() - start < maxWaitMs) {
    await new Promise(r => setTimeout(r, 3000));
    if (await bridgeHealth(bridge)) return true;
  }
  return false;
}

async function generateSlot(bridge, slot) {
  const res = await fetch(`${bridge}/v1/images/generations`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: 'flowui/nano-banana-2', prompt: slot.prompt, size: slot.size || '1024x1024', n: 4 }),
    signal: AbortSignal.timeout(300000),
  });
  const payload = await res.json().catch(() => ({}));
  if (!res.ok) {
    const msg = payload?.error?.message || `HTTP ${res.status}`;
    const err = new Error(msg);
    err.reSignIn = /sign-?in/i.test(msg);
    throw err;
  }
  const items = Array.isArray(payload?.data) ? payload.data : [];
  if (items.length === 0) throw new Error('No images returned');
  return items; // newest-first (bridge sorts by mtime desc)
}

async function uploadCatbox(file) {
  // catbox.moe: free, anonymous, direct hotlink URLs, no account needed.
  const buf = fs.readFileSync(file);
  const fd = new FormData();
  fd.append('reqtype', 'fileupload');
  fd.append('fileToUpload', new Blob([buf]), path.basename(file));
  try {
    const res = await fetch('https://catbox.moe/user/api.php', { method: 'POST', body: fd, signal: AbortSignal.timeout(60000) });
    if (!res.ok) throw new Error(`catbox HTTP ${res.status}`);
    const url = (await res.text()).trim();
    if (!/^https?:\/\//.test(url)) throw new Error(`catbox returned: ${url.slice(0, 80)}`);
    return url;
  } catch (err) {
    // fallback: curl multipart
    return new Promise((resolve, reject) => {
      const curl = spawn('curl', ['-s', '-F', 'reqtype=fileupload', '-F', `fileToUpload=@${file}`, 'https://catbox.moe/user/api.php']);
      let out = '';
      curl.stdout.on('data', d => (out += d));
      curl.on('close', code => {
        const url = out.trim();
        if (code === 0 && /^https?:\/\//.test(url)) resolve(url);
        else reject(new Error('catbox upload failed'));
      });
      curl.on('error', reject);
    });
  }
}

async function main() {
  const cfg = parseArgs(process.argv);
  if (!cfg.slotsFile) {
    log('usage: node site-images.mjs site-images.json --out images [--upload] [--base-url https://...]');
    process.exit(2);
  }
  const spec = JSON.parse(fs.readFileSync(cfg.slotsFile, 'utf8'));
  const slots = Array.isArray(spec.slots) ? spec.slots : [];
  if (slots.length === 0) { log('no slots found in spec'); process.exit(2); }

  fs.mkdirSync(cfg.outDir, { recursive: true });
  const manifestPath = path.join(cfg.outDir, 'images-manifest.json');
  const state = { done: false, baseUrl: cfg.baseUrl || '', upload: cfg.upload, slots: {} };

  const writeState = () => {
    try { fs.writeFileSync(manifestPath, JSON.stringify(state, null, 2)); } catch { /* keep going */ }
  };

  if (!(await waitForBridge(cfg.bridge))) {
    for (const s of slots) state.slots[s.key] = { status: 'error', error: 'flowui bridge did not start. Run bridge\\flow-browser\\start-flow-browser.cmd, or re-sign-in.cmd if the session expired.' };
    state.done = true;
    writeState();
    log('bridge unavailable — manifest written with errors');
    process.exit(1);
  }

  for (const slot of slots) {
    const key = slot.key;
    const entry = { status: 'pending' };
    state.slots[key] = entry;
    log(`[${key}] generating (${slot.size || '1024x1024'})...`);
    try {
      const items = await generateSlot(cfg.bridge, slot);
      const files = [];
      for (let i = 0; i < items.length; i++) {
        const raw = items[i].b64_json || '';
        const ext = String(items[i].filename || '').endsWith('.png') ? 'png' : 'jpg';
        const f = path.join(cfg.outDir, `${key}-${i + 1}.${ext}`);
        fs.writeFileSync(f, Buffer.from(raw, 'base64'));
        files.push(f);
      }
      const chosen = files[0]; // newest candidate
      entry.status = 'ok';
      entry.file = chosen.replace(/\\/g, '/');
      entry.candidates = files.map(f => f.replace(/\\/g, '/'));
      if (cfg.upload) {
        try {
          entry.url = await uploadCatbox(chosen);
          log(`[${key}] uploaded -> ${entry.url}`);
        } catch {
          entry.url = `/images/${path.basename(chosen)}`;
          entry.hostNote = 'catbox upload failed — using relative /images/ path (upload the folder to the client host)';
        }
      } else if (cfg.baseUrl) {
        entry.url = cfg.baseUrl + path.basename(chosen);
      } else {
        entry.url = `/images/${path.basename(chosen)}`;
      }
      log(`[${key}] ok: ${entry.url}`);
    } catch (err) {
      entry.status = 'error';
      entry.error = err.message;
      if (err.reSignIn) entry.error += ' (run bridge\\flow-browser\\re-sign-in.cmd to sign in again)';
      log(`[${key}] ERROR: ${entry.error}`);
    }
    writeState();
  }

  state.done = true;
  writeState();
  const okCount = Object.values(state.slots).filter(s => s.status === 'ok').length;
  log(`done: ${okCount}/${slots.length} slots ok — manifest at ${manifestPath}`);
  process.exit(okCount > 0 ? 0 : 1);
}

main().catch(err => {
  log('fatal:', err.message);
  process.exit(1);
});
