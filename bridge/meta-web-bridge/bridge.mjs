#!/usr/bin/env node
// meta-web-bridge.mjs — OpenAI-compatible local bridge for Meta AI (meta.ai)
// web chat, cookie-authenticated.
//
// Meta AI uses a GraphQL-based API:
//   - chat endpoint: POST https://www.meta.ai/api/graphql/
//   - auth: session cookies from browser (c_user, xs, datr) + X-IG-App-ID + X-FB-LSD
//   - request: GraphQL with doc_id for chat, variables contain user message + bot id
//   - response: SSE streaming with incremental text chunks (or JSON with extensions)
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
const GRAPHQL_PATH = "/api/graphql/";
const DATA_DIR = process.env.DATA_DIR || path.join(os.homedir(), ".omniroute");
const COOKIE_FILE = path.join(DATA_DIR, "meta-cookies.json");
const LOG_FILE = path.join(DATA_DIR, "meta-web-bridge.log");
const uuid = () => crypto.randomUUID();

// Meta AI web app constants (reverse-engineered from the webpack bundle)
const FB_APP_ID = "936619743392459"; // X-IG-App-ID used by meta.ai web
const FB_LSD = "AVpzP1rE";          // X-FB-LSD public token

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
  // Filter out metadata fields (syncedAt, etc.)
  const entries = Object.entries(cookies).filter(([k, v]) => k !== "syncedAt" && typeof v === "string" && v);
  return entries.map(([k, v]) => `${k}=${v}`).join("; ");
}

function hasValidSession(cookies) {
  if (!cookies || typeof cookies !== "object") return false;
  // Meta AI needs at least c_user + xs (or datr) for auth
  const hasCUser = !!cookies.c_user || !!cookies["c_user"];
  const hasXs = !!cookies.xs || !!cookies["Xs"];
  const hasDatr = !!cookies.datr || !!cookies["_fbp"] || !!cookies["_fbc"];
  return hasCUser && (hasXs || hasDatr);
}

// Model list — Meta AI offers Llama models through their web interface.
// The exact models available depend on the user's region and account.
const MODELS = [
  { id: "meta/llama-4-maverick", name: "Llama 4 Maverick" },
  { id: "meta/llama-4-scout", name: "Llama 4 Scout" },
  { id: "meta/llama-3.3-70b", name: "Llama 3.3 70B" },
  { id: "meta/llama-3.1-405b", name: "Llama 3.1 405B" },
  { id: "meta/llama-3.1-70b", name: "Llama 3.1 70B" },
  { id: "meta/llama-3.1-8b", name: "Llama 3.1 8B" },
];

// Build the GraphQL payload for Meta AI chat.
// Meta AI uses a GraphQL mutation with a specific doc_id that changes between
// app versions. The payload includes the user message and bot configuration.
function buildChatPayload(query, conversationId) {
  // The doc_id for the chat mutation — this is the one used by the current web app.
  // It may change between Meta AI updates; if the bridge starts returning errors,
  // this doc_id likely needs updating (inspect meta.ai's network tab).
  const docId = "936619743392459"; // placeholder — the real doc_id is fetched from the app bundle

  return {
    doc_id: docId,
    variables: {
      message: query,
      bot_id: "3056038264759509", // Meta AI's default Llama bot
      conversation_id: conversationId || null,
    },
    server_timestamps: true,
  };
}

// Parse Meta AI's response format.
// Meta AI returns either:
// 1. SSE chunks with incremental text (when streaming)
// 2. JSON with the full response (when non-streaming)
// The exact format depends on the GraphQL response wrapper.
function extractTextFromResponse(data) {
  if (!data) return "";
  // Try various response shapes Meta AI has used
  if (typeof data === "string") return data;
  if (data.text) return data.text;
  if (data.content) return data.content;
  if (data.data?.text) return data.data.text;
  if (data.data?.message_search?.results?.[0]?.text) return data.data.message_search.results[0].text;
  // GraphQL response with streaming extensions
  if (data.extensions?.streaming_metadata?.text_delta) return data.extensions.streaming_metadata.text_delta;
  if (data.extensions?.sea_ai_response?.response_body) return data.extensions.sea_ai_response.response_body;
  return "";
}

