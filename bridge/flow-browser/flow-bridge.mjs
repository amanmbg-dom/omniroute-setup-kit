// flow-bridge.mjs — Google Flow via real browser automation, exposed as an
// OpenAI-compatible /v1/images/generations endpoint for OmniRoute.
//
//   POST /v1/images/generations  { "model": "flowui/nano-banana-2", "prompt": "...", "size": "1536x1024" }
//   -> 200 { "data": [{ "b64_json": "..." }] }
//
// How it works:
//   1. Launches a DEDICATED Chrome profile (~/.flow-browser-profile) with a CDP
//      port, so it never touches your normal browsing profile. A visible window
//      opens; you sign in to your Google account ONCE.
//   2. Connects via Playwright CDP and drives the REAL Google Flow web app
//      (labs.google/fx/tools/flow): create/open project -> type prompt -> click
//      Generate -> poll the DOM for the image UUID -> download via the
//      authenticated session.
//   3. Returns the PNG as base64 to the caller (OmniRoute / Claude Code).
//
// This reuses the automation engine from google-flow-browser-mcp (see README),
// so no cookies, no tokens, no captcha extraction — your own signed-in session.

import { spawn } from 'node:child_process';
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

import { get } from './src/utils/config.js';
import {
  setBrowser, setContext, setPage, setConnected,
} from './src/browser/connect.js';
import { handleGenerateImage } from './src/tools/generate-image.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const PORT = parseInt(process.env.FLOW_BRIDGE_PORT || '20134', 10);
const CDP_PORT = parseInt(get('cdpPort', 9222), 10);
const HEADLESS = process.env.FLOW_HEADLESS === '1' || get('headless', false);
const CHROME_PATH = process.env.CHROME_PATH
  || get('chromePath')
  || 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const PROFILE_DIR = process.env.FLOW_PROFILE_DIR
  || path.join(os.homedir(), '.flow-browser-profile');
const FLOW_URL = get('flowUrl', 'https://labs.google/fx/tools/flow');
const CDP_URL = `http://127.0.0.1:${CDP_PORT}`;

// flowui/<id> (as OmniRoute presents it) -> Flow display name (repo's imageModels keys)
const MODEL_ALIASES = {
  'nano-banana-2': 'Nano Banana 2',
  'nano-banana-pro': 'Nano Banana Pro',
  'imagen-4': 'Imagen 4',
};

const RATIOS = ['16:9', '4:3', '1:1', '3:4', '9:16'];

function sizeToRatio(size) {
  if (!size) return '1:1';
  const m = String(size).toLowerCase().match(/^(\d+)x(\d+)$/);
  if (!m) return '1:1';
  const r = Number(m[1]) / Number(m[2]);
  if (r > 1.5) return '16:9';
  if (r >= 1.2) return '4:3';
  if (r > 0.8) return '1:1';
  if (r >= 0.6) return '3:4';
  return '9:16';
}

