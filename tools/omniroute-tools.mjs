#!/usr/bin/env node
// omniroute-tools.mjs — Unified MCP server for all OmniRoute bridges and tools
// v2: Verifies all bridges, includes deepseek-web (gateway-native), lists all skills
//
// Tools:
//   omniroute_chat          — Chat with any provider
//   omniroute_image         — Generate images (Gemini Flow, Nano Banana, Imagen 4)
//   omniroute_search        — Web search via DeepSeek/Qwen
//   omniroute_health        — Check all provider health
//   omniroute_bridge_status — Check ALL bridges + gateway status
//   omniroute_model_list    — List all available models
//   omniroute_skills_list   — List all installed skills

import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const GW = process.env.OMNIROUTE_BASE_URL || "http://127.0.0.1:20128";
const TOKEN = process.env.OMNIROUTE_API_KEY || "omniroute";
const DATA_DIR = process.env.DATA_DIR || path.join(os.homedir(), ".omniroute");
const SKILLS_DIR = path.join(os.homedir(), ".claude", "skills");
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
        model: { type: "string", description: "Model route (e.g., auto/best-coding, combo/qwen, deepseek-web/DeepSeek-V4-Flash)", default: "auto/coding:reliable" },
        stream: { type: "boolean", description: "Stream the response", default: false },
      },
      required: ["message"],
    },
  },
  {
    name: "omniroute_image",
    description: "Generate images using Gemini Flow (Nano Banana) or Imagen 4.",
    inputSchema: {
      type: "object",
      properties: {
        prompt: { type: "string", description: "Image description" },
        model: { type: "string", description: "Image model (flowui/nano-banana-2, flowui/imagen-4)", default: "flowui/nano-banana-2" },
        size: { type: "string", description: "Image size", default: "1024x1024" },
        n: { type: "number", description: "Number of images", default: 1 },
      },
      required: ["prompt"],
    },
  },
  {
    name: "omniroute_search",
    description: "Search the web via DeepSeek Search, Qwen, or DeepSeek R1.",
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
    inputSchema: { type: "object", properties: {
      detail: { type: "boolean", description: "Show detailed status", default: false },
    }},
  },
  {
    name: "omniroute_bridge_status",
    description: "Check status of ALL bridges: gateway, gflow, flowui, mimo-web, meta-web, deepseek-web (gateway-native)",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "omniroute_model_list",
    description: "List all available models/routes from the gateway",
    inputSchema: { type: "object", properties: {
      filter: { type: "string", description: "Filter by prefix (auto, combo, mistral, deepseek-web, etc.)" },
    }},
  },
  {
    name: "omniroute_skills_list",
    description: "List all installed Claude Code skills from ~/.claude/skills/",
    inputSchema: { type: "object", properties: {
      filter: { type: "string", description: "Filter skills by name substring" },
    }},
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
    body: JSON.stringify({ model: model || "flowui/nano-banana-2", prompt, size: size || "1024x1024", n: n || 1 }),
    signal: AbortSignal.timeout(120000),
  });
  const data = await res.json();
  if (data.error) throw new Error(data.error.message || JSON.stringify(data.error));
  return `Generated ${data.data?.length || 0} image(s). URL: ${data.data?.[0]?.url || "no URL"}`;
}

async function search({ query, provider }) {
  const model = provider === "qwen" ? "qwen-web/qwen3.8-max" : "deepseek-web/DeepSeek-Search";
  const res = await fetch(`${GW}/v1/chat/completions`, {
    method: "POST",
    headers: { "Authorization": `Bearer ${TOKEN}`, "Content-Type": "application/json" },
    body: JSON.stringify({ model, messages: [{ role: "user", content: query }], stream: false }),
    signal: AbortSignal.timeout(30000),
  });
  const data = await res.json();
  if (data.error) throw new Error(data.error.message || JSON.stringify(data.error));
  return data.choices?.[0]?.message?.content || "No results";
}

