// flowui-mcp.mjs — Model Context Protocol (stdio) server for Google Flow images.
//
// Exposes EXACTLY ONE generation tool to Claude Code / any MCP client:
//
//   generate_image  { prompt, size?, n?, model? }  ->  image content block(s)
//   image_status    {}                              ->  bridge health
//
// All generation funnels through the same local flowui bridge
// (http://127.0.0.1:20134) as every other caller, so the image engine, model
// (Nano Banana 2 via your real Google Flow session), ratio mapping and prompt
// discipline are IDENTICAL no matter who asks. This is what keeps quality
// consistent.
//
// Zero dependencies: implements the MCP stdio protocol (newline-delimited
// JSON-RPC 2.0) directly. The bridge auto-starts if it is down.
//
// Register with Claude Code once:
//   claude mcp add -s user flowui -- node "C:\path\to\flowui-mcp.mjs"
// (setup.ps1 does this automatically on new machines.)

import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import readline from 'node:readline';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const BRIDGE_URL = process.env.FLOWUI_BASE_URL || 'http://127.0.0.1:20134';
const BRIDGE_TIMEOUT_MS = parseInt(process.env.FLOWUI_TIMEOUT_MS || '300000', 10);
const LAUNCHER = path.join(__dirname, 'start-flow-browser.cmd');
const OUT_DIR = path.join(os.homedir(), 'flowui-output');

const SIZES = {
  '1024x1024': '1:1',
  '1792x1024': '16:9',
  '1536x1024': '4:3',
  '1024x1536': '3:4',
  '1024x1792': '9:16',
};

const PROTOCOL_VERSION = '2024-11-05';

function log(...args) {
  // Protocol traffic goes to stdout; ALL logging goes to stderr.
  process.stderr.write(`[flowui-mcp ${new Date().toISOString()}] ${args.join(' ')}\n`);
}

function send(msg) {
  process.stdout.write(JSON.stringify(msg) + '\n');
}

function sendResult(id, result) {
  send({ jsonrpc: '2.0', id, result });
}

function sendError(id, code, message) {
  send({ jsonrpc: '2.0', id, error: { code, message } });
}

async function bridgeHealth() {
  try {
    const res = await fetch(`${BRIDGE_URL}/health`, { signal: AbortSignal.timeout(5000) });
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  }
}

// Start the bridge launcher detached and wait for it to answer /health.
// The bridge stays up after this server exits (detached process group).
async function ensureBridge(maxWaitMs = 180000) {
  const health = await bridgeHealth();
  if (health) return health;

  log('bridge is down — launching start-flow-browser.cmd (headless)');
  try {
    spawn('cmd.exe', ['/c', `"${LAUNCHER}"`], {
      detached: true,
      stdio: 'ignore',
      windowsHide: true,
    }).unref();
  } catch (err) {
    log('failed to spawn launcher', err.message);
    return null;
  }

  const started = Date.now();
  while (Date.now() - started < maxWaitMs) {
    await new Promise(r => setTimeout(r, 3000));
    const h = await bridgeHealth();
    if (h) {
      log('bridge came up', { launched: h.launched, needsLogin: h.needsLogin });
      return h;
    }
    if ((Date.now() - started) % 30000 < 3000) {
      log('still waiting for bridge to come up...');
    }
  }
  return null;
}

async function callGenerateImage(args = {}) {
  const prompt = String(args.prompt || '').trim();
  if (!prompt) {
    return { isError: true, content: [{ type: 'text', text: 'generate_image requires a non-empty "prompt".' }] };
  }
  const size = args.size && SIZES[String(args.size)] ? String(args.size) : '1024x1024';
  const n = Math.min(Math.max(parseInt(args.n || '1', 10) || 1, 1), 4);
  const model = String(args.model || 'flowui/nano-banana-2');

  const health = await ensureBridge();
  if (!health) {
    return {
      isError: true,
      content: [{ type: 'text', text: `The flowui image bridge did not start. Launch it manually with:\n  bridge\\flow-browser\\start-flow-browser.cmd\nThen retry.` }],
    };
  }
  if (health.needsLogin) {
    return {
      isError: true,
      content: [{ type: 'text', text: `Google Flow needs a (re-)sign-in. Run:\n  bridge\\flow-browser\\re-sign-in.cmd\nSign in to Google in the Chrome window that opens, then retry.` }],
    };
  }

  let res;
  try {
    res = await fetch(`${BRIDGE_URL}/v1/images/generations`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ model, prompt, size, n }),
      signal: AbortSignal.timeout(BRIDGE_TIMEOUT_MS),
    });
  } catch (err) {
    return { isError: true, content: [{ type: 'text', text: `Image request failed (bridge unreachable): ${err.message}` }] };
  }

  const payload = await res.json().catch(() => ({}));
  if (!res.ok) {
    const msg = payload?.error?.message || `HTTP ${res.status}`;
    if (/sign-?in/i.test(msg)) {
      return {
        isError: true,
        content: [{ type: 'text', text: `Google Flow needs a (re-)sign-in. Run:\n  bridge\\flow-browser\\re-sign-in.cmd\nSign in, then retry. (bridge said: ${msg})` }],
      };
    }
    return { isError: true, content: [{ type: 'text', text: `Image generation failed: ${msg}` }] };
  }

  const items = Array.isArray(payload?.data) ? payload.data : [];
  if (items.length === 0) {
    return { isError: true, content: [{ type: 'text', text: 'Image generation returned no images.' }] };
  }

  // Persist to ~/flowui-output/<stamp>-<slug>/ so the user has real files.
  const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const slug = prompt.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 40) || 'image';
  const outDir = path.join(OUT_DIR, `${stamp}-${slug}`);
  fs.mkdirSync(outDir, { recursive: true });

  const content = [];
  const saved = [];
  items.forEach((item, i) => {
    const raw = item.b64_json || '';
    const ext = /^data:image\/png/i.test(raw) ? 'png' : (String(item.filename || '').endsWith('.png') ? 'png' : 'jpg');
    const file = path.join(outDir, `image-${i + 1}.${ext}`);
    try {
      fs.writeFileSync(file, Buffer.from(raw, 'base64'));
      saved.push(file);
    } catch (err) {
      log('failed to save image', file, err.message);
    }
  });

  if (saved.length === 0) {
    return { isError: true, content: [{ type: 'text', text: 'Generated images could not be saved to disk.' }] };
  }

  // First image as a viewable content block (clients render these inline).
  const first = saved[0];
  const mime = first.endsWith('.png') ? 'image/png' : 'image/jpeg';
  content.push({
    type: 'image',
    data: fs.readFileSync(first).toString('base64'),
    mimeType: mime,
  });

  const lines = [
    `Generated ${saved.length} image(s) with ${model} (size ${size}).`,
    'Files:',
    ...saved.map(f => `  ${f}`),
    'Prompt: ' + prompt,
  ];
  content.push({ type: 'text', text: lines.join('\n') });

  return { isError: false, content };
}

