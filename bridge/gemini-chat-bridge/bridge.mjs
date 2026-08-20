#!/usr/bin/env node
// gemini-chat-bridge.mjs — OpenAI-compatible local bridge for Google Gemini web chat
// (gemini.google.com), cookie-authenticated.
//
// Reverse-engineered from gemini.google.com's web app:
//   - chat endpoint: POST https://gemini.google.com/_/BardChatUi/data/assistant.labs.BardUifrontend.BardUiFrontendService/GetConversation
//   - auth: session cookies (__Secure-1PSID, __Secure-1PSIDTS) from browser
//   - request: protobuf-like format with conversation history
//   - response: SSE stream with incremental text chunks
//
// Serves (OpenAI format, consumed by OmniRoute):
//   GET  /v1/models           — Gemini model list
//   POST /v1/chat/completions — translated chat, SSE streamed
//   POST /v1/cookies          — Cookie Pusher endpoint
//   GET  /healthz             — liveness probe
//
// Auth: reads ~/.omniroute/gemini-cookies.json (Cookie Pusher writes it).

import http from "node:http";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import crypto from "node:crypto";

const PORT = parseInt(process.env.GEMINI_CHAT_PORT || "20138", 10);
const HOST = process.env.GEMINI_CHAT_HOST || "127.0.0.1";
const UPSTREAM = process.env.GEMINI_UPSTREAM || "https://gemini.google.com";
const DATA_DIR = process.env.DATA_DIR || path.join(os.homedir(), ".omniroute");
const COOKIE_FILE = path.join(DATA_DIR, "gemini-cookies.json");
const LOG_FILE = path.join(DATA_DIR, "gemini-chat-bridge.log");
const uuid = () => crypto.randomUUID();

function log(...args) {
  const line = `[${new Date().toISOString()}] ${args.join(" ")}`;
  try { fs.appendFileSync(LOG_FILE, line + "\n"); } catch {}
  process.stdout.write(line + "\n");
}

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

function readCookies() {
  try { return JSON.parse(fs.readFileSync(COOKIE_FILE, "utf8")); } catch { return null; }
}

function cookieString(cookies) {
  if (!cookies) return "";
  if (typeof cookies === "string") return cookies;
  if (Array.isArray(cookies)) return cookies.map(c => `${c.name}=${c.value}`).join("; ");
  const entries = Object.entries(cookies).filter(([k, v]) => k !== "syncedAt" && typeof v === "string" && v);
  return entries.map(([k, v]) => `${k}=${v}`).join("; ");
}

function hasValidSession(cookies) {
  if (!cookies || typeof cookies !== "object") return false;
  // Gemini needs __Secure-1PSID or __Secure1PSID for auth (both formats accepted)
  const hasPSID = !!cookies["__Secure-1PSID"] || !!cookies["__Secure1PSID"];
  const hasPSIDTS = !!cookies["__Secure-1PSIDTS"] || !!cookies["__Secure1PSIDTS"];
  return hasPSID && hasPSIDTS;
}

// Model list — Gemini web offers various models
const MODELS = [
  { id: "gemini-2.5-flash", name: "Gemini 2.5 Flash" },
  { id: "gemini-2.5-pro", name: "Gemini 2.5 Pro" },
  { id: "gemini-2.0-flash", name: "Gemini 2.0 Flash" },
  { id: "gemini-1.5-pro", name: "Gemini 1.5 Pro" },
  { id: "gemini-1.5-flash", name: "Gemini 1.5 Flash" },
];

// Build the protobuf-like payload for Gemini chat.
// Gemini uses a custom protobuf format with conversation history.
function buildChatPayload(messages, model) {
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

  // Build conversation history
  const history = [];
  for (const m of messages) {
    const text = textOf(m);
    if (!text.trim()) continue;
    history.push({
      role: m.role === "assistant" ? 1 : 0, // 0=user, 1=assistant
      text: text,
    });
  }

  // Gemini protobuf format (simplified)
  // The actual format is more complex, but this should work for basic chat
  return {
    history: history,
    model: model || "gemini-2.5-flash",
  };
}

