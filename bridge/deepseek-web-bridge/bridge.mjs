#!/usr/bin/env node
// deepseek-web-bridge.mjs — OpenAI-compatible local bridge for DeepSeek web chat
// (chat.deepseek.com), cookie/token-authenticated, with AUTO-CONTINUE.
//
// Why this bridge exists:
//   The gateway's built-in deepseek-web executor stops the moment DeepSeek's web
//   stream signals the response is incomplete. In the web UI that shows up as the
//   "Continue generating" button on long chats: DeepSeek finishes a response with
//   status INCOMPLETE / AUTO_CONTINUE and the user must click to resume. This
//   bridge replicates the web client's continue protocol (the same one ds2api
//   reverse-engineered) and does it AUTOMATICALLY: when the stream ends with
//   INCOMPLETE/AUTO_CONTINUE it calls POST /api/v0/chat/continue with the captured
//   response_message_id and splices the continuation stream on, up to 8 rounds —
//   so long chats stream to completion with no button and no truncation.
//
// Protocol (reverse-engineered from chat.deepseek.com web client + ds2api):
//   - auth      : Bearer <userToken> on POST /api/v0/users/current -> accessToken
//                 (short-lived; cached 1h per userToken)
//   - pow       : POST /api/v0/chat/create_pow_challenge {target_path:"/api/v0/chat/completion"}
//                 -> {algorithm,challenge,salt,difficulty,expire_at,...}; answer =
//                 base64({algorithm,challenge,salt,answer,signature,target_path})
//                 where answer is the nonce n with keccak256(salt_expireAt_n) == challenge
//   - session   : POST /api/v0/chat_session/create {} -> chat_session.id
//                 (fresh per request; deleted after the stream closes)
//   - chat      : POST /api/v0/chat/completion {chat_session_id, parent_message_id:null,
//                 model_type, prompt, ref_file_ids:[], thinking_enabled, search_enabled,
//                 preempt:false} with X-Ds-Pow-Response header; SSE response
//   - continue  : POST /api/v0/chat/continue {chat_session_id, message_id,
//                 fallback_to_resume:true} (same headers/PoW answer); SSE response
//                 spliced onto the previous stream
//
// Serves (OpenAI format, consumed by OmniRoute's openai-compatible provider nodes):
//   GET  /v1/models           — deepseek-web model list
//   POST /v1/chat/completions — translated chat, SSE streamed back (+ auto-continue)
//   POST /v1/cookies          — Cookie Pusher endpoint: store the userToken
//   GET  /healthz             — liveness probe
//
// Auth: reads ~/.omniroute/deepseek-cookies.json on every request (Cookie Pusher
// writes {userToken} there). Zero runtime dependencies beyond node:http + fetch;
// the PoW solver is the pure-JS keccak from the omniroute package (copied here).

import http from "node:http";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import crypto from "node:crypto";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);

const PORT = parseInt(process.env.DEEPSEEK_BRIDGE_PORT || "20136", 10);
const HOST = process.env.DEEPSEEK_BRIDGE_HOST || "127.0.0.1";
const UPSTREAM = process.env.DEEPSEEK_UPSTREAM || "https://chat.deepseek.com";
const API_BASE = `${UPSTREAM}/api`;
const COMPLETION_URL = `${API_BASE}/v0/chat/completion`;
const CONTINUE_URL = `${API_BASE}/v0/chat/continue`;
const DATA_DIR = process.env.DATA_DIR || path.join(os.homedir(), ".omniroute");
const COOKIE_FILE = path.join(DATA_DIR, "deepseek-cookies.json");
const LOG_FILE = path.join(DATA_DIR, "deepseek-web-bridge.log");
const MAX_CONTINUE_ROUNDS = 8;
const MAX_QUERY = 40000;

// Fingerprint headers the chat.deepseek.com web client sends on every /api/v0/* request
// (mirrors the gateway's deepseek-web executor - client v2.0.0).
const FAKE_HEADERS = {
  Accept: "*/*",
  "Accept-Encoding": "gzip, deflate, br, zstd",
  "Accept-Language": "en-US,en;q=0.9",
  Origin: UPSTREAM,
  Referer: `${UPSTREAM}/`,
  "User-Agent":
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36",
  "X-Client-Bundle-Id": "com.deepseek.chat",
  "X-Client-Locale": "en-US",
  "X-Client-Platform": "web",
  "X-Client-Version": "2.0.0",
};

