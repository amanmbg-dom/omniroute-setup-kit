#!/usr/bin/env node
// claude-desktop-proxy.mjs — Translates Claude Desktop's Anthropic Messages API
// into OpenAI Chat Completions format and forwards to OmniRoute (port 20128).
//
// Claude Desktop → this proxy (10150) → OmniRoute (20128) → free bridges
//
// Zero dependencies: Node 18+ (node:http + global fetch).

import http from "node:http";
import crypto from "node:crypto";

const PORT = parseInt(process.env.PROXY_PORT || "10150", 10);
const UPSTREAM = process.env.UPSTREAM_URL || "http://127.0.0.1:20128";
const API_KEY = process.env.UPSTREAM_KEY || "omniroute";
const uuid = () => crypto.randomUUID();

function log(...args) {
  console.log(`[${new Date().toISOString()}]`, ...args);
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    let data = "";
    req.on("data", (c) => (data += c));
    req.on("end", () => {
      try { resolve(JSON.parse(data || "{}")); }
      catch (e) { reject(e); }
    });
  });
}

function sendJson(res, status, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(status, {
    "Content-Type": "application/json",
    "Content-Length": Buffer.byteLength(body),
  });
  res.end(body);
}

// ── Anthropic Messages → OpenAI Chat ─────────────────────────────

function anthropicToOpenAI(anthropicBody) {
  const messages = [];

  // System message
  if (anthropicBody.system) {
    const sysText = typeof anthropicBody.system === "string"
      ? anthropicBody.system
      : anthropicBody.system.map(b => b.text || "").join("\n");
    messages.push({ role: "system", content: sysText });
  }

  // Conversation messages
  for (const msg of anthropicBody.messages || []) {
    if (msg.role === "user" || msg.role === "assistant") {
      // Handle content blocks (text + images)
      if (Array.isArray(msg.content)) {
        const textParts = msg.content
          .filter(b => b.type === "text")
          .map(b => b.text);
        messages.push({ role: msg.role, content: textParts.join("\n") });
      } else {
        messages.push({ role: msg.role, content: msg.content });
      }
    }
  }

  // Rewrite Claude Desktop model names to OmniRoute-compatible names
  const rawModel = anthropicBody.model || "auto/coding:reliable";
  const model = rawModel.startsWith("claude-") ? "auto/coding:reliable" : rawModel;

  return {
    model,
    messages,
    max_tokens: anthropicBody.max_tokens || 4096,
    temperature: anthropicBody.temperature,
    stream: !!anthropicBody.stream,
  };
}

// ── OpenAI Chat → Anthropic Messages ─────────────────────────────

function openAIToAnthropic(openaiResp, model) {
  const choice = openaiResp.choices?.[0];
  const content = choice?.message?.content || "";
  return {
    id: openaiResp.id || `msg_${uuid().replace(/-/g, "")}`,
    type: "message",
    role: "assistant",
    content: [{ type: "text", text: content }],
    model: model,
    stop_reason: choice?.finish_reason === "stop" ? "end_turn" : "end_turn",
    stop_sequence: null,
    usage: {
      input_tokens: openaiResp.usage?.prompt_tokens || 0,
      output_tokens: openaiResp.usage?.completion_tokens || 0,
    },
  };
}

// ── SSE Stream Translation ───────────────────────────────────────

