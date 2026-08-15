// OmniRoute Cookie Pusher — shared core (ES module).
// Used by both the popup (manual grab) and the background service worker
// (scheduled + expiry-driven auto-refresh).
import { DEFAULT_URL, DEFAULT_API_KEY } from './config.js';

export const DEFAULTS = { url: DEFAULT_URL, apiKey: DEFAULT_API_KEY };

// Provider catalog — mirrors OmniRoute's WEB_COOKIE_PROVIDERS auth hints.
// mode:
//   'header'        -> full cookie header for the domain (name=value; ...)
//   'named'         -> only specific cookie names (assembled name=value; ...)
//   'ls'            -> localStorage token read from an open tab for the domain
//   'ls+header'     -> localStorage token + cookie header (t3.chat needs both)
//   'ls-or-cookie'  -> localStorage token preferred, named cookie as fallback
export const PROVIDERS = [
  // ---- Free tiers (no subscription) ----
  { id: 'huggingchat', label: 'HuggingChat', mode: 'header', domain: 'huggingface.co', free: true },
  { id: 'gemini-web', label: 'Gemini Web', mode: 'named', domain: 'google.com',
    names: ['__Secure-1PSID', '__Secure-1PSIDTS'], required: ['__Secure-1PSID'], free: true },
  { id: 'zai-web', label: 'Z.ai GLM', mode: 'header', domain: 'chat.z.ai', free: true },
  { id: 'yuanbao-web', label: 'Tencent Yuanbao', mode: 'header', domain: 'yuanbao.tencent.com', free: true },
  { id: 'lmarena', label: 'Arena', mode: 'header', domain: 'arena.ai', free: true },
  { id: 'muse-spark-web', label: 'Meta AI Muse', mode: 'header', domain: 'meta.ai', free: true },
  { id: 'zenmux-free', label: 'ZenMux', mode: 'header', domain: 'zenmux.ai', free: true },
  { id: 'qwen-web', label: 'Qwen Web', mode: 'ls+header', domain: 'chat.qwen.ai',
    lsKey: 'token', free: true },
  { id: 't3-web', label: 't3.chat', mode: 'ls+header', domain: 't3.chat',
    lsKey: 'convex-session-id', free: true },

  // ---- Subscription / optional (grabbed only if signed in) ----
  { id: 'deepseek-web', label: 'DeepSeek Web', mode: 'ls', domain: 'chat.deepseek.com', lsKey: 'userToken' },
  { id: 'chatgpt-web', label: 'ChatGPT', mode: 'named', domain: 'chatgpt.com',
    names: ['__Secure-next-auth.session-token'], required: ['__Secure-next-auth.session-token'] },
  { id: 'grok-web', label: 'Grok', mode: 'header', domain: 'grok.com' },
  { id: 'perplexity-web', label: 'Perplexity', mode: 'named', domain: 'perplexity.ai',
    names: ['__Secure-next-auth.session-token'], required: ['__Secure-next-auth.session-token'] },
  { id: 'claude-web', label: 'Claude Web', mode: 'header', domain: 'claude.ai' },
  { id: 'poe-web', label: 'Poe', mode: 'named', domain: 'poe.com', names: ['p-b'], required: ['p-b'] },
  { id: 'venice-web', label: 'Venice', mode: 'header', domain: 'venice.ai' },
  { id: 'blackbox-web', label: 'Blackbox', mode: 'named', domain: 'blackbox.ai',
    names: ['__Secure-authjs.session-token'], required: ['__Secure-authjs.session-token'] },
  { id: 'kimi-web', label: 'Kimi', mode: 'ls-or-cookie', domain: 'kimi.com',
    lsKey: 'access_token', cookieName: 'kimi-auth', cookieValue: false },
  { id: 'hailuo-web', label: 'Hailuo (MiniMax)', mode: 'ls', domain: 'hailuo.ai', lsKey: '_token' },
  { id: 'doubao-web', label: 'Dola (ByteDance)', mode: 'header', domain: 'dola.com' },
  { id: 'copilot-web', label: 'Microsoft Copilot', mode: 'header', domain: 'copilot.microsoft.com' },
  { id: 'v0-vercel-web', label: 'v0 (Vercel)', mode: 'header', domain: 'v0.dev' },
  { id: 'notion-web', label: 'Notion AI', mode: 'named', domain: 'notion.so',
    names: ['token_v2'], required: ['token_v2'], bareValue: true },
  { id: 'gemini-business', label: 'Gemini Business', mode: 'named', domain: 'google.com',
    names: ['__Secure-1PSID', '__Secure-1PSIDTS'], required: ['__Secure-1PSID'] },
];

// Alarms
export const ALARM_FULL = 'omniroute-refresh-full';
export const ALARM_CHECK = 'omniroute-check-expired';
export const EXPIRY_CHECK_MINUTES = 30;
export const DEFAULT_REFRESH_HOURS = 6;

// ---------- settings ----------