const TOOLS = [
  {
    name: 'generate_image',
    description:
      'Generate one or more AI images through the local Google Flow engine (Nano Banana 2, real signed-in session). ' +
      'Use this for EVERY image need — website imagery, gallery photos, product shots, PDF covers, social graphics, ' +
      'illustrations. Consistent quality because the engine and prompt pipeline are fixed. ' +
      'Pass a detailed prompt: subject, setting, composition, lighting, palette, style. ' +
      'Sizes: 1024x1024 (square), 1792x1024 (wide/hero), 1536x1024 (landscape), 1024x1536 (portrait), 1024x1792 (tall).',
    inputSchema: {
      type: 'object',
      properties: {
        prompt: { type: 'string', description: 'Detailed image description (subject, setting, composition, lighting, palette, style).' },
        size: { type: 'string', enum: Object.keys(SIZES), default: '1024x1024', description: 'Output aspect: square / wide / landscape / portrait / tall.' },
        n: { type: 'integer', minimum: 1, maximum: 4, default: 1, description: 'How many candidate images to generate (pick the best yourself).' },
        model: { type: 'string', default: 'flowui/nano-banana-2', description: 'Engine model id (default flowui/nano-banana-2).' },
      },
      required: ['prompt'],
    },
  },
  {
    name: 'image_status',
    description: 'Check whether the local Google Flow image bridge is running and signed in.',
    inputSchema: { type: 'object', properties: {} },
  },
];

async function handleToolsCall(params) {
  const name = params?.name;
  const args = params?.arguments || {};

  if (name === 'generate_image') {
    return callGenerateImage(args);
  }
  if (name === 'image_status') {
    const health = await bridgeHealth();
    if (!health) {
      return { isError: false, content: [{ type: 'text', text: 'flowui bridge is DOWN (not running on 127.0.0.1:20134). Start it with bridge\\flow-browser\\start-flow-browser.cmd' }] };
    }
    const status = `flowui bridge: ${health.status} | Chrome launched: ${health.launched} | connected: ${health.connected} | needs sign-in: ${health.needsLogin} | busy: ${health.busy} | ${health.url || ''}`;
    return { isError: false, content: [{ type: 'text', text: status }] };
  }

  return { isError: true, content: [{ type: 'text', text: `Unknown tool: ${name}` }] };
}

// ---- MCP stdio transport (newline-delimited JSON-RPC 2.0) ----
const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });

rl.on('line', async line => {
  const raw = line.trim();
  if (!raw) return;

  let msg;
  try {
    msg = JSON.parse(raw);
  } catch {
    log('dropped malformed message');
    return;
  }

  if (msg.method === 'initialize') {
    sendResult(msg.id, {
      protocolVersion: PROTOCOL_VERSION,
      capabilities: { tools: { listChanged: false } },
      serverInfo: { name: 'flowui-images', version: '1.0.0' },
    });
    return;
  }
  if (msg.method === 'notifications/initialized' || msg.method === 'notifications/cancelled') {
    return; // notification — no reply
  }
  if (msg.method === 'ping') {
    sendResult(msg.id, {});
    return;
  }
  if (msg.method === 'tools/list') {
    sendResult(msg.id, { tools: TOOLS });
    return;
  }
  if (msg.method === 'tools/call') {
    try {
      const result = await handleToolsCall(msg.params);
      sendResult(msg.id, result);
    } catch (err) {
      sendError(msg.id, -32603, `Internal error: ${err.message}`);
    }
    return;
  }
  if (msg.id !== undefined) {
    sendError(msg.id, -32601, `Method not found: ${msg.method}`);
  }
});

process.on('uncaughtException', err => {
  log('uncaught exception', err.message);
});
