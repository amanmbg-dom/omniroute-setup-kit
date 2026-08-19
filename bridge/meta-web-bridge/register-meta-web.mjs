#!/usr/bin/env node
// register-meta-web.mjs — Register the Meta Web Bridge with OmniRoute gateway
// Creates connection + model routes for meta-web/* models

import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const GW = process.env.OMNIROUTE_BASE_URL || "http://127.0.0.1:20128";
const DATA_DIR = process.env.DATA_DIR || path.join(os.homedir(), ".omniroute");
const CONFIG_FILE = path.join(DATA_DIR, "config.js");
const BRIDGE_PORT = process.env.META_BRIDGE_PORT || "20136";

function getConfig() {
  try {
    const content = fs.readFileSync(CONFIG_FILE, "utf8");
    const match = content.match(/DEFAULT_API_KEY\s*=\s*['"]([^'"]+)['"]/);
    return { token: match ? match[1] : "omniroute" };
  } catch {
    return { token: "omniroute" };
  }
}

async function api(method, path, body) {
  const { token } = getConfig();
  const opts = {
    method,
    headers: {
      "Authorization": `Bearer ${token}`,
      "Content-Type": "application/json",
    },
  };
  if (body) opts.body = JSON.stringify(body);
  const res = await fetch(`${GW}${path}`, opts);
  return { status: res.status, data: await res.json().catch(() => ({})) };
}

async function main() {
  console.log("Registering Meta Web Bridge with gateway...");

  // 1. Check if bridge is running
  try {
    const res = await fetch(`http://127.0.0.1:${BRIDGE_PORT}/healthz`, { signal: AbortSignal.timeout(3000) });
    const health = await res.json();
    console.log(`  Bridge health: ${health.status}`);
  } catch {
    console.log(`  WARNING: Bridge not running on port ${BRIDGE_PORT}. Start it first.`);
  }

  // 2. Register the connection
  const connection = {
    name: "Meta Web (auto)",
    type: "openai-compatible",
    baseUrl: `http://127.0.0.1:${BRIDGE_PORT}`,
    authType: "none",
    isActive: true,
    priority: 1,
    maxConcurrent: 5,
  };

  try {
    const { status, data } = await api("POST", "/api/connections", connection);
    if (status < 300) {
      console.log(`  Connection registered: ${data.id || "ok"}`);
    } else {
      console.log(`  Connection registration: ${status} ${JSON.stringify(data).substring(0, 100)}`);
    }
  } catch (e) {
    console.log(`  Connection registration failed: ${e.message}`);
  }

  // 3. Register models
  const models = [
    "meta/llama-3.3-70b",
    "meta/llama-3.1-405b",
    "meta/llama-3.1-70b",
    "meta/llama-3.1-8b",
    "meta-llama-3.3-70b-instruct",
  ];

  for (const model of models) {
    try {
      const { status } = await api("POST", "/api/models", {
        id: model,
        connectionName: "Meta Web (auto)",
        isActive: true,
      });
      if (status < 300) {
        console.log(`  Model registered: ${model}`);
      }
    } catch {}
  }

  console.log("\nDone. Meta Web models are now available as meta-web/* routes.");
  console.log("Sign in at meta.ai, then Cookie Pusher → Grab & push sessions.");
}

main().catch(console.error);
