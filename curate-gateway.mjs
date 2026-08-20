#!/usr/bin/env node
// curate-gateway.mjs — make the gateway's /v1/models catalog EXACTLY the
// curated free-model list, on both platforms.
//
// OmniRoute's catalog builder skips any model flagged isHidden in the
// `modelCompatOverrides` key_value namespace (the same storage the dashboard's
// "hide" eye writes). Hiding every NON-curated route means:
//   - Claude Code's gateway discovery (/v1/models) returns ONLY the curated
//     list  -> the /model picker shows exactly the good free models, and
//     `claude -m <route>` stops being rejected as "restricted" (the model is
//     in the entitlement list).
//   - Codex, the dashboard and any other client see the same curated catalog.
//   - No "gazillion models" on any picker.
//
// Idempotent + re-runnable (fix-model-cache runs it at every start). Curated
// models are explicitly un-hidden; non-curated are hidden. Escape hatch:
//   SKIP_CURATE=1 node curate-gateway.mjs ...   (report only, no writes)
//
// Usage:
//   node curate-gateway.mjs <storage.sqlite> <baseUrl> <token> <curated-ids-file>
//
// <curated-ids-file> is a newline-separated list of the exact ids to keep.
import { DatabaseSync } from "node:sqlite";
import { readFileSync, existsSync } from "node:fs";

const [dbPath, gw, token, listFile] = process.argv.slice(2);
if (!dbPath || !gw || !listFile) {
  console.error("usage: node curate-gateway.mjs <storage.sqlite> <baseUrl> <token> <curated-ids-file>");
  process.exit(2);
}

const NS = "modelCompatOverrides";
const CUSTOM_NS = "customModels";
const SKIP = process.env.SKIP_CURATE === "1";

async function main() {
  if (!existsSync(dbPath)) {
    console.log(`  (gateway DB not found at ${dbPath} - curation skipped)`);
    return;
  }
  // The curated list is authoritative for what stays visible.
  const curated = new Set(
    readFileSync(listFile, "utf8")
      .split(/\r?\n/)
      .map((s) => s.trim())
      .filter(Boolean)
  );
  if (curated.size === 0) {
    console.log("  (curated list empty - curation skipped; refusing to hide everything)");
    return;
  }

  // Fetch the FULL live catalog (all routes, including non-curated).
  let cat;
  try {
    const headers = token ? { Authorization: `Bearer ${token}` } : {};
    cat = await (
      await fetch(`${gw}/v1/models`, { headers, signal: AbortSignal.timeout(25000) })
    ).json();
  } catch (e) {
    console.log(`  (could not fetch ${gw}/v1/models for curation: ${e.message})`);
    return;
  }
  const all = [...new Set((cat.data || []).map((m) => m.id))];
  if (!all.length) {
    console.log("  (catalog empty - curation skipped)");
    return;
  }

  // Group by provider prefix (provider = text before the first '/').
  const byProvider = new Map();
  for (const id of all) {
    const p = id.includes("/") ? id.split("/")[0] : id;
    if (!byProvider.has(p)) byProvider.set(p, []);
    byProvider.get(p).push(id);
  }

  const db = new DatabaseSync(dbPath, { timeout: 30000 });
  const getList = (ns, key) => {
    try {
      const row = db
        .prepare("SELECT value FROM key_value WHERE namespace = ? AND key = ?")
        .get(ns, key);
      if (!row || !row.value) return [];
      const j = JSON.parse(row.value);
      return Array.isArray(j) ? j : [];
    } catch {
      return [];
    }
  };

  let hidden = 0;
  let shown = 0;
  let touched = 0;
  const writes = [];

  for (const [provider, ids] of byProvider) {
    const existing = getList(NS, provider);
    const byId = new Map(existing.map((e) => [e && e.id, e]));
    const out = [];
    let providerHidden = 0;
    for (const id of ids) {
      const want = curated.has(id);
      const cur = byId.get(id);
      if (want) {
        if (cur && cur.isHidden) out.push({ ...cur, isHidden: false });
        shown++;
      } else {
        if (!cur) out.push({ id, isHidden: true });
        else if (!cur.isHidden) out.push({ ...cur, isHidden: true });
        else out.push(cur);
        providerHidden++;
        hidden++;
      }
    }
    // Preserve existing compat entries for ids the live catalog no longer lists.
    for (const e of existing) {
      if (e && e.id && !byId.has(e.id)) out.push(e);
    }
    if (out.length === 0) continue;
    const same =
      out.length === existing.length &&
      out.every((e, i) => JSON.stringify(e) === JSON.stringify(existing[i]));
    if (same) continue;
    writes.push([provider, out]);
    if (providerHidden > 0) touched++;
  }

  // Also un-hide curated models that were hidden via a customModels row
  // (the catalog builder checks customModels BEFORE the compat list).
  const curatedWithSlash = [...curated].filter((i) => i.includes("/"));
  const customProviders = new Set(curatedWithSlash.map((i) => i.split("/")[0]));
  for (const provider of customProviders) {
    const existing = getList(CUSTOM_NS, provider);
    if (!existing.length) continue;
    let dirty = false;
    const out = existing.map((e) => {
      if (e && e.id && curated.has(e.id) && e.isHidden) {
        dirty = true;
        return { ...e, isHidden: false };
      }
      return e;
    });
    if (dirty) writes.push([provider, out]);
  }

  if (SKIP) {
    console.log(`  [SKIP_CURATE=1] would hide ${hidden} routes, keep ${shown} curated routes (${writes.length} provider rows)`);
    db.close();
    return;
  }

  const write = db.prepare("INSERT OR REPLACE INTO key_value (namespace, key, value) VALUES (?, ?, ?)");
  db.exec("BEGIN");
  try {
    for (const [provider, list] of writes) write.run(NS, provider, JSON.stringify(list));
    db.exec("COMMIT");
  } catch (e) {
    db.exec("ROLLBACK");
    throw e;
  }
  db.close();

  console.log(`  curation: catalog ${all.length} -> keeping ${shown} curated, hiding ${hidden} (${touched} providers written)`);
}

main().catch((e) => {
  console.log(`  (curation failed: ${e.message})`);
  process.exitCode = 1;
});