function modelToDisplay(model) {
  const id = String(model || 'nano-banana-2').replace(/^flowui\//, '').toLowerCase();
  return MODEL_ALIASES[id] || 'Nano Banana 2';
}

let chromeProc = null;
let needsLogin = false;
let lastError = null;
let busy = false;
let currentStatus = { launched: false, connected: false, url: null };

function log(...args) {
  console.log(`[flow-bridge ${new Date().toISOString()}]`, ...args);
}

async function cdpReady() {
  try {
    const res = await fetch(`${CDP_URL}/json/version`);
    return res.ok;
  } catch {
    return false;
  }
}

async function ensureBrowser() {
  // Reuse an already-running instance on our CDP port if it answers.
  if (await cdpReady()) {
    try {
      const b = await chromium.connectOverCDP(CDP_URL);
      const ctx = b.contexts()[0];
      const pg = ctx.pages()[0] || (await ctx.newPage());
      setBrowser(b); setContext(ctx); setPage(pg); setConnected(true);
      currentStatus = { launched: true, connected: true, url: pg.url() };
      return pg;
    } catch (err) {
      log('CDP port answered but connect failed, relaunching', err.message);
    }
  }

  // Launch a dedicated Chrome instance (visible window, automation-flag-free).
  if (chromeProc) {
    try { chromeProc.kill(); } catch { /* ignore */ }
    chromeProc = null;
  }
  fs.mkdirSync(PROFILE_DIR, { recursive: true });

  const launchArgs = [
    `--remote-debugging-port=${CDP_PORT}`,
    '--remote-allow-origins=*',
    `--user-data-dir=${PROFILE_DIR}`,
    '--no-first-run',
    '--no-default-browser-check',
    '--disable-blink-features=AutomationControlled',
    '--disable-features=ChromeWhatsNewUI',
    '--window-size=1400,900',
    FLOW_URL,
  ];
  if (HEADLESS) launchArgs.unshift('--headless=new');

  log('launching Chrome', { chrome: CHROME_PATH, profile: PROFILE_DIR, cdp: CDP_PORT, headless: HEADLESS });
  chromeProc = spawn(CHROME_PATH, launchArgs, { stdio: 'ignore', detached: false });
  // Remember the Chrome PID so re-sign-in.cmd / cleanup can target EXACTLY this
  // instance (identified by our profile dir), never the user's other Chrome.
  try {
    fs.writeFileSync(path.join(os.homedir(), '.flow-browser-chrome.pid'), String(chromeProc.pid));
  } catch { /* non-fatal */ }

  let ok = false;
  for (let i = 0; i < 45; i++) {
    if (await cdpReady()) { ok = true; break; }
    await new Promise(r => setTimeout(r, 1000));
  }
  if (!ok) {
    lastError = 'Chrome did not open a CDP port in time';
    throw new Error(lastError);
  }

  const b = await chromium.connectOverCDP(CDP_URL);
  const ctx = b.contexts()[0] || (await b.newContext());
  // Collapse to ONE clean tab — session-restore leftovers confuse the automation.
  let pg = ctx.pages()[0] || (await ctx.newPage());
  for (let i = 1; i < ctx.pages().length; i++) {
    try { await ctx.pages()[i].close(); } catch { /* already closed */ }
  }
  setBrowser(b); setContext(ctx); setPage(pg); setConnected(true);
  currentStatus = { launched: true, connected: true, url: pg.url() };
  log('connected to Chrome via CDP', { url: pg.url() });
  try {
    await pg.goto(FLOW_URL, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await pg.waitForTimeout(3000);
  } catch (err) {
    log('goto flow failed', err.message);
  }
  pg = await enterFlowApp(pg) || pg;
  setPage(pg);
  return pg;
}

// Flow's public site (labs.google/fx/tools/flow) shows a marketing landing page
// with a "Create with Google Flow" button. Clicking it enters the real app — or
// opens the Google sign-in page if this profile isn't authenticated yet. The app
// may open in a NEW tab (target=_blank), so adopt it.
async function enterFlowApp(page) {
  try {
    const onLanding = await page.evaluate(() =>
      Array.from(document.querySelectorAll('button, a'))
        .some(el => (el.textContent || '').includes('Create with Google Flow') && el.offsetParent !== null)
    );
    if (!onLanding) return page;
    const clicked = await page.evaluate(() => {
      const btn = Array.from(document.querySelectorAll('button, a'))
        .find(el => (el.textContent || '').includes('Create with Google Flow') && el.offsetParent !== null);
      if (btn) { btn.click(); return true; }
      return false;
    });
    log('landing page detected — clicked Create with Google Flow', { clicked });
    if (!clicked) return page;
    await page.waitForTimeout(6000);
    const ctx = page.context();
    const appTab = ctx.pages().find(p => p !== page && !p.isClosed());
    if (appTab) {
      log('adopted app/sign-in tab', { url: appTab.url().slice(0, 120) });
      return appTab;
    }
  } catch (err) {
    log('enterFlowApp probe failed', err.message);
  }
  return page;
}

async function ensureSignedIn(page) {
  const pages = page.context().pages().filter(p => !p.isClosed());
  for (const p of pages) {
    const url = p.url();
    if (url.includes('accounts.google')) {
      needsLogin = true;
      log('sign-in required (Google accounts page open)', { url: url.slice(0, 80) });
      return false;
    }
  }
  const body = await page.evaluate(() => document.body ? document.body.innerText : '')
    .catch(() => '');
  const signedOut = /sign\s*in/i.test(body.slice(0, 2000))
    || body.includes('Choose an account');
  needsLogin = signedOut;
  return !signedOut;
}

async function generateImage(body) {
  const page = await ensureBrowser();
  await ensureSignedIn(page);
  if (needsLogin) {
    const err = new Error(
      'Google Flow needs a one-time sign-in. A Chrome window ("Flow Automation" profile) is open — '
      + `sign in to your Google account there (URL: ${FLOW_URL}), then retry.`
    );
    err.status = 503;
    throw err;
  }

  const displayModel = modelToDisplay(body.model);
  const ratio = sizeToRatio(body.size);
  const outputFolder = fs.mkdtempSync(path.join(os.tmpdir(), 'flowui-'));

  log('generating image', { model: displayModel, ratio, prompt: (body.prompt || '').slice(0, 80) });

  const result = await handleGenerateImage({
    prompt: body.prompt || '',
    model: displayModel,
    ratio,
    auto_confirm: true,
    quantity: body.n || 1,
    output_folder: outputFolder,
    project_name: 'omniroute-images',
    campaign: 'omniroute',
  });

  const files = (result.files || []).filter(f => fs.existsSync(f))
    .sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);
  if (files.length === 0) {
    const err = new Error(`Generation finished but no file was saved. Raw result: ${JSON.stringify(result).slice(0, 400)}`);
    err.status = 502;
    throw err;
  }

  // Honor `n`: return the newest n files (Flow typically generates 4 per run).
  // Default (no n): return everything, same as before.
  const count = typeof body.n === 'number' && body.n > 0 ? Math.min(body.n, files.length) : files.length;
  const data = files.slice(0, count).map(f => {
    const buf = fs.readFileSync(f);
    const name = path.basename(f);
    return { b64_json: buf.toString('base64'), filename: name };
  });
  try { fs.rmSync(outputFolder, { recursive: true, force: true }); } catch { /* keep */ }

  return { created: Math.floor(Date.now() / 1000), data };
}

function send(res, status, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(status, {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(body),
    'Access-Control-Allow-Origin': '*',
  });
  res.end(body);
}

const server = http.createServer(async (req, res) => {
  try {
    if (req.method === 'GET' && req.url === '/health') {
      return send(res, 200, {
        status: 'ok',
        launched: currentStatus.launched,
        connected: currentStatus.connected,
        needsLogin,
        busy,
        url: currentStatus.url,
        lastError,
        profileDir: PROFILE_DIR,
      });
    }
    if (req.method === 'GET' && req.url === '/v1/models') {
      return send(res, 200, {
        object: 'list',
        data: Object.keys(MODEL_ALIASES).map(id => ({
          id: `flowui/${id}`,
          object: 'model',
          created: 0,
          owned_by: 'google-flow',
        })),
      });
    }
    if (req.method === 'POST' && req.url === '/v1/images/generations') {
      if (busy) return send(res, 429, { error: { message: 'A generation is already running; try again shortly.' } });
      let body = {};
      try { body = JSON.parse(await readBody(req)); } catch { /* empty body */ }
      if (!body.prompt) return send(res, 400, { error: { message: 'Missing required field: prompt' } });

      busy = true;
      try {
        const timeout = new Promise((_, rej) =>
          setTimeout(() => rej(new Error('Generation timed out after 240s — the Flow UI may need manual attention in the Chrome window.')), 240000));
        const result = await Promise.race([generateImage(body), timeout]);
        return send(res, 200, result);
      } catch (err) {
        lastError = err.message;
        log('generation failed', err.message);
        return send(res, err.status || 502, { error: { message: err.message } });
      } finally {
        busy = false;
      }
    }
    return send(res, 404, { error: { message: `Not found: ${req.method} ${req.url}` } });
  } catch (err) {
    lastError = err.message;
    return send(res, 500, { error: { message: err.message } });
  }
});

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', c => chunks.push(c));
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

server.listen(PORT, '127.0.0.1', () => {
  log(`flowui bridge listening on http://127.0.0.1:${PORT}`);
  log(`model: flowui/nano-banana-2  (dedicated Chrome profile: ${PROFILE_DIR})`);
  log('first generation opens a Chrome window — sign in to Google once, then requests will flow.');
});
