#!/usr/bin/env node
// bridge-plugin-system.mjs — Configuration-driven bridge management
// Add new bridges by editing bridges.json, no code changes needed.
//
// Usage:
//   node bridge-plugin-system.mjs list              — List all bridges
//   node bridge-plugin-system.mjs start <name>      — Start a bridge
//   node bridge-plugin-system.mjs stop <name>       — Stop a bridge
//   node bridge-plugin-system.mjs status            — Check all bridges
//   node bridge-plugin-system.mjs add <config>      — Add a new bridge
//   node bridge-plugin-system.mjs register <name>   — Register with gateway
//
// To add a new bridge, edit ~/.omniroute/bridges.json:
// {
//   "bridges": [
//     {
//       "name": "my-new-bridge",
//       "type": "openai-compatible",
//       "port": 20137,
//       "script": "bridge.mjs",
//       "healthPath": "/healthz",
//       "modelsPath": "/v1/models",
//       "chatPath": "/v1/chat/completions",
//       "cookiesNeeded": true,
//       "cookieFile": "my-cookies.json",
//       "env": { "MY_VAR": "value" },
//       "registerWithGateway": true,
//       "gatewayConnection": {
//         "name": "My New Bridge (auto)",
//         "type": "openai-compatible",
//         "baseUrl": "http://127.0.0.1:20137",
//         "authType": "none"
//       }
//     }
//   ]
// }

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execSync, spawn } from "node:child_process";

const DATA_DIR = process.env.DATA_DIR || path.join(os.homedir(), ".omniroute");
const BRIDGES_FILE = path.join(DATA_DIR, "bridges.json");
const GW = process.env.OMNIROUTE_BASE_URL || "http://127.0.0.1:20128";
const KIT_DIR = process.env.KIT_DIR || path.join(os.homedir(), "omniroute-setup-kit");

function loadBridges() {
  try {
    return JSON.parse(fs.readFileSync(BRIDGES_FILE, "utf8")).bridges || [];
  } catch {
    // Default bridges
    return [
      {
        name: "gemini-bridge",
        type: "python",
        port: 20133,
        dir: "bridge/gemini-bridge",
        script: "bridge.py",
        healthPath: "/health",
        registerWithGateway: false,  // already registered
      },
      {
        name: "flowui",
        type: "python",
        port: 20134,
        dir: "bridge/flow-browser",
        script: "flowui.py",
        healthPath: "/",
        registerWithGateway: false,  // already registered
      },
      {
        name: "mimo-web",
        "type": "node",
        port: 20135,
        dir: "bridge/mimo-web-bridge",
        script: "bridge.mjs",
        healthPath: "/healthz",
        cookiesNeeded: true,
        cookieFile: "mimo-cookies.json",
        registerWithGateway: false,  // already registered
      },
      {
        name: "deepseek-web",
        "type": "node",
        port: 20137,
        dir: "bridge/deepseek-web-bridge",
        script: "bridge.mjs",
        healthPath: "/healthz",
        cookiesNeeded: true,
        cookieFile: "deepseek-cookies.json",
        registerWithGateway: false,  // already registered
      },
      {
        name: "meta-web",
        type: "node",
        port: 20136,
        dir: "bridge/meta-web-bridge",
        script: "bridge.mjs",
        healthPath: "/healthz",
        cookiesNeeded: true,
        cookieFile: "meta-cookies.json",
        registerWithGateway: true,
        gatewayConnection: {
          name: "Meta Web (auto)",
          type: "openai-compatible",
          baseUrl: "http://127.0.0.1:20136",
          authType: "none",
        },
      },
    ];
  }
}

function saveBridges(bridges) {
  fs.mkdirSync(path.dirname(BRIDGES_FILE), { recursive: true });
  fs.writeFileSync(BRIDGES_FILE, JSON.stringify({ bridges }, null, 2));
}

function checkPort(port) {
  try {
    execSync(`netstat -ano | findstr :${port} | findstr LISTENING`, { stdio: "pipe" });
    return true;
  } catch {
    return false;
  }
}

async function checkBridge(bridge) {
  try {
    const res = await fetch(`http://127.0.0.1:${bridge.port}${bridge.healthPath}`, {
      signal: AbortSignal.timeout(3000),
    });
    return { running: true, status: res.ok ? "healthy" : `HTTP ${res.status}` };
  } catch {
    return { running: false, status: "not running" };
  }
}

// ─── Commands ───

async function listBridges() {
  const bridges = loadBridges();
  console.log("Configured bridges:");
  for (const b of bridges) {
    const { running, status } = await checkBridge(b);
    const icon = running ? "✅" : "❌";
    const cookie = b.cookiesNeeded ? " 🔑" : "";
    console.log(`  ${icon} ${b.name} (port ${b.port}) - ${status}${cookie}`);
  }
}

async function statusBridges() {
  const bridges = loadBridges();
  const results = [];
  for (const b of bridges) {
    const { running, status } = await checkBridge(b);
    results.push({ name: b.name, port: b.port, running, status });
  }
  console.log(JSON.stringify(results, null, 2));
}

async function addBridge(config) {
  const bridges = loadBridges();
  const existing = bridges.find(b => b.name === config.name);
  if (existing) {
    Object.assign(existing, config);
    console.log(`Updated bridge: ${config.name}`);
  } else {
    bridges.push(config);
    console.log(`Added bridge: ${config.name}`);
  }
  saveBridges(bridges);
}

async function registerBridge(name) {
  const bridges = loadBridges();
  const bridge = bridges.find(b => b.name === name);
  if (!bridge) {
    console.error(`Bridge not found: ${name}`);
    return;
  }
  if (!bridge.registerWithGateway || !bridge.gatewayConnection) {
    console.log(`Bridge ${name} doesn't need gateway registration`);
    return;
  }

  // Get admin token
  let token = "omniroute";
  try {
    const content = fs.readFileSync(path.join(DATA_DIR, "config.js"), "utf8");
    const match = content.match(/DEFAULT_API_KEY\s*=\s*['"]([^'"]+)['"]/);
    if (match) token = match[1];
  } catch {}

  try {
    const res = await fetch(`${GW}/api/connections`, {
      method: "POST",
      headers: { "Authorization": `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify(bridge.gatewayConnection),
    });
    if (res.ok) {
      console.log(`Registered ${name} with gateway`);
    } else {
      console.log(`Registration failed: ${res.status}`);
    }
  } catch (e) {
    console.error(`Registration error: ${e.message}`);
  }
}

// ─── CLI ───

const [,, cmd, ...args] = process.argv;

switch (cmd) {
  case "list": listBridges(); break;
  case "status": statusBridges(); break;
  case "add":
    if (args[0]) {
      try {
        addBridge(JSON.parse(args[0]));
      } catch {
        console.error("Usage: bridge-plugin-system.mjs add '{\"name\":\"...\",\"port\":...}'");
      }
    }
    break;
  case "register":
    if (args[0]) registerBridge(args[0]);
    else console.error("Usage: bridge-plugin-system.mjs register <name>");
    break;
  default:
    console.log("Bridge Plugin System");
    console.log("Commands: list, status, add, register");
    console.log("Edit ~/.omniroute/bridges.json to add new bridges");
}