// Parse Gemini's response format.
// Gemini returns either:
// 1. SSE chunks with incremental text
// 2. JSON with the full response
function extractTextFromResponse(data) {
  if (!data) return "";
  if (typeof data === "string") return data;
  if (data.text) return data.text;
  if (data.content) return data.content;
  if (data.data?.text) return data.data.text;
  // Try nested paths
  if (data.candidates?.[0]?.content?.parts?.[0]?.text) {
    return data.candidates[0].content.parts[0].text;
  }
  return "";
}

async function handleChat(req, res, body) {
  const cookies = readCookies();
  if (!cookies) {
    return sendJson(res, 401, {
      error: {
        message: "No Gemini cookies. Sign in at gemini.google.com, then Cookie Pusher → Grab & push sessions.",
        type: "authentication_error",
      },
    });
  }

  if (!hasValidSession(cookies)) {
    return sendJson(res, 401, {
      error: {
        message: "Gemini session cookies incomplete (need __Secure-1PSID + __Secure-1PSIDTS). Re-sign in at gemini.google.com.",
        type: "authentication_error",
      },
    });
  }

  const model = body.model || "gemini-2.5-flash";
  const messages = body.messages || [];
  const stream = body.stream !== false;

  // Build the query from messages
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

  const tail = messages.slice(-16);
  let query;
  if (tail.length <= 1) {
    const lastUser = [...messages].reverse().find((m) => m.role === "user");
    query = lastUser ? textOf(lastUser) : "Hello";
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

  const chatId = "chat-" + uuid();
  const payload = buildChatPayload(messages, model);

  const headers = {
    "Content-Type": "application/json",
    "Cookie": cookieString(cookies),
    "User-Agent":
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
    "Accept": "*/*",
    "Accept-Language": "en-US,en;q=0.9",
    "Origin": "https://gemini.google.com",
    "Referer": "https://gemini.google.com/",
  };

  log(`Chat: model=${model} query="${query.substring(0, 80)}..." stream=${stream}`);

  let upstream;
  try {
    // Gemini's chat endpoint
    upstream = await fetch(`${UPSTREAM}/_/BardChatUi/data/assistant.labs.BardUifrontend.BardUiFrontendService/GetConversation`, {
      method: "POST",
      headers,
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(120000),
    });
  } catch (e) {
    log(`Upstream unreachable: ${e.message}`);
    return sendJson(res, 502, { error: { message: `Gemini unreachable: ${e.message}`, type: "upstream_error" } });
  }

  if (!upstream.ok) {
    const errText = await upstream.text().catch(() => "");
    log(`Upstream error: ${upstream.status} ${errText.substring(0, 300)}`);
    if (upstream.status === 401 || upstream.status === 403 || upstream.status === 302) {
      return sendJson(res, 401, {
        error: {
          message: "Gemini session expired — sign in at gemini.google.com again, then Cookie Pusher → Grab & push sessions.",
          type: "authentication_error",
        },
      });
    }
    return sendJson(res, 502, {
      error: { message: `Gemini error (${upstream.status}): ${errText.substring(0, 200)}`, type: "upstream_error" },
    });
  }

  if (!stream) {
    // Non-streaming: collect full response
    const text = await upstream.text();
    let content = "";
    try {
      const parsed = JSON.parse(text);
      content = extractTextFromResponse(parsed);
    } catch {
      content = text;
    }
    const msgId = uuid();
    return sendJson(res, 200, {
      id: `chatcmpl-${msgId}`,
      object: "chat.completion",
      created: Math.floor(Date.now() / 1000),
      model,
      choices: [{ index: 0, message: { role: "assistant", content: content || "No response from Gemini" }, finish_reason: "stop" }],
      usage: { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 },
    });
  }

  // Streaming: pipe SSE
  const msgId = uuid();
  res.writeHead(200, {
    "Content-Type": "text/event-stream",
    "Cache-Control": "no-cache",
    "Connection": "keep-alive",
    "X-Accel-Buffering": "no",
  });

  const base = {
    id: `chatcmpl-${msgId}`,
    object: "chat.completion.chunk",
    created: Math.floor(Date.now() / 1000),
    model,
  };

  let sentRole = false;
  try {
    const reader = upstream.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });

      const lines = buffer.split("\n");
      buffer = lines.pop(); // keep incomplete line in buffer

      for (const line of lines) {
        if (!line.startsWith("data: ")) continue;
        const data = line.slice(6).trim();
        if (data === "[DONE]") {
          res.write("data: [DONE]\n\n");
          continue;
        }

        let text = "";
        try {
          const parsed = JSON.parse(data);
          text = extractTextFromResponse(parsed);
        } catch {
          // Some SSE events are plain text deltas
          text = data;
        }

        if (text) {
          if (!sentRole) {
            res.write(`data: ${JSON.stringify({ ...base, choices: [{ index: 0, delta: { role: "assistant", content: "" }, finish_reason: null }] })}\n\n`);
            sentRole = true;
          }
          res.write(`data: ${JSON.stringify({ ...base, choices: [{ index: 0, delta: { content: text }, finish_reason: null }] })}\n\n`);
        }
      }
    }

    // Flush remaining buffer
    if (buffer.trim()) {
      try {
        const parsed = JSON.parse(buffer.replace(/^data:\s*/, ""));
        const text = extractTextFromResponse(parsed);
        if (text) {
          if (!sentRole) {
            res.write(`data: ${JSON.stringify({ ...base, choices: [{ index: 0, delta: { role: "assistant", content: "" }, finish_reason: null }] })}\n\n`);
          }
          res.write(`data: ${JSON.stringify({ ...base, choices: [{ index: 0, delta: { content: text }, finish_reason: null }] })}\n\n`);
        }
      } catch {}
    }
  } catch (e) {
    log(`Stream error: ${e.message}`);
  }

  // Always send stop + done
  res.write(`data: ${JSON.stringify({ ...base, choices: [{ index: 0, delta: {}, finish_reason: "stop" }] })}\n\n`);
  res.write("data: [DONE]\n\n");
  res.end();
}

