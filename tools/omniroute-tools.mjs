#!/usr/bin/env node
// omniroute-tools.mjs — Unified MCP server for all OmniRoute bridges
// Provides a single entry point for Claude Code to access all tools:
//   - Image generation (Gemini Flow, MiMo)
//   - Chat with specific providers (Meta, MiMo, DeepSeek, Qwen)
//   - Web search via provider-specific search endpoints
//   - Provider health checks
//   - Bridge management
//
// Usage: node omniroute-tools.mjs (stdio MCP transport)
// Or:    node omniroute-tools.mjs --http (HTTP transport on port 20140)

import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const GW = process.env.OMNIROUTE_BASE_URL || "http://127.0.0.1:20128";
const TOKEN = process.env.OMNIROUTE_API_KEY || "omniroute";
const DATA_DIR = process.env.DATA_DIR || path.join(os.homedir(), ".omniroute");
const LOG_FILE = path.join(DATA_DIR, "omniroute-tools.log");

function log(...args) {
  const line = `[${new Date().toISOString()}] ${args.join(" ")}`;
  try { fs.appendFileSync(LOG_FILE, line + "\n"); } catch {}
}

// ─── Tool definitions ───

const TOOLS = [
  {
    name: "omniroute_chat",
    description: "Chat with any OmniRoute provider. Routes to the best available model.",
    inputSchema: {
      type: "object",
      properties: {
        message: { type: "string", description: "The user message" },
        model: { type: "string", description: "Model route (e.g., auto/best-coding, combo/qwen, mistral/mistral-large-latest)", default: "auto/coding:reliable" },
        stream: { type: "boolean", description: "Stream the response", default: false },
      },
      required: ["message"],
    },
  },
  {
    name: "omniroute_image",
    description: "Generate images using Gemini Flow (Nano Banana) or MiMo. Returns base64 image data.",
    inputSchema: {
      type: "object",
      properties: {
        prompt: { type: "string", description: "Image description" },
        model: { type: "string", description: "Image model (flowui/nano-banana-2, flowui/imagen-4)", default: "flowui/nano-banana-2" },
        size: { type: "string", description: "Image size (1792x1024, 1536x1024, 1024x1024)", default: "1024x1024" },
        n: { type: "number", description: "Number of images", default: 1 },
      },
      required: ["prompt"],
    },
  },
  {
    name: "omniroute_search",
    description: "Search the web via provider-specific search endpoints (DeepSeek Search, Qwen, etc.)",
    inputSchema: {
      type: "object",
      properties: {
        query: { type: "string", description: "Search query" },
        provider: { type: "string", description: "Search provider (deepseek, qwen, auto)", default: "auto" },
      },
      required: ["query"],
    },
  },
  {
    name: "omniroute_health",
    description: "Check health of all OmniRoute providers and bridges",
    inputSchema: {
      type: "object",
      properties: {
        detail: { type: "boolean", description: "Show detailed status", default: false },
      },
    },
  },
  {
    name: "omniroute_bridge_status",
    description: "Check status of all running bridges",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "omniroute_model_list",
    description: "List all available models/routes from the gateway",
    inputSchema: {
      type: "object",
      properties: {
        filter: { type: "string", description: "Filter by prefix (auto, combo, mistral, etc.)" },
      },
    },
  },
];

// ─── Tool implementations ───

async function chat({ message, model, stream }) {
  const res = await fetch(`${GW}/v1/chat/completions`, {
    method: "POST",
    headers: { "Authorization": `Bearer ${TOKEN}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: model || "auto/coding:reliable",
      messages: [{ role: "user", content: message }],
      stream: stream || false,
    }),
    signal: AbortSignal.timeout(60000),
  });
  const data = await res.json();
  if (data.error) throw new Error(data.error.message || JSON.stringify(data.error));
  return data.choices?.[0]?.message?.content || JSON.stringify(data);
}

async function image({ prompt, model, size, n }) {
  const res = await fetch(`${GW}/v1/images/generations`, {
    method: "POST",
    headers: { "Authorization": `Bearer ${TOKEN}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: model || "flowui/nano-banana-2",
      prompt,
      size: size || "1024x1024",
      n: n || 1,
    }),
    signal: AbortSignal.timeout(120000),
  });
  const data = await res.json();
  if (data.error) throw new Error(data.error.message || JSON.stringify(data.error));
  return `Generated ${data.data?.length || 0} image(s). First image URL: ${data.data?.[0]?.url || "no URL"}`;
}

