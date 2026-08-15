// register-mimo-web.mjs — register the MiMo web bridge in OmniRoute's storage so
//   GET  /v1/models                  lists mimo-web/<model>
//   POST /v1/chat/completions  mimo-web/<model>  routes to the local bridge
// Idempotent; safe to re-run (e.g. after `omniroute reset`).
//
// Mirrors OmniRoute's own storage format (self-contained on purpose, same as
// bridge/gemini-bridge/register-gflow.mjs):
//   - provider_nodes row (type openai-compatible, prefix 'mimo-web')
//   - provider_connections row so the gateway routes mimo-web/* chat to the bridge
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { randomUUID } from "node:crypto";
import { DatabaseSync } from "node:sqlite";

const HOME = homedir();
const DATA_DIR = process.env.DATA_DIR || join(HOME, ".omniroute");
const DB_PATH = join(DATA_DIR, "storage.sqlite");
const BRIDGE_BASE = process.env.MIMO_BRIDGE_URL || "http://127.0.0.1:20135/v1";

if (!existsSync(DB_PATH)) {
  console.error(`OmniRoute DB not found at ${DB_PATH}. Is the gateway installed?`);
  process.exit(1);
}

const db = new DatabaseSync(DB_PATH);
try {
  const now = new Date().toISOString();

  // 1. provider node (openai-compatible) — upsert by prefix
  const node = db.prepare("SELECT id FROM provider_nodes WHERE prefix = 'mimo-web'").get();
  const nodeId = (node && node.id) || `openai-compatible-${randomUUID()}`;
  db.prepare(
    `INSERT INTO provider_nodes (id, type, name, prefix, api_type, base_url, chat_path, models_path, custom_headers_json, created_at, updated_at)
     VALUES (?, 'openai-compatible', 'MiMo Web', 'mimo-web', 'chat', ?, '/chat/completions', '/models', NULL, ?, ?)
     ON CONFLICT(id) DO UPDATE SET
       base_url = excluded.base_url, chat_path = excluded.chat_path,
       models_path = excluded.models_path, updated_at = excluded.updated_at`
  ).run(nodeId, BRIDGE_BASE, now, now);

  // 2. provider connection so the gateway routes mimo-web/* chat to the bridge.
  // The gateway resolves openai-compatible node credentials by NODE ID (so the
  // connection's provider must be the node id, not the prefix), and it reads the
  // bridge URL from provider_specific_data.baseUrl (same contract as gflow).
  const conn = db.prepare("SELECT id FROM provider_connections WHERE provider = ?").get(nodeId);
  const connId = (conn && conn.id) || randomUUID();
  db.prepare(
    `INSERT INTO provider_connections (id, provider, auth_type, name, priority, is_active, api_key, provider_specific_data, test_status, created_at, updated_at)
     VALUES (?, ?, 'apikey', 'MiMo Web Bridge', 1, 1, 'mimo-web-local', ?, 'unknown', ?, ?)
     ON CONFLICT(id) DO UPDATE SET is_active = 1, provider_specific_data = excluded.provider_specific_data,
       test_status = 'unknown', last_error = NULL, backoff_level = 0, rate_limited_until = NULL,
       updated_at = excluded.updated_at`
  ).run(connId, nodeId, JSON.stringify({ baseUrl: BRIDGE_BASE }), now, now);

  console.log(`mimo-web registered -> bridge at ${BRIDGE_BASE}`);
  console.log("use models: mimo-web/mimo-v2.5, mimo-web/mimo-v2.5-pro, mimo-web/mimo-v2-flash, ...");
} finally {
  db.close();
}