// deepseek-web model ids (same list as the gateway's provider registry, so the
// curated catalog + combo/* keep working unchanged).
const MODELS = [
  { id: "deepseek-v4-pro", name: "DeepSeek V4 Pro" },
  { id: "deepseek-v4-pro-think", name: "DeepSeek V4 Pro Think" },
  { id: "deepseek-v4-pro-search", name: "DeepSeek V4 Pro Search" },
  { id: "deepseek-v4-pro-think-search", name: "DeepSeek V4 Pro Think+Search" },
  { id: "deepseek-v4-flash", name: "DeepSeek V4 Flash" },
  { id: "deepseek-v4-flash-think", name: "DeepSeek V4 Flash Think" },
  { id: "deepseek-v4-flash-search", name: "DeepSeek V4 Flash Search" },
  { id: "deepseek-v4-flash-think-search", name: "DeepSeek V4 Flash Think+Search" },
  { id: "deepseek-chat", name: "DeepSeek Chat" },
  { id: "deepseek-reasoner", name: "DeepSeek Reasoner" },
  { id: "DeepSeek-R1", name: "DeepSeek R1" },
  { id: "DeepSeek-R1-Search", name: "DeepSeek R1 Search" },
  { id: "DeepSeek-V3.2", name: "DeepSeek V3.2" },
  { id: "DeepSeek-Search", name: "DeepSeek Search" },
];

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

// ---------------- cookies / auth ----------------

function loadCookies() {
  try {
    const j = JSON.parse(fs.readFileSync(COOKIE_FILE, "utf8"));
    return typeof j.userToken === "string" && j.userToken ? j.userToken : null;
  } catch {
    return null;
  }
}

function extractUserToken(raw) {
  if (typeof raw !== "string" || !raw.length) return null;
  try {
    const parsed = JSON.parse(raw);
    if (typeof parsed?.value === "string") return parsed.value;
  } catch {
    // not JSON, use raw
  }
  return raw;
}

const tokenCache = new Map(); // userToken -> { accessToken, expiresAt }

async function acquireAccessToken(userToken, signal) {
  const cached = tokenCache.get(userToken);
  if (cached && cached.expiresAt > Math.floor(Date.now() / 1000)) return cached.accessToken;

  const resp = await fetch(`${API_BASE}/v0/users/current`, {
    headers: { Authorization: `Bearer ${userToken}`, ...FAKE_HEADERS },
    signal: signal ?? undefined,
  });
  if (resp.status === 401 || resp.status === 403) {
    throw new Error("DeepSeek userToken invalid or expired - grab a fresh one (Cookie Pusher)");
  }
  if (!resp.ok) throw new Error(`users/current HTTP ${resp.status}`);
  const json = await resp.json();
  if (json?.code && json.code !== 0) {
    tokenCache.delete(userToken);
    throw new Error(`DeepSeek rejected token: ${json.msg || json?.data?.biz_msg || json.code}`);
  }
  const bizData = json?.data?.biz_data || json?.biz_data;
  if (!bizData?.token) throw new Error("No access token in users/current response");
  tokenCache.set(userToken, {
    accessToken: bizData.token,
    expiresAt: Math.floor(Date.now() / 1000) + 3600,
  });
  return bizData.token;
}

// ---------------- PoW (pure JS keccak, copied from the omniroute package) ----------------

function solveWithJS(challenge, prefix, difficulty) {
  const U = require("./deepseek-pow-solver.cjs").U;
  const createHash = () => {
    const self = {};
    self._sponge = new U({ capacity: 256, padding: 6 });
    self.update = (s) => {
      self._sponge.absorb(Buffer.from(s, "utf8"));
      return self;
    };
    self.digest = (fmt) => self._sponge.squeeze(6).toString(fmt || "hex");
    self.copy = () => {
      const c = {};
      c._sponge = self._sponge.copy();
      c.update = (s) => {
        c._sponge.absorb(Buffer.from(s, "utf8"));
        return c;
      };
      c.digest = (fmt) => c._sponge.squeeze(6).toString(fmt || "hex");
      return c;
    };
    return self;
  };
  const h = createHash();
  h.update(prefix);
  for (let nonce = 0; nonce < difficulty; nonce++) {
    if (h.copy().update(String(nonce)).digest("hex") === challenge) return nonce;
  }
  return -1;
}