async function search({ query, provider }) {
  // Use deepseek-web search or qwen-web search
  const model = provider === "qwen" ? "qwen-web/qwen3.8-max" : "deepseek-web/DeepSeek-Search";
  const res = await fetch(`${GW}/v1/chat/completions`, {
    method: "POST",
    headers: { "Authorization": `Bearer ${TOKEN}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model,
      messages: [{ role: "user", content: query }],
      stream: false,
    }),
    signal: AbortSignal.timeout(30000),
  });
  const data = await res.json();
  if (data.error) throw new Error(data.error.message || JSON.stringify(data.error));
  return data.choices?.[0]?.message?.content || "No results";
}

async function health({ detail }) {
  const providers = [
    "auto/best-coding", "mistral/mistral-large-latest", "cohere/c4ai-aya-expanse-32b",
    "hf/CohereLabs/aya-expanse-32b", "qwen-web/qwen3.8-max", "combo/deepseek",
  ];
  const results = [];
  for (const route of providers) {
    try {
      const start = Date.now();
      const res = await fetch(`${GW}/v1/chat/completions`, {
        method: "POST",
        headers: { "Authorization": `Bearer ${TOKEN}`, "Content-Type": "application/json" },
        body: JSON.stringify({ model: route, messages: [{ role: "user", content: "PING" }], max_tokens: 5, stream: false }),
        signal: AbortSignal.timeout(15000),
      });
      const elapsed = ((Date.now() - start) / 1000).toFixed(1);
      if (res.ok) results.push(`✅ ${route} (${elapsed}s)`);
      else results.push(`❌ ${route} (HTTP ${res.status})`);
    } catch (e) {
      results.push(`❌ ${route} (${e.message.substring(0, 30)})`);
    }
  }
  return results.join("\n");
}

async function bridgeStatus() {
  const bridges = [
    { name: "Gemini Bridge", port: 20133, path: "/health" },
    { name: "FlowUI Bridge", port: 20134, path: "/" },
    { name: "MiMo Web Bridge", port: 20135, path: "/healthz" },
    { name: "Meta Web Bridge", port: 20136, path: "/healthz" },
  ];
  const results = [];
  for (const b of bridges) {
    try {
      const res = await fetch(`http://127.0.0.1:${b.port}${b.path}`, { signal: AbortSignal.timeout(3000) });
      results.push(`✅ ${b.name} (port ${b.port})`);
    } catch {
      results.push(`❌ ${b.name} (port ${b.port} - not running)`);
    }
  }
  return results.join("\n");
}

async function modelList({ filter }) {
  const res = await fetch(`${GW}/v1/models`, {
    headers: { "Authorization": `Bearer ${TOKEN}` },
    signal: AbortSignal.timeout(10000),
  });
  const data = await res.json();
  let models = (data.data || []).map(m => m.id);
  if (filter) models = models.filter(m => m.startsWith(filter + "/") || m.startsWith(filter + ":"));
  return `Found ${models.length} models${filter ? ` matching "${filter}"` : ""}:\n${models.slice(0, 50).join("\n")}${models.length > 50 ? `\n... +${models.length - 50} more` : ""}`;
}

// ─── MCP Server ───

const HANDLERS = {
  omniroute_chat: chat,
  omniroute_image: image,
  omniroute_search: search,
  omniroute_health: health,
  omniroute_bridge_status: bridgeStatus,
  omniroute_model_list: modelList,
};

// Stdio MCP transport
let inputBuffer = "";

process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  inputBuffer += chunk;
  while (true) {
    const headerEnd = inputBuffer.indexOf("\r\n\r\n");
    if (headerEnd === -1) break;
    const header = inputBuffer.substring(0, headerEnd);
    const contentLengthMatch = header.match(/Content-Length:\s*(\d+)/i);
    if (!contentLengthMatch) { inputBuffer = inputBuffer.substring(headerEnd + 4); continue; }
    const contentLength = parseInt(contentLengthMatch[1]);
    const bodyStart = headerEnd + 4;
    if (inputBuffer.length < bodyStart + contentLength) break;
    const body = inputBuffer.substring(bodyStart, bodyStart + contentLength);
    inputBuffer = inputBuffer.substring(bodyStart + contentLength);
    try { handleMessage(JSON.parse(body)); } catch (e) { log("Error:", e.message); }
  }
});

async function handleMessage(msg) {
  const { id, method, params } = msg;

  if (method === "initialize") {
    send({ jsonrpc: "2.0", id, result: {
      protocolVersion: "2024-11-05",
      capabilities: { tools: {} },
      serverInfo: { name: "omniroute-tools", version: "1.0.0" },
    }});
    return;
  }

  if (method === "notifications/initialized") return;

  if (method === "tools/list") {
    send({ jsonrpc: "2.0", id, result: { tools: TOOLS } });
    return;
  }

  if (method === "tools/call") {
    const { name, arguments: args } = params;
    const handler = HANDLERS[name];
    if (!handler) {
      send({ jsonrpc: "2.0", id, result: { content: [{ type: "text", text: `Unknown tool: ${name}` }], isError: true } });
      return;
    }
    try {
      const result = await handler(args || {});
      send({ jsonrpc: "2.0", id, result: { content: [{ type: "text", text: result }] } });
    } catch (e) {
      log(`Tool ${name} error:`, e.message);
      send({ jsonrpc: "2.0", id, result: { content: [{ type: "text", text: `Error: ${e.message}` }], isError: true } });
    }
    return;
  }

  send({ jsonrpc: "2.0", id, error: { code: -32601, message: `Method not found: ${method}` } });
}

function send(msg) {
  const body = JSON.stringify(msg);
  const header = `Content-Length: ${Buffer.byteLength(body)}\r\n\r\n`;
  process.stdout.write(header + body);
}

log("omniroute-tools MCP server started");
