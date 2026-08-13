#!/usr/bin/env node
// import-cookies.mjs <cdp-base-url> <cookie-json-file> [more...]
// Pushes cookie exports (Cookie Pusher format) into a running Chromium via
// Chrome DevTools Protocol using Node's native WebSocket client (Node >= 22).
// Cookie format accepted: array of {name, value, domain, path, expirationDate,
// httpOnly, secure, sameSite} — exactly what the Cookie Pusher extension reads.

import { readFile } from 'node:fs/promises';

const [cdpBase, ...files] = process.argv.slice(2);
if (!cdpBase || files.length === 0) {
  console.error('usage: import-cookies.mjs <cdp-base-url> <cookie-json> [more...]');
  process.exit(1);
}
if (typeof WebSocket === 'undefined') {
  console.error('Native WebSocket unavailable - run with Node >= 22, or install: npm i -g chrome-remote-interface');
  process.exit(1);
}

// grab the first page target's websocket URL
const targets = await (await fetch(`${cdpBase}/json`)).json();
const page = targets.find((t) => t.type === 'page') || targets[0];
if (!page?.webSocketDebuggerUrl) {
  console.error('No CDP page target found - is Chromium running with --remote-debugging-port?');
  process.exit(1);
}

const ws = new WebSocket(page.webSocketDebuggerUrl);
let seq = 0;
const pending = new Map();
const send = (method, params = {}) =>
  new Promise((resolve, reject) => {
    const id = ++seq;
    pending.set(id, { resolve, reject });
    ws.send(JSON.stringify({ id, method, params }));
  });

await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
ws.onmessage = (ev) => {
  const msg = JSON.parse(ev.data);
  if (msg.id && pending.has(msg.id)) {
    const { resolve, reject } = pending.get(msg.id);
    pending.delete(msg.id);
    msg.error ? reject(new Error(msg.error.message)) : resolve(msg.result);
  }
};

await send('Network.enable');

let total = 0;
for (const file of files) {
  const cookies = JSON.parse(await readFile(file, 'utf8'));
  if (!Array.isArray(cookies)) {
    console.error(`skip ${file}: not an array of cookies`);
    continue;
  }
  for (const c of cookies) {
    if (!c?.name || !c?.domain) continue;
    const expiry = c.expirationDate ? Math.floor(c.expirationDate) : undefined;
    const sameSite = { 'Lax': 'Lax', 'Strict': 'Strict', 'None': 'None' }[c.sameSite] || 'Lax';
    await send('Network.setCookie', {
      name: c.name,
      value: c.value ?? '',
      domain: c.domain,
      path: c.path ?? '/',
      httpOnly: !!c.httpOnly,
      secure: !!c.secure,
      sameSite,
      ...(expiry ? { expires: expiry } : {}),
    }).catch(() => {});
    total++;
  }
  console.log(`imported ${cookies.length} cookies from ${file}`);
}
console.log(`done - ${total} cookies set into the profile`);
ws.close();
process.exit(0);