async function solvePow(challenge) {
  const { algorithm, challenge: c, salt, difficulty, expire_at, signature, target_path } = challenge;
  if (algorithm !== "DeepSeekHashV1") throw new Error(`Unsupported PoW algorithm: ${algorithm}`);
  const prefix = `${salt}_${expire_at}_`;
  const answer = solveWithJS(c, prefix, difficulty);
  if (answer < 0) throw new Error("PoW solver failed");
  return Buffer.from(
    JSON.stringify({ algorithm, challenge: c, salt, answer, signature, target_path })
  ).toString("base64");
}

async function getPowChallenge(accessToken, signal) {
  const resp = await fetch(`${API_BASE}/v0/chat/create_pow_challenge`, {
    method: "POST",
    headers: { ...FAKE_HEADERS, "Content-Type": "application/json", Authorization: `Bearer ${accessToken}` },
    body: JSON.stringify({ target_path: "/api/v0/chat/completion" }),
    signal: signal ?? undefined,
  });
  if (!resp.ok) throw new Error(`create_pow_challenge HTTP ${resp.status}`);
  const json = await resp.json();
  const bizData = json?.data?.biz_data || json?.biz_data;
  if (!bizData?.challenge?.challenge) throw new Error(`No PoW challenge: code=${json?.code}`);
  return bizData.challenge;
}

// ---------------- sessions ----------------

async function createSession(accessToken, signal) {
  const resp = await fetch(`${API_BASE}/v0/chat_session/create`, {
    method: "POST",
    headers: { ...FAKE_HEADERS, "Content-Type": "application/json", Authorization: `Bearer ${accessToken}`, Cookie: fakeCookie() },
    body: JSON.stringify({}),
    signal: signal ?? undefined,
  });
  if (!resp.ok) throw new Error(`chat_session/create HTTP ${resp.status}`);
  const json = await resp.json();
  const bizData = json?.data?.biz_data || json?.biz_data;
  const id = bizData?.chat_session?.id;
  if (!id) throw new Error(`No session id: code=${json?.code}`);
  return id;
}

async function deleteSession(accessToken, sessionId) {
  try {
    await fetch(`${API_BASE}/v0/chat_session/delete`, {
      method: "POST",
      headers: { ...FAKE_HEADERS, "Content-Type": "application/json", Authorization: `Bearer ${accessToken}` },
      body: JSON.stringify({ chat_session_id: sessionId }),
      signal: AbortSignal.timeout(15000),
    });
  } catch {
    // best-effort cleanup
  }
}

function fakeCookie() {
  const ts = Date.now();
  const hex = (n) => Array.from({ length: n }, () => Math.floor(Math.random() * 16).toString(16)).join("");
  const uid = () =>
    "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
      const r = (Math.random() * 16) | 0;
      return (c === "x" ? r : (r & 0x3) | 0x8).toString(16);
    });
  return `intercom-HWWAFSESTIME=${ts}; HWWAFSESID=${hex(18)}; Hm_lvt_${uid()}=${Math.floor(ts / 1000)}; _frid=${uid()}`;
}

// ---------------- prompt building (same contract as the gateway executor) ----------------

function extractMessageText(content) {
  if (Array.isArray(content)) {
    return content.filter((p) => p && p.type === "text").map((p) => p.text || "").join("\n");
  }
  return String(content || "");
}

function messagesToPrompt(messages) {
  if (!Array.isArray(messages) || !messages.length) return "";
  const systemParts = [];
  let lastUserContent = "";
  for (const m of messages) {
    const text = extractMessageText(m.content).trim();
    if (m.role === "system") {
      if (text) systemParts.push(text);
    } else if (m.role === "user") {
      if (text) lastUserContent = text;
    }
  }
  const parts = [];
  if (systemParts.length) parts.push(systemParts.join("\n\n"));
  if (lastUserContent) parts.push(lastUserContent);
  return parts.join("\n\n").replace(/!\[.*?\]\(.*?\)/g, "");
}

// ---------------- model options ----------------

