// sync-cookies.mjs — export the pushed Google session from OmniRoute's DB
// into ~/.omniroute/gemini-cookies.json for the bridge to read.
//
// Self-contained on purpose (node:sqlite + node:crypto only): mirrors the
// exact storage format OmniRoute uses (storage.sqlite, provider_connections,
// aes-256-gcm with scrypt(STORAGE_ENCRYPTION_KEY, "omniroute-field-encryption-v1")).
// The Cookie Pusher stores the gemini-web session as the connection's api_key:
//   "__Secure-1PSID=xxx; __Secure-1PSIDTS=yyy"

import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { createDecipheriv, scryptSync } from "node:crypto";

const HOME = homedir();
const DATA_DIR = process.env.DATA_DIR || join(HOME, ".omniroute");
const DB_PATH = join(DATA_DIR, "storage.sqlite");
const ENV_PATH = join(DATA_DIR, ".env");
const OUT_PATH = process.env.GEMINI_COOKIES_FILE || join(DATA_DIR, "gemini-cookies.json");

const PREFIX = "enc:v1:";
const STATIC_SALT = "omniroute-field-encryption-v1";
const WANTED = ["__Secure-1PSID", "__Secure-1PSIDTS"];

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
  const secret = env.STORAGE_ENCRYPTION_KEY;
  if (!secret) return null;
  return scryptSync(secret, STATIC_SALT, 32);
}

function decrypt(value, key) {
  if (!value || typeof value !== "string") return value || "";
  if (!value.startsWith(PREFIX)) return value;
  if (!key) throw new Error("STORAGE_ENCRYPTION_KEY missing from ~/.omniroute/.env");
  const [ivHex, encryptedHex, authTagHex] = value.slice(PREFIX.length).split(":");
  const decipher = createDecipheriv("aes-256-gcm", key, Buffer.from(ivHex, "hex"), {
    authTagLength: 16,
  });
  decipher.setAuthTag(Buffer.from(authTagHex, "hex"));
  return decipher.update(encryptedHex, "hex", "utf8") + decipher.final("utf8");
}

function parseCookieHeader(header) {
  const pairs = {};
  for (const part of header.split(";")) {
    const eq = part.indexOf("=");
    if (eq === -1) continue;
    const name = part.slice(0, eq).trim();
    const value = part.slice(eq + 1).trim();
    if (name) pairs[name] = value;
  }
  return pairs;
}

function fail(msg) {
  console.error(msg);
  process.exit(1);
}

if (!existsSync(DB_PATH)) fail(`OmniRoute DB not found at ${DB_PATH}. Is the gateway installed?`);
const key = getKey();

const db = new DatabaseSync(DB_PATH, { readOnly: true });
try {
  const rows = db
    .prepare(
      `SELECT api_key, provider_specific_data FROM provider_connections
       WHERE lower(provider) = 'gemini-web' ORDER BY updated_at DESC LIMIT 5`
    )
    .all();
  if (!rows.length) {
    fail(
      "No gemini-web connection in OmniRoute. Open gemini.google.com (signed in), then " +
        "Cookie Pusher -> Grab & push sessions, then re-run."
    );
  }

  let found = null;
  for (const row of rows) {
    const apiKey = decrypt(row.api_key, key);
    const pairs = parseCookieHeader(apiKey);
    if (pairs["__Secure-1PSID"]) {
      found = { __Secure1PSID: pairs["__Secure-1PSID"], __Secure1PSIDTS: pairs["__Secure-1PSIDTS"] || "" };
      break;
    }
    // fallback: provider_specific_data may hold cookie / __Secure-1PSID directly
    try {
      const psd = row.provider_specific_data ? JSON.parse(row.provider_specific_data) : {};
      const psid = decrypt(psd.cookie, key) || psd["__Secure-1PSID"] || "";
      const psidts = psd["__Secure-1PSIDTS"] || "";
      if (psid) {
        const header = parseCookieHeader(String(psid).includes("=") ? String(psid) : `__Secure-1PSID=${psid}`);
        found = {
          __Secure1PSID: header["__Secure-1PSID"] || String(psid),
          __Secure1PSIDTS: psidts || "",
        };
        break;
      }
    } catch {
      /* try next row */
    }
  }

  if (!found) fail("gemini-web connection exists but holds no __Secure-1PSID cookie.");
  if (!found.__Secure1PSID) fail("gemini-web cookie is empty.");

  writeFileSync(
    OUT_PATH,
    JSON.stringify(
      { __Secure1PSID: found.__Secure1PSID, __Secure1PSIDTS: found.__Secure1PSIDTS, syncedAt: new Date().toISOString() },
      null,
      2
    )
  );
  console.log(`cookies synced -> ${OUT_PATH} (${found.__Secure1PSID.slice(0, 12)}..., ts:${found.__Secure1PSIDTS ? "yes" : "no"})`);
} finally {
  db.close();
}
