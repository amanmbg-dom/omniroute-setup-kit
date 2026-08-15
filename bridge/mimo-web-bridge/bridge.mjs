#!/usr/bin/env node
// mimo-web-bridge.mjs — OpenAI-compatible local bridge for Xiaomi MiMo AI Studio
// (aistudio.xiaomimimo.com) web chat, cookie-authenticated.
//
// Reverse-engineered from the aistudio.xiaomimimo.com web app (webpack build):
//   - chat endpoint : POST /open-apis/bot/chat  (production; /fastchat prefix only in ultra builds)
//   - auth          : `session` cookie (+ optional `xiaomichatbot_ph` cookie echoed as a
//                     query param of the same name — read from document.cookie)
//   - headers       : Accept-Language, x-timeZone, Content-Type (no Authorization header)
//   - request       : { msgId, conversationId, query, isEditedQuery, previousDialogueId?,
//                       sceneType?, params?, modelConfig: { model, enableThinking,
//                       webSearchStatus, temperature?, topP? }, multiMedias: [] }
//   - response      : named SSE events — `message` (JSON {content: <delta>}), `finish`,
//                     `usage`, `dialogId`, `error`, `web_search`, `doc`, `tip_ratio`
//   - thinking      : deltas arrive wrapped in <think>\0 ... </think>\0 markers
//
// Serves (OpenAI format, consumed by OmniRoute's openai-compatible provider nodes):
//   GET  /v1/models           — model list from /open-apis/bot/config (cached 1h)
//   POST /v1/chat/completions — translated chat, SSE streamed back
//   POST /v1/cookies          — Cookie Pusher endpoint: store session cookies
//   GET  /healthz             — liveness probe
//
// Auth: reads ~/.omniroute/mimo-cookies.json on every request (cookie pusher writes it).
// Zero runtime dependencies (node:http + global fetch).
//
// Run:  node bridge.mjs        (or start-bridge.cmd)

import http from "node:http";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import crypto from "node:crypto";

const PORT = parseInt(process.env.MIMO_BRIDGE_PORT || "20135", 10);
const HOST = process.env.MIMO_BRIDGE_HOST || "127.0.0.1";
const UPSTREAM = process.env.MIMO_UPSTREAM || "https://aistudio.xiaomimimo.com";
const CHAT_PATH = "/open-apis/bot/chat";
const CONFIG_PATH = "/open-apis/bot/config";
const DATA_DIR = process.env.DATA_DIR || path.join(os.homedir(), ".omniroute");
const COOKIE_FILE = path.join(DATA_DIR, "mimo-cookies.json");
const LOG_FILE = path.join(DATA_DIR, "mimo-web-bridge.log");
const TOKEN_PARAM = "xiaomichatbot_ph";
const THINK_OPEN = "<think>\u0000";
const THINK_CLOSE = "</think>\u0000";
const MODEL_CACHE_MS = 60 * 60 * 1000;
const MAX_QUERY = 40000;

const uuid = () => crypto.randomUUID();

function log(...args) {
  const line = `[${new Date().toISOString()}] ${args.join(" ")}`;
  try {
    fs.appendFileSync(LOG_FILE, line + "\n");
  } catch {}
  process.stdout.write(line + "\n");
}

// ---------------- helpers ----------------

function sendJson(res, status, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(status, {
    "Content-Type": "application/json",
    "Content-Length": Buffer.byteLength(body),
  });
  res.end(body);
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    let data = "";
    req.on("data", (c) => {
      data += c;
      if (data.length > 8e6) {
        reject(new Error("body too large"));
        req.destroy();
      }
    });
    req.on("end", () => {
      try {
        resolve(data ? JSON.parse(data) : {});
      } catch {
        reject(new Error("invalid JSON body"));
      }
    });
    req.on("error", reject);
  });
}

// ---------------- cookies ----------------

function loadCookies() {
  try {
    return JSON.parse(fs.readFileSync(COOKIE_FILE, "utf8"));
  } catch {
    return null;
  }
}

