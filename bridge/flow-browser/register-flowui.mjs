// register-flowui.mjs — register the Google Flow browser bridge in OmniRoute so
//   POST /v1/images/generations  {"model": "flowui/nano-banana-2", ...}
// routes to the local bridge at 127.0.0.1:20134. Idempotent; safe to re-run.
//
// Same storage format as bridge/gemini-bridge/register-gflow.mjs:
//   - provider_connections row (aes-256-gcm encrypted api_key)
//   - key_value 'customModels'/'flowui' entry so the images route accepts flowui/<model>
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { createCipheriv, randomBytes, scryptSync } from "node:crypto";

const HOME = homedir();
const DATA_DIR = process.env.DATA_DIR || join(HOME, ".omniroute");
const DB_PATH = join(DATA_DIR, "storage.sqlite");
const ENV_PATH = join(DATA_DIR, ".env");
const BRIDGE_BASE = process.env.FLOWUI_BASE_URL || "http://127.0.0.1:20134/v1";
const FLOWUI_KEY = process.env.FLOWUI_API_KEY || "flowui-local";

const PREFIX = "enc:v1:";
const STATIC_SALT = "omniroute-field-encryption-v1";

function parseEnv(text) {
  const out = {};
  for (const line of text.split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/);
    if (m) out[m[1]] = m[2];
  }
  return out;
}

function getKey() {
  if (!existsSync(ENV_PATH)) return null;
  const env = parseEnv(readFileSync(ENV_PATH, "utf8"));
  return env.STORAGE_ENCRYPTION_KEY ? scryptSync(env.STORAGE_ENCRYPTION_KEY, STATIC_SALT, 32) : null;
}

function encrypt(value, key) {
  if (!value || value.startsWith(PREFIX)) return value;
  if (!key) return value;
  const iv = randomBytes(16);
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  let enc = cipher.update(value, "utf8", "hex") + cipher.final("hex");
  return `${PREFIX}${iv.toString("hex")}:${enc}:${cipher.getAuthTag().toString("hex")}`;
}

if (!existsSync(DB_PATH)) {
  console.error(`OmniRoute DB not found at ${DB_PATH}. Is the gateway installed?`);
  process.exit(1);
}

const key = getKey();
const db = new DatabaseSync(DB_PATH);
try {
  const now = new Date().toISOString();
  const existing = db
    .prepare("SELECT id, priority FROM provider_connections WHERE provider = 'flowui' AND auth_type = 'apikey'")
    .get();
  const id = existing?.id || crypto.randomUUID();
  const priority = existing?.priority || 1;
  const encKey = encrypt(FLOWUI_KEY, key);
  db.prepare(
    `INSERT INTO provider_connections (
       id, provider, auth_type, name, priority, is_active, api_key, provider_specific_data,
       test_status, created_at, updated_at
     ) VALUES (?, 'flowui', 'apikey', 'Google Flow Browser Bridge', ?, 1, ?, ?, 'unknown', ?, ?)
     ON CONFLICT(id) DO UPDATE SET
       api_key = excluded.api_key, provider_specific_data = excluded.provider_specific_data,
       is_active = 1, updated_at = excluded.updated_at`
  ).run(id, priority, encKey, JSON.stringify({ baseUrl: BRIDGE_BASE }), now, now);

  const models = [
    {
      id: "nano-banana-2",
      name: "Nano Banana 2 (Google Flow, real session)",
      source: "manual",
      apiFormat: "images-generations",
      supportedEndpoints: ["images"],
    },
    {
      id: "nano-banana-pro",
      name: "Nano Banana Pro (Google Flow, real session)",
      source: "manual",
      apiFormat: "images-generations",
      supportedEndpoints: ["images"],
    },
    {
      id: "imagen-4",
      name: "Imagen 4 (Google Flow, real session)",
      source: "manual",
      apiFormat: "images-generations",
      supportedEndpoints: ["images"],
    },
  ];
  db.prepare("INSERT OR REPLACE INTO key_value (namespace, key, value) VALUES ('customModels', 'flowui', ?)").run(
    JSON.stringify(models)
  );

  console.log(`flowui registered -> bridge at ${BRIDGE_BASE}`);
  console.log("use model: flowui/nano-banana-2 (or -pro, imagen-4) on /v1/images/generations");
} finally {
  db.close();
}