export async function getSettings() {
  const stored = await chrome.storage.local.get(['url', 'apiKey', 'autoRefresh', 'refreshHours']);
  // The gateway binds IPv4 only. Chrome resolves 'localhost' to ::1 on
  // Windows, so always use the IPv4 literal - even if a stale 'localhost'
  // URL was saved to chrome.storage before this fix.
  let url = stored.url || DEFAULT_URL;
  if (/localhost|::1/.test(url)) url = DEFAULT_URL;
  return {
    url,
    apiKey: stored.apiKey || DEFAULT_API_KEY,
    autoRefresh: stored.autoRefresh !== false,
    refreshHours: stored.refreshHours || DEFAULT_REFRESH_HOURS,
  };
}

// ---------- grabbing ----------

async function getCookies(domain) {
  return chrome.cookies.getAll({ domain });
}

function toHeader(cookies, wantedNames) {
  const list = cookies
    .filter((c) => !wantedNames || wantedNames.includes(c.name))
    .map((c) => `${c.name}=${c.value}`);
  return list.length ? list.join('; ') : null;
}

function findCookie(cookies, name) {
  const c = cookies.find((x) => x.name === name);
  return c ? c.value : null;
}

async function findOpenTab(domain) {
  const host = domain.toLowerCase();
  const tabs = await chrome.tabs.query({});
  return tabs.find((t) => {
    try {
      const u = new URL(t.url);
      return u.hostname === host || u.hostname.endsWith('.' + host);
    } catch {
      return false;
    }
  });
}

async function readLocalStorage(domain, key) {
  const tab = await findOpenTab(domain);
  if (!tab || tab.id == null) return { value: null, needTab: true };
  try {
    const results = await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      func: (k) => {
        try {
          return localStorage.getItem(k);
        } catch {
          return null;
        }
      },
      args: [key],
    });
    const v = results && results[0] && results[0].result;
    return { value: v || null, needTab: false };
  } catch (e) {
    return { value: null, needTab: false, error: String(e) };
  }
}

// Returns { found, apiKey?, note? } | { found:false, reason:'no-session' | 'need-tab' }
export async function grabCredential(cfg) {
  const cookies = await getCookies(cfg.domain);
  switch (cfg.mode) {
    case 'header': {
      const h = toHeader(cookies, null);
      return h ? { found: true, apiKey: h, note: `${cookies.length} cookies` } : { found: false, reason: 'no-session' };
    }
    case 'named': {
      if (cfg.bareValue) {
        const v = findCookie(cookies, cfg.required[0]);
        return v ? { found: true, apiKey: v, note: `${cfg.required[0]}` } : { found: false, reason: 'no-session' };
      }
      const h = toHeader(cookies, cfg.names);
      if (!h) return { found: false, reason: 'no-session' };
      const missing = (cfg.required || []).filter((n) => !cookies.some((c) => c.name === n));
      return { found: true, apiKey: h, note: missing.length ? `missing ${missing.join(', ')}` : 'ok' };
    }
    case 'ls': {
      const r = await readLocalStorage(cfg.domain, cfg.lsKey);
      if (r.needTab) return { found: false, reason: 'need-tab' };
      return r.value
        ? { found: true, apiKey: r.value, note: 'localStorage' }
        : { found: false, reason: 'no-session' };
    }
    case 'ls+header': {
      const h = toHeader(cookies, null);
      const r = await readLocalStorage(cfg.domain, cfg.lsKey);
      const parts = [];
      if (r.value) parts.push(`${cfg.lsKey}=${r.value}`);
      if (h) parts.push(h);
      if (!parts.length) return r.needTab ? { found: false, reason: 'need-tab' } : { found: false, reason: 'no-session' };
      return { found: true, apiKey: parts.join('; '), note: `${r.value ? 'ls+' : ''}${h ? cookies.length + ' cookies' : ''}` };
    }
    case 'ls-or-cookie': {
      const r = await readLocalStorage(cfg.domain, cfg.lsKey);
      if (r.value) return { found: true, apiKey: r.value, note: 'localStorage' };
      const c = findCookie(cookies, cfg.cookieName);
      if (c) {
        return { found: true, apiKey: cfg.cookieValue ? c : `${cfg.cookieName}=${c}`, note: 'cookie fallback' };
      }
      return r.needTab ? { found: false, reason: 'need-tab' } : { found: false, reason: 'no-session' };
    }
  }
  return { found: false, reason: 'no-session' };
}

// ---------- pushing ----------
// Auth uses a Bearer API key (admin scope) — NOT the dashboard password.
// OmniRoute's mutation-origin guard only applies to cookie-authed dashboard
// sessions; Bearer-authed requests from any origin are accepted.

function resolveBase(settings) {
  return (settings.url || DEFAULT_URL).replace(/\/+$/, '');
}

function resolveApiKey(settings) {
  return (settings.apiKey || DEFAULT_API_KEY).trim();
}

async function apiFetch(path, { method = 'GET', body } = {}, settings) {
  const base = resolveBase(settings);
  const apiKey = resolveApiKey(settings);
  const res = await fetch(`${base}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${apiKey}`,
    },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`API ${method} ${path} ${res.status}: ${text.slice(0, 200)}`);
  return text ? JSON.parse(text) : null;
}