async function health({ detail }) {
  const results = [];

  // Check gateway
  try {
    const start = Date.now();
    const res = await fetch(`${GW}/v1/models`, {
      headers: { "Authorization": `Bearer ${TOKEN}` },
      signal: AbortSignal.timeout(10000),
    });
    const elapsed = ((Date.now() - start) / 1000).toFixed(1);
    const data = await res.json();
    results.push(`✅ Gateway (port 20128) — ${data.data?.length || 0} models (${elapsed}s)`);
  } catch (e) {
    results.push(`❌ Gateway (port 20128) — ${e.message.substring(0, 50)}`);
  }

  // Check key routes
  const routes = ["auto/best-coding", "combo/deepseek", "combo/qwen", "deepseek-web/DeepSeek-V4-Flash", "mistral/mistral-large-latest"];
  for (const route of routes) {
    try {
      const start = Date.now();
      const res = await fetch(`${GW}/v1/chat/completions`, {
        method: "POST",
        headers: { "Authorization": `Bearer ${TOKEN}`, "Content-Type": "application/json" },
        body: JSON.stringify({ model: route, messages: [{ role: "user", content: "PING" }], max_tokens: 5 }),
        signal: AbortSignal.timeout(15000),
      });
      const elapsed = ((Date.now() - start) / 1000).toFixed(1);
      if (res.ok) results.push(`  ✅ ${route} (${elapsed}s)`);
      else results.push(`  ❌ ${route} (HTTP ${res.status})`);
    } catch (e) {
      results.push(`  ❌ ${route} (${e.message.substring(0, 30)})`);
    }
  }
  return results.join("\n");
}