function resolveModelOptions(model, bodyObj) {
  const m = String(model || "").toLowerCase();
  const modelType = m.includes("pro") || m.includes("expert") ? "expert" : "default";
  const thinkingEnabled =
    m.includes("r1") || m.includes("think") || m.includes("reason") ||
    bodyObj?.thinking_enabled === true || bodyObj?.thinking === true || !!bodyObj?.reasoning_effort;
  const searchEnabled =
    m.includes("search") || bodyObj?.search_enabled === true || bodyObj?.search === true || bodyObj?.web_search === true;
  return { modelType, thinkingEnabled, searchEnabled };
}

// ---------------- content formatting (mirrors the gateway executor) ----------------

function cleanDeepSeekToken(text) {
  return text.replace(/FINISHED/g, "").replace(/^(SEARCH|WEB_SEARCH|SEARCHING)\s*/i, "");
}

function isThinkingModel(model) {
  const m = String(model || "").toLowerCase();
  return m.includes("think") || m.includes("r1") || m.includes("reason");
}

function isSearchModel(model) {
  const m = String(model || "").toLowerCase();
  return m.includes("search") || m.includes("fold");
}

function formatStreamContent(raw, model) {
  let text = cleanDeepSeekToken(raw);
  if (!isSearchModel(model)) return text;
  if (String(model).toLowerCase().includes("search-silent")) return text.replace(/\[citation:(\d+)\]/g, "");
  return text.replace(/\[citation:(\d+)\]/g, "[$1]");
}

// ---------------- SSE helpers ----------------

function parseBlock(block) {
  let data = "";
  for (const raw of block.split(/\r?\n/)) {
    if (raw.startsWith("data:")) data += raw.slice(5).replace(/^\s/, "") + "\n";
  }
  return data.trim();
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
      if (block.trim()) {
        const data = parseBlock(block);
        if (data) yield data;
      }
    }
  }
  if (pending.trim()) {
    const data = parseBlock(pending);
    if (data) yield data;
  }
}

// ---------------- auto-continue state ----------------
// Mirrors ds2api's continueState: captures response_message_id (top-level or in a
// response object) and watches response/status for INCOMPLETE / AUTO_CONTINUE.

class ContinueState {
  constructor() {
    this.responseMessageId = 0;
    this.lastStatus = "";
    this.finished = false;
  }

  observe(data) {
    if (!data || data === "[DONE]") return;
    let chunk;
    try {
      chunk = JSON.parse(data);
    } catch {
      return;
    }
    if (typeof chunk !== "object" || chunk === null) return;
    if (Number.isInteger(chunk.response_message_id) && chunk.response_message_id > 0) {
      this.responseMessageId = chunk.response_message_id;
    }
    this.observeDirect(chunk.p, chunk.v);
    if (chunk.p === "response") this.observeBatch("response", chunk.v);
    else this.observeBatch("", chunk.v);
    if (chunk.v && typeof chunk.v === "object") this.observeResponse(chunk.v.response);
    if (chunk.message && typeof chunk.message === "object") this.observeResponse(chunk.message.response);
  }

  observeDirect(p, v) {
    const path = String(p || "").replace(/^\/+|\/+$/g, "");
    if (path === "response/status" || path === "status" || path === "response/quasi_status" || path === "quasi_status") {
      this.setStatus(typeof v === "string" ? v : "");
    } else if (path === "response/auto_continue" || path === "auto_continue") {
      if (v === true) this.lastStatus = "AUTO_CONTINUE";
    }
  }

  observeResponse(raw) {
    if (!raw || typeof raw !== "object") return;
    if (Number.isInteger(raw.message_id) && raw.message_id > 0) this.responseMessageId = raw.message_id;
    this.setStatus(String(raw.status || ""));
    if (raw.auto_continue === true) this.lastStatus = "AUTO_CONTINUE";
  }

  observeBatch(parentPath, raw) {
    if (!Array.isArray(raw)) return;
    const parent = String(parentPath || "").replace(/^\/+|\/+$/g, "");
    for (const m of raw) {
      if (!m || typeof m !== "object") continue;
      const p = String(m.p || "").trim();
      const full = p.includes("/") ? p : parent ? `${parent}/${p}` : p;
      const path = full.replace(/^\/+|\/+$/g, "");
      if (path === "response/status" || path === "status" || path === "response/quasi_status" || path === "quasi_status") {
        this.setStatus(typeof m.v === "string" ? m.v : "");
      } else if (path === "response/auto_continue" || path === "auto_continue") {
        if (m.v === true) this.lastStatus = "AUTO_CONTINUE";
      }
    }
  }