async function handleStream(anthropicBody, res) {
  const openaiBody = anthropicToOpenAI({ ...anthropicBody, stream: true });

  res.writeHead(200, {
    "Content-Type": "text/event-stream",
    "Cache-Control": "no-cache",
    "Connection": "keep-alive",
  });

  const write = (data) => {
    res.write(`event: ${data.event}\ndata: ${JSON.stringify(data.data)}\n\n`);
  };

  // message_start
  write({
    event: "message_start",
    data: {
      type: "message_start",
      message: {
        id: `msg_${uuid().replace(/-/g, "")}`,
        type: "message",
        role: "assistant",
        content: [],
        model: anthropicBody.model,
        stop_reason: null,
        stop_sequence: null,
        usage: { input_tokens: 0, output_tokens: 0 },
      },
    },
  });

  try {
    const response = await fetch(`${UPSTREAM}/v1/chat/completions`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${API_KEY}`,
      },
      body: JSON.stringify(openaiBody),
      signal: AbortSignal.timeout(120000),
    });

    if (!response.ok) {
      const errText = await response.text().catch(() => "upstream error");
      write({ event: "error", data: { type: "error", error: { type: "api_error", message: errText.slice(0, 200) } } });
      write({ event: "message_stop", data: { type: "message_stop" } });
      res.end();
      return;
    }

    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";
    let started = false;

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });

      const lines = buffer.split("\n");
      buffer = lines.pop() || "";

      for (const line of lines) {
        if (!line.startsWith("data: ")) continue;
        const payload = line.slice(6).trim();
        if (payload === "[DONE]") continue;

        try {
          const chunk = JSON.parse(payload);
          const delta = chunk.choices?.[0]?.delta;
          if (delta?.content) {
            if (!started) {
              write({ event: "content_block_start", data: { type: "content_block_start", index: 0, content_block: { type: "text", text: "" } } });
              started = true;
            }
            write({ event: "content_block_delta", data: { type: "content_block_delta", index: 0, delta: { type: "text_delta", text: delta.content } } });
          }
          if (chunk.choices?.[0]?.finish_reason) {
            write({ event: "content_block_stop", data: { type: "content_block_stop", index: 0 } });
          }
        } catch {}
      }
    }
  } catch (e) {
    write({ event: "error", data: { type: "error", error: { type: "api_error", message: e.message } } });
  }

  write({ event: "message_delta", data: { type: "message_delta", delta: { stop_reason: "end_turn", stop_sequence: null }, usage: { output_tokens: 0 } } });
  write({ event: "message_stop", data: { type: "message_stop" } });
  res.end();
}

// ── HTTP Server ──────────────────────────────────────────────────

const server = http.createServer(async (req, res) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    res.writeHead(204, {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, x-api-key, anthropic-version, anthropic-model",
    });
    return res.end();
  }

  // Health check
  if (req.url === "/healthz") {
    return sendJson(res, 200, { ok: true, proxy: "claude-desktop", port: PORT, upstream: UPSTREAM });
  }

  // Only accept POST to /v1/messages
  if (req.method === "POST" && req.url === "/v1/messages") {
    try {
      const body = await readJson(req);
      const model = body.model || "auto/coding:reliable";
      log(`Request: model=${model} stream=${!!body.stream} max_tokens=${body.max_tokens}`);

      if (body.stream) {
        return await handleStream(body, res);
      }

      // Non-streaming: request with stream:false, but OmniRoute may still
      // return SSE, so we collect the full response from the stream.
      const openaiBody = anthropicToOpenAI(body);
      openaiBody.stream = false;
      const response = await fetch(`${UPSTREAM}/v1/chat/completions`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${API_KEY}`,
        },
        body: JSON.stringify(openaiBody),
        signal: AbortSignal.timeout(120000),
      });

      const rawText = await response.text();
      let openaiResp;
      try {
        openaiResp = JSON.parse(rawText);
      } catch {
        // OmniRoute returned SSE — assemble from chunks
        let fullContent = "";
        let model = "unknown";
        for (const line of rawText.split("\n")) {
          if (!line.startsWith("data: ")) continue;
          const payload = line.slice(6).trim();
          if (payload === "[DONE]") continue;
          try {
            const chunk = JSON.parse(payload);
            model = chunk.model || model;
            const delta = chunk.choices?.[0]?.delta;
            if (delta?.content) fullContent += delta.content;
          } catch {}
        }
        openaiResp = {
          choices: [{ message: { content: fullContent }, finish_reason: "stop" }],
          model,
          usage: { prompt_tokens: 0, completion_tokens: 0 },
        };
      }
      if (openaiResp.error) {
        return sendJson(res, 502, {
          type: "error",
          error: { type: "api_error", message: openaiResp.error.message || "upstream error" },
        });
      }

      const anthropicResp = openAIToAnthropic(openaiResp, model);
      log(`Response: ${anthropicResp.content[0]?.text?.slice(0, 80) || "(empty)"}`);
      sendJson(res, 200, anthropicResp);
    } catch (e) {
      log(`Error: ${e.message}`);
      sendJson(res, 500, {
        type: "error",
        error: { type: "api_error", message: e.message },
      });
    }
    return;
  }

  sendJson(res, 404, { type: "error", error: { type: "not_found", message: `Unknown route: ${req.method} ${req.url}` } });
});

server.listen(PORT, "127.0.0.1", () => {
  log(`claude-desktop-proxy listening on http://127.0.0.1:${PORT}`);
  log(`Upstream: ${UPSTREAM}`);
  log(`Claude Desktop should set ANTHROPIC_BASE_URL=http://127.0.0.1:${PORT}`);
});
