#!/usr/bin/env node
// meta-web-bridge.mjs — OpenAI-compatible local bridge for Meta AI (meta.ai)
// web chat, cookie-authenticated.
//
// Meta AI uses a GraphQL-based API:
//   - chat endpoint: POST https://www.meta.ai/api/v1/chat/
//   - auth: session cookies from browser (c_user, xs, datr)
//   - request: { messages: [{author, text}], model: "LATEST" }
//   - response: SSE streaming with incremental text chunks
//
// Serves (OpenAI format, consumed by OmniRoute):
//   GET  /v1/models           — model list
//   POST /v1/chat/completions — translated chat, SSE streamed
//   POST /v1/cookies          — Cookie Pusher endpoint
//   GET  /healthz             — liveness probe
//
// Auth: reads ~/.omniroute/meta-cookies.json (Cookie Pusher writes it).

import http from "node:http";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import crypto from "node:crypto";

const PORT = parseInt(process.env.META_BRIDGE_PORT || "20136", 10);
const HOST = process.env.META_BRIDGE_HOST || "127.0.0.1";
const UPSTREAM = process.env.META_UPSTREAM || "https://www.meta.ai";
const CHAT_PATH = "/api/v1/chat/";
const DATA_DIR = process.env.DATA_DIR || path.join(os.homedir(), ".omniroute");
const COOKIE_FILE = path.join(DATA_DIR, "meta-cookies.json");
const LOG_FILE = path.join(DATA_DIR, "meta-web-bridge.log");
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
    req.on("data", (c) => { data += c; if (data.length > 8e6) { reject(new Error("body too large")); req.destroy(); } });
    req.on("end", () => { try { resolve(JSON.parse(data)); } catch (e) { reject(e); } });
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
  return Object.entries(cookies).map(([k, v]) => `${k}=${v}`).join("; ");
}

// Model list (Meta AI offers Llama models)
const MODELS = [
  { id: "meta/llama-3.3-70b", name: "Llama 3.3 70B" },
  { id: "meta/llama-3.1-405b", name: "Llama 3.1 405B" },
  { id: "meta/llama-3.1-70b", name: "Llama 3.1 70B" },
  { id: "meta/llama-3.1-8b", name: "Llama 3.1 8B" },
  { id: "meta-llama-3.3-70b-instruct", name: "Llama 3.3 70B Instruct" },
];

async function handleChat(req, res) {
  const cookies = readCookies();
  if (!cookies) {
    return sendJson(res, 401, { error: { message: "No Meta AI cookies. Sign in at meta.ai, then Cookie Pusher → Grab & push sessions." } });
  }

  const body = await readJson(req);
  const model = body.model || "meta/llama-3.3-70b";
  const messages = body.messages || [];
  const stream = body.stream !== false;

  // Extract last user message
  const lastMsg = messages.filter(m => m.role === "user").pop();
  const query = lastMsg ? (typeof lastMsg.content === "string" ? lastMsg.content : JSON.stringify(lastMsg.content)) : "Hello";

  const msgId = uuid();
  const chatId = uuid();

  // Build Meta AI chat payload
  const payload = {
    messages: messages.map(m => ({
      author: m.role === "assistant" ? "bot" : "user",
      text: typeof m.content === "string" ? m.content : JSON.stringify(m.content),
    })),
    model: "LATEST",
  };

  const headers = {
    "Content-Type": "application/json",
    "Cookie": cookieString(cookies),
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
    "Accept": "*/*",
    "Accept-Language": "en-US,en;q=0.9",
    "Origin": "https://www.meta.ai",
    "Referer": "https://www.meta.ai/",
    "X-FB-LSD": "AVpzP1rE",  // Meta's public lsd token
  };

  log(`Chat: model=${model} query="${query.substring(0, 80)}..." stream=${stream}`);

  try {
    const upstream = await fetch(`${UPSTREAM}${CHAT_PATH}`, {
      method: "POST",
      headers,
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(60000),
    });

    if (!upstream.ok) {
      const errText = await upstream.text().catch(() => "");
      log(`Upstream error: ${upstream.status} ${errText.substring(0, 200)}`);
      return sendJson(res, upstream.status, { error: { message: `Meta AI error (${upstream.status}): ${errText.substring(0, 200)}` } });
    }

    if (!stream) {
      // Non-streaming: collect full response
      const text = await upstream.text();
      const content = extractContent(text);
      return sendJson(res, 200, {
        id: `chatcmpl-${msgId}`,
        object: "chat.completion",
        created: Math.floor(Date.now() / 1000),
        model,
        choices: [{ index: 0, message: { role: "assistant", content }, finish_reason: "stop" }],
        usage: { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 },
      });
    }

    // Streaming: pipe SSE
    res.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      "Connection": "keep-alive",
    });

    const reader = upstream.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";
    let sentRole = false;

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });

      const lines = buffer.split("\n");
      buffer = lines.pop();

      for (const line of lines) {
        if (!line.startsWith("data: ")) continue;
        const data = line.slice(6).trim();
        if (data === "[DONE]") {
          res.write("data: [DONE]\n\n");
          continue;
        }
        try {
          const parsed = JSON.parse(data);
          const text = parsed.text || parsed.content || parsed.delta?.content || "";
          if (text) {
            if (!sentRole) {
              res.write(`data: ${JSON.stringify({ id: `chatcmpl-${msgId}`, object: "chat.completion.chunk", choices: [{ index: 0, delta: { role: "assistant", content: "" }, finish_reason: null }] })}\n\n`);
              sentRole = true;
            }
            res.write(`data: ${JSON.stringify({ id: `chatcmpl-${msgId}`, object: "chat.completion.chunk", choices: [{ index: 0, delta: { content: text }, finish_reason: null }] })}\n\n`);
          }
        } catch {}
      }
    }
    res.end();
  } catch (e) {
    log(`Error: ${e.message}`);
    if (!res.headersSent) {
      sendJson(res, 500, { error: { message: `Bridge error: ${e.message}` } });
    } else {
      res.end();
    }
  }
}

function extractContent(text) {
  // Try to extract text from Meta AI's response format
  try {
    const parsed = JSON.parse(text);
    return parsed.text || parsed.content || parsed.data?.text || text;
  } catch {
    return text;
  }
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
    return sendJson(res, 200, { status: cookies ? "ok" : "no-cookies", bridge: "meta-web", port: PORT });
  }

  if (url.pathname === "/v1/models" && req.method === "GET") {
    return sendJson(res, 200, {
      object: "list",
      data: MODELS.map(m => ({
        id: m.id, object: "model", created: Date.now(), owned_by: "meta-web",
        permission: [], root: m.id, parent: null,
      })),
    });
  }

  if (url.pathname === "/v1/cookies" && req.method === "POST") {
    try {
      const body = await readJson(req);
      fs.mkdirSync(path.dirname(COOKIE_FILE), { recursive: true });
      fs.writeFileSync(COOKIE_FILE, JSON.stringify(body.cookies || body, null, 2));
      log(`Cookies updated (${COOKIE_FILE})`);
      return sendJson(res, 200, { ok: true, file: COOKIE_FILE });
    } catch (e) {
      return sendJson(res, 400, { error: e.message });
    }
  }

  if (url.pathname === "/v1/chat/completions" && req.method === "POST") {
    return handleChat(req, res);
  }

  sendJson(res, 404, { error: "Not found" });
});

server.listen(PORT, HOST, () => {
  log(`meta-web-bridge listening on http://${HOST}:${PORT}`);
  log(`Cookie file: ${COOKIE_FILE}`);
});
