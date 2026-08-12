// register-gflow.mjs — register the bridge in OmniRoute so
//   POST /v1/images/generations  {"model": "gflow/nano-banana-2", ...}
// routes to the local bridge. Idempotent; safe to re-run after a reset.
//
// Mirrors OmniRoute's own storage format (self-contained on purpose):
//   - provider_connections row (aes-256-gcm encrypted api_key, same scheme as sync-cookies.mjs)
//   - key_value 'customModels'/'gflow' entry so the images route accepts gflow/<model>
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { createCipheriv, createDecipheriv, randomBytes, scryptSync } from "node:crypto";

const HOME = homedir();
const DATA_DIR = process.env.DATA_DIR || join(HOME, ".omniroute");
const DB_PATH = join(DATA_DIR, "storage.sqlite");
const ENV_PATH = join(DATA_DIR, ".env");
const BRIDGE_BASE = process.env.GFLOW_BASE_URL || "http://127.0.0.1:20133/v1";
const GFLOW_KEY = process.env.GFLOW_API_KEY || "gflow-local";

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
  if (!key) return value; // no key configured — store plaintext like OmniRoute does
  const iv = randomBytes(16);
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  let enc = cipher.update(value, "utf8", "hex") + cipher.final("hex");
  return `${PREFIX}${iv.toString("hex")}:${enc}:${cipher.getAuthTag().toString("hex")}`;
}

function decrypt(value, key) {
  if (!value || typeof value !== "string" || !value.startsWith(PREFIX)) return value || "";
  if (!key) throw new Error("STORAGE_ENCRYPTION_KEY missing from ~/.omniroute/.env");
  const [ivHex, encryptedHex, authTagHex] = value.slice(PREFIX.length).split(":");
  const d = createDecipheriv("aes-256-gcm", key, Buffer.from(ivHex, "hex"), { authTagLength: 16 });
  d.setAuthTag(Buffer.from(authTagHex, "hex"));
  return d.update(encryptedHex, "hex", "utf8") + d.final("utf8");
}

if (!existsSync(DB_PATH)) {
  console.error(`OmniRoute DB not found at ${DB_PATH}. Is the gateway installed?`);
  process.exit(1);
}

const key = getKey();
const db = new DatabaseSync(DB_PATH);
try {
  // 1. provider_connections row for gflow (authType apikey + providerSpecificData.baseUrl)
  const now = new Date().toISOString();
  const existing = db
    .prepare("SELECT id, priority FROM provider_connections WHERE provider = 'gflow' AND auth_type = 'apikey'")
    .get();
  const id = existing?.id || crypto.randomUUID();
  const priority = existing?.priority || 1;
  const encKey = encrypt(GFLOW_KEY, key);
  db.prepare(
    `INSERT INTO provider_connections (
       id, provider, auth_type, name, priority, is_active, api_key, provider_specific_data,
       test_status, created_at, updated_at
     ) VALUES (?, 'gflow', 'apikey', 'Google Flow Bridge', ?, 1, ?, ?, 'unknown', ?, ?)
     ON CONFLICT(id) DO UPDATE SET
       api_key = excluded.api_key, provider_specific_data = excluded.provider_specific_data,
       is_active = 1, updated_at = excluded.updated_at`
  ).run(id, priority, encKey, JSON.stringify({ baseUrl: BRIDGE_BASE }), now, now);

  // 2. custom model so /v1/images/generations accepts gflow/nano-banana-2
  const models = [
    {
      id: "nano-banana-2",
      name: "Nano Banana 2 (Gemini Web)",
      source: "manual",
      apiFormat: "images-generations",
      supportedEndpoints: ["images"],
    },
  ];
  db.prepare("INSERT OR REPLACE INTO key_value (namespace, key, value) VALUES ('customModels', 'gflow', ?)").run(
    JSON.stringify(models)
  );

  console.log(`gflow registered -> bridge at ${BRIDGE_BASE}`);
  console.log("use model: gflow/nano-banana-2 on /v1/images/generations");
} finally {
  db.close();
}