// Merge cookie-file cookies + anything passed as Authorization: Bearer <cookie header>
function pickCookies(fileCookies, auth) {
  const out = {};
  const add = (hdr) => {
    for (const part of String(hdr || "").split(";")) {
      const eq = part.indexOf("=");
      if (eq < 1) continue;
      const name = part.slice(0, eq).trim();
      const value = part.slice(eq + 1).trim();
      if (name) out[name] = value;
    }
  };
  if (fileCookies) {
    add(
      Object.entries(fileCookies)
        .filter(([k]) => k !== "syncedAt")
        .map(([k, v]) => `${k}=${v}`)
        .join("; ")
    );
  }
  if (auth) add(auth.replace(/^Bearer\s+/i, ""));
  return out;
}

function parseHeader(header) {
  const out = {};
  for (const part of String(header || "").split(";")) {
    const eq = part.indexOf("=");
    if (eq < 1) continue;
    const name = part.slice(0, eq).trim();
    const value = part.slice(eq + 1).trim();
    if (name) out[name] = value;
  }
  return out;
}

// ---------------- model config ----------------

let modelsCache = null;
let modelsCacheAt = 0;
let modelsPromise = null;

async function refreshModels(force) {
  if (modelsCache && !force && Date.now() - modelsCacheAt < MODEL_CACHE_MS) return modelsCache;
  if (!modelsPromise) {
    modelsPromise = (async () => {
      const res = await fetch(UPSTREAM + CONFIG_PATH, {
        headers: { "Accept-Language": "zh-CN" },
        signal: AbortSignal.timeout(20000),
      });
      if (!res.ok) throw new Error(`config ${res.status}`);
      const j = await res.json();
      const list = (j.data && j.data.modelConfigList) || [];
      if (!list.length) throw new Error("empty modelConfigList");
      modelsCache = list.map((m) => ({
        id: m.model,
        object: "model",
        owned_by: "xiaomimimo",
        created: 0,
        name: m.name,
        temperature: m.temperature,
        topP: m.topP,
        thinkingDefaultOn: !!m.thinkingDefaultOn,
        webSearchDefaultStatus: m.webSearchDefaultStatus,
      }));
      modelsCacheAt = Date.now();
      log(`models refreshed: ${modelsCache.length}`);
      return modelsCache;
    })();
  }
  try {
    return await modelsPromise;
  } finally {
    modelsPromise = null;
  }
}

// ---------------- SSE (wire-format of the MiMo stream) ----------------

function parseBlock(block) {
  let event = "message";
  let data = "";
  for (const raw of block.split(/\r?\n/)) {
    if (raw.startsWith("event:")) event = raw.slice(6).trim();
    else if (raw.startsWith("data:")) data += raw.slice(5).replace(/^\s/, "") + "\n";
  }
  return { event, data: data.trim() };
}

async function* iterateSSE(stream) {
  const reader = stream.getReader();
  const dec = new TextDecoder();
  let pending = "";
  for (;;) {
    const { value, done } = await reader.read();
    if (done) break;
    pending += dec.decode(value, { stream: true });
    let idx;
    while ((idx = pending.indexOf("\n\n")) !== -1) {
      const block = pending.slice(0, idx);
      pending = pending.slice(idx + 2);
      if (block.trim()) yield parseBlock(block);
    }
  }
  if (pending.trim()) yield parseBlock(pending);
}

// ---------------- thinking-marker splitter ----------------
// Upstream deltas carry thinking wrapped in <think>\0 ... </think>\0; markers may
// straddle chunk boundaries, so buffer with a marker-length margin (like the app).