  setStatus(status) {
    const s = String(status || "").trim();
    if (!s) return;
    this.lastStatus = s;
    if (s.toUpperCase() === "FINISHED" || s.toUpperCase() === "CONTENT_FILTER") this.finished = true;
  }

  shouldContinue() {
    if (this.finished || this.responseMessageId <= 0) return false;
    const s = this.lastStatus.toUpperCase();
    return s === "INCOMPLETE" || s === "AUTO_CONTINUE";
  }
}

// ---------------- chat ----------------

async function performCompletion(accessToken, powAnswer, payload, signal) {
  return fetch(COMPLETION_URL, {
    method: "POST",
    headers: {
      ...FAKE_HEADERS,
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
      "X-Ds-Pow-Response": powAnswer,
      "X-Client-Timezone-Offset": String(new Date().getTimezoneOffset() * -60),
      Cookie: fakeCookie(),
    },
    body: JSON.stringify(payload),
    signal: signal ?? undefined,
  });
}

async function performContinue(accessToken, powAnswer, sessionId, messageId, signal) {
  return fetch(CONTINUE_URL, {
    method: "POST",
    headers: {
      ...FAKE_HEADERS,
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
      "X-Ds-Pow-Response": powAnswer,
      "X-Client-Timezone-Offset": String(new Date().getTimezoneOffset() * -60),
      Cookie: fakeCookie(),
    },
    body: JSON.stringify({
      chat_session_id: sessionId,
      message_id: messageId,
      fallback_to_resume: true,
    }),
    signal: signal ?? undefined,
  });
}

// Stream one DeepSeek SSE body, translating to OpenAI chunks. Returns the continue
// state (response_message_id + status) captured along the way.
async function streamRound(body, opts) {
  const { model, base, emit, isThinking } = opts;
  const state = new ContinueState();
  let currentPath = "";
  const searchResults = [];

  const sendByPath = (raw) => {
    const text = formatStreamContent(raw, model);
    if (!text) return;
    let path = currentPath;
    if (!path && isThinking) path = "thinking";
    else if (!path && isSearchModel(model)) path = "content";
    if (path === "thinking") emit({ reasoning_content: text });
    else emit({ content: text });
  };

  const handleFragment = (frag, setPathFromType) => {
    if (!frag || typeof frag !== "object") return;
    const type = String(frag.type || "").toUpperCase();
    if (setPathFromType || type) {
      if (type === "THINK") currentPath = "thinking";
      else if (type === "ANSWER" || type === "RESPONSE") currentPath = "content";
    }
    if (typeof frag.content === "string" && frag.content.length) sendByPath(frag.content);
  };

  for await (const data of iterateSSE(body)) {
    if (data === "[DONE]") break;
    state.observe(data);
    let chunk;
    try {
      chunk = JSON.parse(data);
    } catch {
      continue;
    }
    if (typeof chunk !== "object" || chunk === null) continue;
    const p = chunk.p;
    const o = chunk.o;
    const v = chunk.v;

    if (v && typeof v === "object" && v.response) {
      if (v.response.thinking_enabled === true) currentPath = "thinking";
      else if (v.response.thinking_enabled === false) currentPath = "content";
      if (Array.isArray(v.response.fragments)) {
        for (const frag of v.response.fragments) handleFragment(frag, false);
      }
    }

    if (p === "response/fragments") {
      if (Array.isArray(v)) {
        for (const frag of v) handleFragment(frag, true);
      } else if (v && typeof v === "object") {
        handleFragment(v, true);
      }
    }

    if (p === "response" && Array.isArray(v)) {
      for (const entry of v) {
        if (entry?.p === "response" && entry?.v?.thinking_enabled === true) currentPath = "thinking";
      }
    }

    if (p === "response/search_status") continue;

    if (p === "response/search_results" && Array.isArray(v)) {
      if (o !== "BATCH") {
        searchResults.length = 0;
        searchResults.push(...v);
      } else {
        for (const op of v) {
          const m = String(op?.p || "").match(/^(\d+)\/cite_index$/);
          if (m) {
            const idx = parseInt(m[1], 10);
            if (searchResults[idx]) searchResults[idx].cite_index = op.v;
          }
        }
      }
      continue;
    }

    if (typeof v === "string") {
      sendByPath(v);
    } else if (Array.isArray(v) && p === "response") {
      for (const entry of v) {
        if (Array.isArray(entry?.v)) {
          const joined = entry.v.map((item) => (item && item.content) || "").join("");
          if (joined) sendByPath(joined);
        }
      }
    }

    if (p === "response/status" && v === "FINISHED") {
      // keep draining briefly - search_results may still arrive
    }
  }

  // append search citations (like the gateway executor)
  if (searchResults.length && !String(model).toLowerCase().includes("search-silent")) {
    const citations = searchResults
      .filter((r) => r.cite_index)
      .sort((a, b) => (a.cite_index || 0) - (b.cite_index || 0))
      .map((r) => `[${r.cite_index}]: [${r.title}](${r.url})`)
      .join("\n");
    if (citations) emit({ content: `\n\n${citations}` });
  }

  return state;
}