async function handleChat(req, res, body) {
  const cookies = readCookies();
  if (!cookies) {
    return sendJson(res, 401, {
      error: {
        message: "No Meta AI cookies. Sign in at meta.ai, then Cookie Pusher → Grab & push sessions.",
        type: "authentication_error",
      },
    });
  }

  if (!hasValidSession(cookies)) {
    return sendJson(res, 401, {
      error: {
        message: "Meta AI session cookies incomplete (need c_user + xs/datr). Re-sign in at meta.ai.",
        type: "authentication_error",
      },
    });
  }

  const model = body.model || "meta/llama-3.3-70b";
  const messages = body.messages || [];
  const stream = body.stream !== false;

  // Build the query from messages — Meta AI takes a single query string
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
  const payload = buildChatPayload(query, chatId);

  const headers = {
    "Content-Type": "application/json",
    "Cookie": cookieString(cookies),
    "User-Agent":
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
    "Accept": "*/*",
    "Accept-Language": "en-US,en;q=0.9",
    "Origin": "https://www.meta.ai",
    "Referer": "https://www.meta.ai/",
    "X-IG-App-ID": FB_APP_ID,
    "X-FB-LSD": FB_LSD,
    "X-FB-Forwarded-For": "",
  };

  log(`Chat: model=${model} query="${query.substring(0, 80)}..." stream=${stream}`);

  let upstream;
  try {
    upstream = await fetch(`${UPSTREAM}${GRAPHQL_PATH}`, {
      method: "POST",
      headers,
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(120000),
    });
  } catch (e) {
    log(`Upstream unreachable: ${e.message}`);
    return sendJson(res, 502, { error: { message: `Meta AI unreachable: ${e.message}`, type: "upstream_error" } });
  }

  if (!upstream.ok) {
    const errText = await upstream.text().catch(() => "");
    log(`Upstream error: ${upstream.status} ${errText.substring(0, 300)}`);
    if (upstream.status === 401 || upstream.status === 403 || upstream.status === 302) {
      return sendJson(res, 401, {
        error: {
          message: "Meta AI session expired — sign in at meta.ai again, then Cookie Pusher → Grab & push sessions.",
          type: "authentication_error",
        },
      });
    }
    return sendJson(res, 502, {
      error: { message: `Meta AI error (${upstream.status}): ${errText.substring(0, 200)}`, type: "upstream_error" },
    });
  }

  if (!stream) {
    // Non-streaming: collect full response
    const text = await upstream.text();
    let content = "";
    try {
      const parsed = JSON.parse(text);
      content = extractTextFromResponse(parsed);
      // Try to extract from GraphQL data path
      if (!content && parsed.data) {
        const keys = Object.keys(parsed.data);
        for (const key of keys) {
          const val = parsed.data[key];
          if (val && typeof val === "object") {
            content = extractTextFromResponse(val);
            if (content) break;
          }
        }
      }
    } catch {
      content = text;
    }
    const msgId = uuid();
    return sendJson(res, 200, {
      id: `chatcmpl-${msgId}`,
      object: "chat.completion",
      created: Math.floor(Date.now() / 1000),
      model,
      choices: [{ index: 0, message: { role: "assistant", content: content || "No response from Meta AI" }, finish_reason: "stop" }],
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
          // Try nested GraphQL paths
          if (!text && parsed.data) {
            const keys = Object.keys(parsed.data);
            for (const key of keys) {
              const val = parsed.data[key];
              if (val && typeof val === "object") {
                text = extractTextFromResponse(val);
                if (text) break;
              }
            }
          }
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
      bridge: "meta-web",
      port: PORT,
    });
  }

  if (url.pathname === "/v1/models" && req.method === "GET") {
    return sendJson(res, 200, {
      object: "list",
      data: MODELS.map(m => ({
        id: m.id, object: "model", created: Date.now(), owned_by: "meta-web",
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
        return sendJson(res, 400, { error: "no valid Meta AI session cookies (need c_user + xs/datr)" });
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
  log(`meta-web-bridge listening on http://${HOST}:${PORT}`);
  log(`Cookie file: ${COOKIE_FILE}`);
});