function thinkSplitter() {
  let buf = "";
  let inThink = false;
  const M = Math.max(THINK_OPEN.length, THINK_CLOSE.length);
  return {
    push(delta) {
      buf += delta;
      const out = { content: "", reasoning: "" };
      const flush = (kind, text) => {
        if (!text) return;
        if (kind === "content") out.content += text;
        else out.reasoning += text;
      };
      for (;;) {
        if (!inThink) {
          const i = buf.indexOf(THINK_OPEN);
          if (i === -1) {
            if (buf.length > M) {
              flush("content", buf.slice(0, buf.length - M));
              buf = buf.slice(buf.length - M);
            }
            break;
          }
          flush("content", buf.slice(0, i));
          buf = buf.slice(i + THINK_OPEN.length);
          inThink = true;
        } else {
          const i = buf.indexOf(THINK_CLOSE);
          if (i === -1) {
            if (buf.length > M) {
              flush("reasoning", buf.slice(0, buf.length - M));
              buf = buf.slice(buf.length - M);
            }
            break;
          }
          flush("reasoning", buf.slice(0, i));
          buf = buf.slice(i + THINK_CLOSE.length);
          inThink = false;
        }
      }
      return out;
    },
    flush() {
      const out = { content: "", reasoning: "" };
      if (buf) {
        if (inThink) out.reasoning = buf;
        else out.content = buf;
        buf = "";
      }
      return out;
    },
  };
}

function mapUsage(usageObj) {
  if (!usageObj || typeof usageObj !== "object") return undefined;
  const u = usageObj.usage && typeof usageObj.usage === "object" ? usageObj.usage : usageObj;
  const n = u.nativeUsage && typeof u.nativeUsage === "object" ? u.nativeUsage : null;
  const prompt = u.prompt_tokens ?? (n && n.prompt_tokens) ?? undefined;
  const completion = u.completion_tokens ?? (n && n.completion_tokens) ?? undefined;
  if (prompt === undefined && completion === undefined) return undefined;
  return {
    prompt_tokens: prompt ?? 0,
    completion_tokens: completion ?? 0,
    total_tokens: (prompt ?? 0) + (completion ?? 0),
  };
}

// ---------------- chat ----------------