async function bridgeStatus() {
  const bridges = [
    { name: "Gateway", port: 20128, path: "/", expect: [200, 307] },
    { name: "gflow (Gemini Bridge)", port: 20133, path: "/health", expect: [200] },
    { name: "FlowUI Bridge", port: 20134, path: "/health", expect: [200, 404] },
    { name: "MiMo Web Bridge", port: 20135, path: "/healthz", expect: [200] },
    { name: "Meta Web Bridge", port: 20136, path: "/healthz", expect: [200] },
    { name: "DeepSeek Web (gateway-native)", port: 20128, path: "/v1/models", expect: [200] },
  ];

  const results = [];
  for (const b of bridges) {
    try {
      const res = await fetch(`http://127.0.0.1:${b.port}${b.path}`, {
        headers: { "Authorization": `Bearer ${TOKEN}` },
        signal: AbortSignal.timeout(3000),
      });
      const ok = b.expect.includes(res.status);
      if (ok) {
        results.push(`✅ ${b.name} (port ${b.port})`);
      } else {
        results.push(`⚠️  ${b.name} (port ${b.port}) — HTTP ${res.status}`);
      }
    } catch {
      results.push(`❌ ${b.name} (port ${b.port}) — not running`);
    }
  }

  // Check cookie status for web bridges
  const cookieFiles = [
    { name: "MiMo cookies", file: "mimo-cookies.json" },
    { name: "Meta cookies", file: "meta-cookies.json" },
    { name: "DeepSeek cookies", file: "deepseek-cookies.json" },
    { name: "Qwen cookies", file: "qwen-cookies.json" },
    { name: "Gemini cookies", file: "gemini-cookies.json" },
  ];
  results.push("\nCookie status:");
  for (const c of cookieFiles) {
    const fp = path.join(DATA_DIR, c.file);
    if (fs.existsSync(fp)) {
      try {
        const data = JSON.parse(fs.readFileSync(fp, "utf8"));
        const count = Array.isArray(data) ? data.length : 1;
        results.push(`  ✅ ${c.name} (${count} account${count > 1 ? "s" : ""})`);
      } catch {
        results.push(`  ⚠️  ${c.name} (invalid JSON)`);
      }
    } else {
      results.push(`  ❌ ${c.name} — push via Cookie Pusher`);
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

  // Categorize
  const cats = {};
  for (const m of models) {
    const prefix = m.split("/")[0] || "direct";
    cats[prefix] = (cats[prefix] || 0) + 1;
  }

  const lines = [`Total: ${models.length} models`];
  for (const [k, v] of Object.entries(cats).sort((a, b) => b[1] - a[1]).slice(0, 15)) {
    lines.push(`  ${k}: ${v}`);
  }
  if (filter) {
    lines.push(`\nFiltered by "${filter}" (${models.length} models):`);
    for (const m of models.slice(0, 30)) lines.push(`  ${m}`);
    if (models.length > 30) lines.push(`  ... and ${models.length - 30} more`);
  }
  return lines.join("\n");
}

function skillsList({ filter }) {
  if (!fs.existsSync(SKILLS_DIR)) return "No skills directory found at ~/.claude/skills/";

  const dirs = fs.readdirSync(SKILLS_DIR, { withFileTypes: true })
    .filter(d => d.isDirectory())
    .map(d => d.name)
    .sort();

  let skills = dirs;
  if (filter) skills = skills.filter(s => s.includes(filter));

  const lines = [`Total: ${skills.length} skills installed`];
  for (const s of skills.slice(0, 50)) {
    const skillMd = path.join(SKILLS_DIR, s, "SKILL.md");
    let desc = "";
    if (fs.existsSync(skillMd)) {
      const content = fs.readFileSync(skillMd, "utf8");
      const descMatch = content.match(/^description:\s*(.+)$/m);
      if (descMatch) desc = ` — ${descMatch[1].substring(0, 80)}`;
    }
    lines.push(`  /${s}${desc}`);
  }
  if (skills.length > 50) lines.push(`  ... and ${skills.length - 50} more`);
  return lines.join("\n");
}

// ─── MCP Server ───

const toolMap = {
  omniroute_chat: chat,
  omniroute_image: image,
  omniroute_search: search,
  omniroute_health: health,
  omniroute_bridge_status: bridgeStatus,
  omniroute_model_list: modelList,
  omniroute_skills_list: skillsList,
};

// Read Content-Length framed JSON-RPC from stdin
function readMessage() {
  return new Promise((resolve, reject) => {
    const chunks = [];
    process.stdin.on("data", (chunk) => chunks.push(chunk));
    process.stdin.on("end", () => {
      try {
        const raw = Buffer.concat(chunks).toString("utf8");
        // Try to parse as Content-Length framed
        const match = raw.match(/Content-Length:\s*(\d+)\r\n\r\n(.+)/s);
        if (match) {
          resolve(JSON.parse(match[2]));
        } else {
          // Try raw JSON
          resolve(JSON.parse(raw.trim()));
        }
      } catch (e) { reject(e); }
    });
  });
}

function sendResponse(id, result) {
  const resp = JSON.stringify({ jsonrpc: "2.0", id, result });
  const msg = `Content-Length: ${Buffer.byteLength(resp)}\r\n\r\n${resp}`;
  process.stdout.write(msg);
}

function sendError(id, code, message) {
  const resp = JSON.stringify({ jsonrpc: "2.0", id, error: { code, message } });
  const msg = `Content-Length: ${Buffer.byteLength(resp)}\r\n\r\n${resp}`;
  process.stdout.write(msg);
}

async function main() {
  log("MCP server started (PID " + process.pid + ")");

  try {
    const msg = await readMessage();

    if (msg.method === "initialize") {
      sendResponse(msg.id, {
        protocolVersion: "2024-11-05",
        capabilities: { tools: {} },
        serverInfo: { name: "omniroute-tools", version: "2.0.0" },
      });
    } else if (msg.method === "tools/list") {
      sendResponse(msg.id, { tools: TOOLS });
    } else if (msg.method === "tools/call") {
      const { name, arguments: args } = msg.params;
      const fn = toolMap[name];
      if (!fn) {
        sendError(msg.id, -32601, `Unknown tool: ${name}`);
      } else {
        try {
          const result = await fn(args || {});
          sendResponse(msg.id, { content: [{ type: "text", text: result }] });
        } catch (e) {
          sendError(msg.id, -32000, e.message);
        }
      }
    } else {
      sendError(msg.id, -32601, `Unknown method: ${msg.method}`);
    }
  } catch (e) {
    log("Error:", e.message);
    process.exit(1);
  }
}

main();