async function handleChat(req, res, body) {
  const model = typeof body.model === "string" && body.model ? body.model : "deepseek-chat";
  const messages = Array.isArray(body.messages) ? body.messages : [];
  const stream = body.stream === true || body.stream === "true";

  // auth: Authorization header wins, else the cookie file
  let userToken = null;
  const auth = String(req.headers.authorization || "");
  if (/^Bearer\s+/i.test(auth)) userToken = extractUserToken(auth.replace(/^Bearer\s+/i, "").trim());
  if (!userToken) userToken = loadCookies();
  if (!userToken) {
    return sendJson(res, 401, {
      error: {
        message:
          "No DeepSeek userToken. Sign in at chat.deepseek.com, then Cookie Pusher -> Grab & push sessions.",
        type: "authentication_error",
      },
    });
  }

  const prompt = messagesToPrompt(messages).trim();
  if (!prompt) return sendJson(res, 400, { error: { message: "no user message", type: "invalid_request_error" } });
  const finalPrompt = prompt.length > MAX_QUERY ? prompt.slice(-MAX_QUERY) : prompt;

  const { modelType, thinkingEnabled, searchEnabled } = resolveModelOptions(model, body);

  let accessToken, sessionId, powAnswer;
  try {
    accessToken = await acquireAccessToken(userToken);
  } catch (e) {
    return sendJson(res, 401, { error: { message: e.message, type: "authentication_error" } });
  }
  try {
    sessionId = await createSession(accessToken);
  } catch (e) {
    return sendJson(res, 502, { error: { message: `session create failed: ${e.message}`, type: "upstream_error" } });
  }
  const cleanup = () => deleteSession(accessToken, sessionId).catch(() => {});

  try {
    const powChallenge = await getPowChallenge(accessToken);
    powAnswer = await solvePow(powChallenge);
  } catch (e) {
    cleanup();
    return sendJson(res, 502, { error: { message: `PoW failed: ${e.message}`, type: "upstream_error" } });
  }

  const payload = {
    chat_session_id: sessionId,
    parent_message_id: null,
    model_type: modelType,
    prompt: finalPrompt,
    ref_file_ids: [],
    thinking_enabled: thinkingEnabled,
    search_enabled: searchEnabled,
    preempt: false,
  };

  let first;
  try {
    first = await performCompletion(accessToken, powAnswer, payload);
  } catch (e) {
    cleanup();
    return sendJson(res, 502, { error: { message: `upstream unreachable: ${e.message}`, type: "upstream_error" } });
  }

  if (!first.ok || !first.body) {
    const text = await first.text().catch(() => "");
    cleanup();
    log(`completion HTTP ${first.status}: ${text.slice(0, 200)}`);
    const status = first.status === 401 || first.status === 403 ? 401 : 502;
    return sendJson(res, status, {
      error: {
        message:
          status === 401
            ? "DeepSeek session expired - grab cookies again (Cookie Pusher)."
            : `DeepSeek upstream ${first.status}: ${text.slice(0, 160)}`,
        type: status === 401 ? "authentication_error" : "upstream_error",
      },
    });
  }

  const id = "chatcmpl-" + uuid();
  const created = Math.floor(Date.now() / 1000);
  const isThinking = isThinkingModel(model);
  const base = { id, object: "chat.completion.chunk", created, model };

  if (stream) {
    res.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
      "X-Accel-Buffering": "no",
    });
    const emit = (delta) => {
      res.write(`data: ${JSON.stringify({ ...base, choices: [{ index: 0, delta, finish_reason: null }] })}\n\n`);
    };
    try {
      let current = first;
      let rounds = 0;
      for (;;) {
        const state = await streamRound(current.body, { model, base, emit, isThinking });
        if (state.shouldContinue() && rounds < MAX_CONTINUE_ROUNDS) {
          rounds++;
          log(`auto-continue round ${rounds}/${MAX_CONTINUE_ROUNDS} (message_id=${state.responseMessageId}, status=${state.lastStatus})`);
          let next;
          try {
            next = await performContinue(accessToken, powAnswer, sessionId, state.responseMessageId);
          } catch (e) {
            log(`continue request failed: ${e.message}`);
            break;
          }
          if (!next.ok || !next.body) {
            log(`continue HTTP ${next ? next.status : "?"}`);
            break;
          }
          current = next;
          continue;
        }
        break;
      }
    } catch (e) {
      log("stream error:", e.message);
    }
    emit({}, "stop");
    res.write("data: [DONE]\n\n");
    res.end();
    cleanup();
    return;
  }

  // non-stream
  let content = "";
  let reasoning = "";
  const collect = (delta) => {
    if (delta.content) content += delta.content;
    if (delta.reasoning_content) reasoning += delta.reasoning_content;
  };
  try {
    let current = first;
    let rounds = 0;
    for (;;) {
      const state = await streamRound(current.body, { model, base, emit: collect, isThinking });
      if (state.shouldContinue() && rounds < MAX_CONTINUE_ROUNDS) {
        rounds++;
        log(`auto-continue round ${rounds}/${MAX_CONTINUE_ROUNDS} (message_id=${state.responseMessageId}, status=${state.lastStatus})`);
        let next;
        try {
          next = await performContinue(accessToken, powAnswer, sessionId, state.responseMessageId);
        } catch {
          break;
        }
        if (!next.ok || !next.body) break;
        current = next;
        continue;
      }
      break;
    }
  } catch (e) {
    log("non-stream error:", e.message);
  }
  cleanup();
  const message = { role: "assistant", content };
  if (reasoning) message.reasoning_content = reasoning;
  sendJson(res, 200, {
    id,
    object: "chat.completion",
    created,
    model,
    choices: [{ index: 0, message, finish_reason: "stop" }],
  });
}