async function handleChat(req, res, body) {
  const model = typeof body.model === "string" && body.model ? body.model : "mimo-v2.5";
  const messages = Array.isArray(body.messages) ? body.messages : [];
  const stream = body.stream === true || body.stream === "true";

  const textOf = (m) => {
    if (typeof m.content === "string") return m.content;
    if (Array.isArray(m.content)) {
      return m.content
        .filter((p) => p && p.type === "text")
        .map((p) => p.text || "")
        .join("\n");
    }
    return "";
  };

  const lastUser = [...messages].reverse().find((m) => m.role === "user");
  if (!lastUser) {
    return sendJson(res, 400, { error: { message: "no user message", type: "invalid_request_error" } });
  }

  // Single message -> raw text; history -> transcript (the web API only takes the
  // latest query plus a server-side previousDialogueId we cannot reuse statelessly).
  const tail = messages.slice(-16);
  let query;
  if (tail.length <= 1) {
    query = textOf(lastUser);
  } else {
    query = tail
      .map((m) => `${m.role === "user" ? "User" : "Assistant"}: ${textOf(m)}`)
      .filter((s) => s.trim())
      .join("\n\n");
  }
  query = (query || "").trim();
  if (!query) {
    return sendJson(res, 400, { error: { message: "empty query", type: "invalid_request_error" } });
  }
  if (query.length > MAX_QUERY) query = query.slice(-MAX_QUERY);

  // ---- auth ----
  const cookies = pickCookies(loadCookies(), req.headers.authorization);
  const session = cookies.session || cookies.SESSION || "";
  const ph = cookies[TOKEN_PARAM] || "";
  if (!session) {
    return sendJson(res, 401, {
      error: {
        message:
          "No MiMo session cookie. Sign in at aistudio.xiaomimimo.com, then Cookie Pusher -> Grab & push sessions.",
        type: "authentication_error",
      },
    });
  }
  const cookieHeader = Object.entries(cookies)
    .map(([k, v]) => `${k}=${v}`)
    .join("; ");

  // ---- model config ----
  let cfg = null;
  try {
    cfg = (await refreshModels()).find((m) => m.id === model) || null;
  } catch {}
  const modelConfig = {
    model,
    enableThinking:
      body.enable_thinking !== undefined ? !!body.enable_thinking : cfg ? !!cfg.thinkingDefaultOn : true,
    webSearchStatus: "DISABLED",
  };
  if (typeof body.temperature === "number") modelConfig.temperature = body.temperature;
  if (typeof body.top_p === "number") modelConfig.topP = body.top_p;

  const payload = {
    msgId: uuid(),
    conversationId: "chat-" + uuid(),
    query,
    isEditedQuery: false,
    modelConfig,
    multiMedias: [],
  };

  const url = UPSTREAM + CHAT_PATH + (ph ? `?${TOKEN_PARAM}=${encodeURIComponent(ph)}` : "");
  const headers = {
    "Content-Type": "application/json",
    "Accept-Language": "zh-CN",
    "x-timeZone": "Asia/Shanghai",
    Cookie: cookieHeader,
    "User-Agent":
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36",
  };

  let upstream;
  try {
    upstream = await fetch(url, {
      method: "POST",
      headers,
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(300000),
    });
  } catch (e) {
    return sendJson(res, 502, { error: { message: `upstream unreachable: ${e.message}`, type: "upstream_error" } });
  }

  if (!upstream.ok || !upstream.body) {
    const text = await upstream.text().catch(() => "");
    log(`upstream ${upstream.status}: ${text.slice(0, 300)}`);
    if (upstream.status === 302 || upstream.status === 401) {
      return sendJson(res, 401, {
        error: {
          message: "MiMo session expired - grab cookies again from aistudio.xiaomimimo.com (Cookie Pusher).",
          type: "authentication_error",
        },
      });
    }
    return sendJson(res, 502, {
      error: { message: `MiMo upstream ${upstream.status}: ${text.slice(0, 200)}`, type: "upstream_error" },
    });
  }

  const think = thinkSplitter();
  let usage = null;

  const emitDelta = (base, delta) => {
    if (delta.content) {
      res.write(`data: ${JSON.stringify({ ...base, choices: [{ index: 0, delta: { content: delta.content }, finish_reason: null }] })}\n\n`);
    }
    if (delta.reasoning) {
      res.write(`data: ${JSON.stringify({ ...base, choices: [{ index: 0, delta: { reasoning_content: delta.reasoning }, finish_reason: null }] })}\n\n`);
    }
  };

  if (stream) {
    res.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
      "X-Accel-Buffering": "no",
    });
    const base = {
      id: "chatcmpl-" + uuid(),
      object: "chat.completion.chunk",
      created: Math.floor(Date.now() / 1000),
      model,
    };
    for await (const ev of iterateSSE(upstream.body)) {
      if (ev.event === "message") {
        let data = {};
        try {
          data = JSON.parse(ev.data || "{}");
        } catch {}
        emitDelta(base, think.push(data.content || ""));
      } else if (ev.event === "usage") {
        try {
          usage = JSON.parse(ev.data || "{}");
        } catch {}
      } else if (ev.event === "error") {
        let data = {};
        try {
          data = JSON.parse(ev.data || "{}");
        } catch {}
        emitDelta(base, think.flush());
        res.write(
          `data: ${JSON.stringify({ ...base, choices: [{ index: 0, delta: {}, finish_reason: "stop" }] })}\n\n`
        );
        log(`upstream error event: ${(data.content || "").slice(0, 200)}`);
        break;
      } else if (ev.event === "finish" || ev.event === "done") {
        break;
      }
    }
    emitDelta(base, think.flush());
    res.write(
      `data: ${JSON.stringify({ ...base, choices: [{ index: 0, delta: {}, finish_reason: "stop" }] })}\n\n`
    );
    if (usage) {
      const u = mapUsage(usage);
      if (u) res.write(`data: ${JSON.stringify({ ...base, choices: [], usage: u })}\n\n`);
    }
    res.write("data: [DONE]\n\n");
    res.end();
    return;
  }

  // non-stream
  let content = "";
  let reasoning = "";
  for await (const ev of iterateSSE(upstream.body)) {
    if (ev.event === "message") {
      try {
        const d = JSON.parse(ev.data || "{}");
        const t = think.push(d.content || "");
        content += t.content;
        reasoning += t.reasoning;
      } catch {}
    } else if (ev.event === "usage") {
      try {
        usage = JSON.parse(ev.data || "{}");
      } catch {}
    } else if (ev.event === "error") {
      let msg = "MiMo upstream error";
      try {
        const d = JSON.parse(ev.data || "{}");
        if (d.content) msg = d.content;
      } catch {}
      return sendJson(res, 502, { error: { message: msg, type: "upstream_error" } });
    } else if (ev.event === "finish" || ev.event === "done") {
      break;
    }
  }
  const t = think.flush();
  content += t.content;
  reasoning += t.reasoning;
  const message = { role: "assistant", content };
  if (reasoning) message.reasoning_content = reasoning;
  sendJson(res, 200, {
    id: "chatcmpl-" + uuid(),
    object: "chat.completion",
    created: Math.floor(Date.now() / 1000),
    model,
    choices: [{ index: 0, message, finish_reason: "stop" }],
    ...(mapUsage(usage) ? { usage: mapUsage(usage) } : {}),
  });
}