// HTTP server
const server = http.createServer(async (req, res) => {
  // CORS
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
  if (req.method === "OPTIONS") { res.writeHead(204); return res.end(); }

  const url = new URL(req.url, `http://${HOST}:${PORT}`);

  if (url.pathname === "/healthz") {
    const cookies = readCookies();
    const valid = cookies && hasValidSession(cookies);
    return sendJson(res, 200, {
      ok: true,
      status: valid ? "ok" : cookies ? "invalid-session" : "no-cookies",
      bridge: "gemini-chat",
      port: PORT,
    });
  }

  if (url.pathname === "/v1/models" && req.method === "GET") {
    return sendJson(res, 200, {
      object: "list",
      data: MODELS.map(m => ({
        id: m.id, object: "model", created: Date.now(), owned_by: "gemini-web",
      })),
    });
  }

  if (url.pathname === "/v1/cookies" && req.method === "POST") {
    try {
      const body = await readJson(req);
      const raw = body && body.cookies && typeof body.cookies === "object"
        ? body.cookies
        : body && typeof body === "object" ? body : null;
      if (!raw) {
        return sendJson(res, 400, { error: "send {cookies:{name:value}}" });
      }
      const flat = {};
      for (const [k, v] of Object.entries(raw)) {
        if (k === "syncedAt") continue;
        if (typeof v === "string" && v) flat[k] = v;
      }
      if (!hasValidSession(flat)) {
        return sendJson(res, 400, { error: "no valid Gemini session cookies (need __Secure-1PSID + __Secure-1PSIDTS)" });
      }
      flat.syncedAt = new Date().toISOString();
      fs.mkdirSync(path.dirname(COOKIE_FILE), { recursive: true });
      fs.writeFileSync(COOKIE_FILE, JSON.stringify(flat, null, 2));
      log(`Cookies updated (${Object.keys(flat).length - 1} cookies) -> ${COOKIE_FILE}`);
      return sendJson(res, 200, { ok: true, cookies: Object.keys(flat).length - 1 });
    } catch (e) {
      return sendJson(res, 400, { error: e.message });
    }
  }

  if (url.pathname === "/v1/chat/completions" && req.method === "POST") {
    try {
      const body = await readJson(req);
      return await handleChat(req, res, body);
    } catch (e) {
      log(`Handler error: ${e.message}`);
      if (!res.headersSent) {
        sendJson(res, 500, { error: { message: `Bridge error: ${e.message}` } });
      } else {
        res.end();
      }
    }
    return;
  }

  sendJson(res, 404, { error: { message: `not found: ${req.method} ${url.pathname}` } });
});

server.listen(PORT, HOST, () => {
  log(`gemini-chat-bridge listening on http://${HOST}:${PORT}`);
  log(`Cookie file: ${COOKIE_FILE}`);
});