// ---------------- HTTP server ----------------

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, `http://${req.headers.host || "localhost"}`);
    const pathname = url.pathname.replace(/\/+$/, "") || "/";
    if (req.method === "GET" && (pathname === "/v1/models" || pathname === "/models")) {
      sendJson(res, 200, {
        object: "list",
        data: MODELS.map((m) => ({ id: m.id, object: "model", owned_by: "deepseek", created: 0, name: m.name })),
      });
      return;
    }
    if (req.method === "GET" && pathname === "/healthz") {
      sendJson(res, 200, { ok: true });
      return;
    }
    if (req.method === "POST" && pathname === "/v1/cookies") {
      const body = await readJson(req);
      const raw =
        body && typeof body.userToken === "string"
          ? { userToken: body.userToken }
          : body && body.cookies && typeof body.cookies === "object"
            ? body.cookies
            : body && body.token
              ? { userToken: body.token }
              : null;
      const token = raw && extractUserToken(raw.userToken || raw.token || "");
      if (!token) {
        return sendJson(res, 400, { error: "send {userToken:'...'} or {cookies:{userToken:'...'}}" });
      }
      fs.writeFileSync(COOKIE_FILE, JSON.stringify({ userToken: token, syncedAt: new Date().toISOString() }, null, 2));
      tokenCache.delete(token); // force a fresh access token on next chat
      log(`userToken updated -> ${COOKIE_FILE}`);
      sendJson(res, 200, { ok: true });
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

server.listen(PORT, HOST, () =>
  log(`deepseek-web-bridge listening on http://${HOST}:${PORT} (auto-continue on, ${MAX_CONTINUE_ROUNDS} rounds)`)
);