// ---------------- HTTP server ----------------

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, `http://${req.headers.host || "localhost"}`);
    const pathname = url.pathname.replace(/\/+$/, "") || "/";
    if (req.method === "GET" && (pathname === "/v1/models" || pathname === "/models")) {
      try {
        const list = await refreshModels();
        sendJson(res, 200, {
          object: "list",
          data: list.map((m) => ({ id: m.id, object: "model", owned_by: "xiaomimimo", created: 0 })),
        });
      } catch (e) {
        sendJson(res, 503, { error: { message: `models unavailable: ${e.message}`, type: "upstream_error" } });
      }
      return;
    }
    if (req.method === "GET" && pathname === "/healthz") {
      sendJson(res, 200, { ok: true });
      return;
    }
    if (req.method === "POST" && pathname === "/v1/cookies") {
      const body = await readJson(req);
      const raw =
        body && body.cookies && typeof body.cookies === "object"
          ? body.cookies
          : body && body.header
            ? parseHeader(body.header)
            : null;
      if (!raw) {
        return sendJson(res, 400, { error: "send {cookies:{name:value}} or {header:'a=b; c=d'}" });
      }
      const flat = {};
      for (const [k, v] of Object.entries(raw)) {
        if (k === "syncedAt") continue;
        if (typeof v === "string" && v) flat[k] = v;
      }
      if (!flat.session && !flat.SESSION) {
        return sendJson(res, 400, { error: "no session cookie in payload" });
      }
      flat.syncedAt = new Date().toISOString();
      fs.writeFileSync(COOKIE_FILE, JSON.stringify(flat, null, 2));
      log(`cookies updated (${Object.keys(flat).length - 1} cookies) -> ${COOKIE_FILE}`);
      sendJson(res, 200, { ok: true, cookies: Object.keys(flat).length - 1 });
      return;
    }
    if (req.method === "POST" && pathname === "/v1/chat/completions") {
      const body = await readJson(req);
      await handleChat(req, res, body);
      return;
    }
    sendJson(res, 404, { error: { message: `not found: ${req.method} ${pathname}` } });
  } catch (e) {
    log("handler error:", e.message);
    try {
      if (!res.headersSent) sendJson(res, 500, { error: { message: e.message } });
      else res.end();
    } catch {}
  }
});

server.listen(PORT, HOST, () => log(`mimo-web-bridge listening on http://${HOST}:${PORT}`));