export async function listConnections(settings) {
  try {
    const data = await apiFetch('/api/providers', {}, settings);
    if (Array.isArray(data)) return data;
    return (data && data.connections) || [];
  } catch {
    return [];
  }
}

export async function deleteConnection(id, settings) {
  try {
    await apiFetch(`/api/providers/${encodeURIComponent(id)}`, { method: 'DELETE' }, settings);
  } catch {
    // ignore — the connection may already be gone
  }
}

export async function pushConnection(cfg, credential, settings) {
  // Upsert: remove any previous "… (auto)" connection for this provider so
  // auto-refresh never accumulates duplicates.
  const conns = await listConnections(settings);
  const stale = (conns || []).filter(
    (c) => c.provider === cfg.id && /\(auto\)$/.test(String(c.name || ''))
  );
  for (const c of stale) await deleteConnection(c.id, settings);

  const data = await apiFetch(
    '/api/providers',
    {
      method: 'POST',
      body: {
        provider: cfg.id,
        apiKey: credential.apiKey,
        name: `${cfg.label} (auto)`,
      },
    },
    settings
  );
  return { status: 201, body: JSON.stringify(data).slice(0, 300) };
}

export async function runAll(settings) {
  const results = [];
  for (const cfg of PROVIDERS) {
    try {
      const cred = await grabCredential(cfg);
      if (!cred.found) {
        results.push({ id: cfg.id, label: cfg.label, free: cfg.free, status: 'skip', reason: cred.reason });
        continue;
      }
      await pushConnection(cfg, cred, settings);
      results.push({ id: cfg.id, label: cfg.label, free: cfg.free, status: 'ok', note: cred.note, http: 201 });
    } catch (e) {
      results.push({ id: cfg.id, label: cfg.label, free: cfg.free, status: 'error', error: String(e) });
    }
  }
  return results;
}

// ---------- expiry detection ----------

const AUTH_ERROR_TYPES = new Set([
  'forbidden',
  'not_found',
  'token_expired',
  'session_expired',
  'auth',
  'unauthorized',
  'invalid_origin',
]);

function isExpiredSignal(c) {
  const et = String(c.lastErrorType || c.errorCode || c.error_type || '').toLowerCase();
  if (AUTH_ERROR_TYPES.has(et)) return true;
  const le = String(c.lastError || c.error || c.last_error || '').toUpperCase();
  if (
    le.includes('SESSION_EXPIRED') ||
    le.includes('AUTH_007') ||
    le.includes('401') ||
    le.includes('403')
  ) {
    return true;
  }
  // Any error state on one of our web-cookie connections → attempt a refresh
  // (harmless: if the user is no longer signed in, the grab just finds nothing).
  return String(c.testStatus || '').toLowerCase() === 'error' && (et || le);
}

/** Pure: which of OUR auto-managed web-cookie connections look expired? */
export function providersNeedingRefresh(connections) {
  const wanted = new Set(PROVIDERS.map((p) => p.id));
  const need = new Set();
  for (const c of connections || []) {
    if (!wanted.has(c.provider)) continue;
    if (!/\(auto\)$/.test(String(c.name || ''))) continue;
    if (isExpiredSignal(c)) need.add(c.provider);
  }
  return [...need];
}

// ---------- auto-refresh ----------

/** Grab + push every provider that currently has a signed-in session. */
export async function refreshAll(settings) {
  return runAll(settings);
}

/** Check OmniRoute for expired web-cookie connections and re-grab just those. */
export async function checkExpiredAndRefresh(settings) {
  const conns = await listConnections(settings);
  const need = providersNeedingRefresh(conns);
  if (!need.length) return [];
  const byId = new Map(PROVIDERS.map((p) => [p.id, p]));
  const results = [];
  for (const id of need) {
    const cfg = byId.get(id);
    if (!cfg) continue;
    try {
      const cred = await grabCredential(cfg);
      if (!cred.found) {
        results.push({ id: cfg.id, label: cfg.label, status: 'skip', reason: cred.reason });
        continue;
      }
      await pushConnection(cfg, cred, settings);
      results.push({ id: cfg.id, label: cfg.label, status: 'ok', note: cred.note });
    } catch (e) {
      results.push({ id: cfg.id, label: cfg.label, status: 'error', error: String(e) });
    }
  }
  return results;
}

// ---------- alarms ----------

export async function setAlarms(settings) {
  const s = settings || (await getSettings());
  if (!s.autoRefresh) {
    chrome.alarms.clear(ALARM_FULL);
    chrome.alarms.clear(ALARM_CHECK);
    return;
  }
  const hours = Math.max(1, Math.min(24 * 7, Number(s.refreshHours) || DEFAULT_REFRESH_HOURS));
  chrome.alarms.create(ALARM_FULL, { delayInMinutes: 5, periodInMinutes: hours * 60 });
  chrome.alarms.create(ALARM_CHECK, { delayInMinutes: 2, periodInMinutes: EXPIRY_CHECK_MINUTES });
}
