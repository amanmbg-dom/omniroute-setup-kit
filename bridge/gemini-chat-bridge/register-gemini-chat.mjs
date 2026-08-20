#!/usr/bin/env node
// register-gemini-chat.mjs — Register the Gemini chat bridge with OmniRoute
// as an openai-compatible provider node.

import http from "node:http";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const BRIDGE_PORT = process.env.GEMINI_CHAT_PORT || "20138";
const BRIDGE_HOST = process.env.GEMINI_CHAT_HOST || "127.0.0.1";
const GATEWAY_PORT = process.env.GATEWAY_PORT || "20128";
const DATA_DIR = process.env.DATA_DIR || path.join(os.homedir(), ".omniroute");
const CONFIG_FILE = path.join(DATA_DIR, "config.json");

function log(...args) {
  console.log(`[register-gemini-chat ${new Date().toISOString()}]`, ...args);
}

async function checkBridge() {
  try {
    const resp = await fetch(`http://${BRIDGE_HOST}:${BRIDGE_PORT}/healthz`);
    const data = await resp.json();
    return data.ok === true;
  } catch {
    return false;
  }
}

async function registerWithGateway() {
  const config = {
    id: "gemini-chat-bridge",
    name: "Gemini Chat Bridge",
    type: "openai-compatible",
    baseUrl: `http://${BRIDGE_HOST}:${BRIDGE_PORT}`,
    models: [
      "gemini-2.5-flash",
      "gemini-2.5-pro",
      "gemini-2.0-flash",
      "gemini-1.5-pro",
      "gemini-1.5-flash",
    ],
    enabled: true,
    priority: 10,
  };

  log(`Registering Gemini chat bridge at http://${BRIDGE_HOST}:${BRIDGE_PORT}`);

  try {
    // Try to register with the local gateway
    const resp = await fetch(`http://127.0.0.1:${GATEWAY_PORT}/api/providers`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(config),
    });

    if (resp.ok) {
      log("Registered with gateway successfully");
      return true;
    } else {
      log(`Gateway registration failed: ${resp.status}`);
      return false;
    }
  } catch (e) {
    log(`Gateway not reachable: ${e.message}`);
    log("Bridge will work standalone — connect via direct URL");
    return false;
  }
}

async function main() {
  log("Checking bridge health...");
  const healthy = await checkBridge();

  if (!healthy) {
    log("Bridge not healthy — start it first with start-bridge.cmd");
    process.exit(1);
  }

  log("Bridge is healthy");

  // Save config locally
  fs.mkdirSync(DATA_DIR, { recursive: true });
  const localConfig = {
    bridge: "gemini-chat",
    port: BRIDGE_PORT,
    host: BRIDGE_HOST,
    registeredAt: new Date().toISOString(),
  };
  fs.writeFileSync(CONFIG_FILE, JSON.stringify(localConfig, null, 2));
  log(`Config saved to ${CONFIG_FILE}`);

  // Register with gateway
  await registerWithGateway();

  log("Done! Use the Gemini chat bridge at:");
  log(`  http://${BRIDGE_HOST}:${BRIDGE_PORT}/v1/chat/completions`);
}

main().catch((e) => {
  console.error("Registration failed:", e.message);
  process.exit(1);
});
