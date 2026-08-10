# OmniRoute Cookie Pusher

A tiny browser extension that grabs your signed-in sessions for OmniRoute's
**web-cookie providers** (HuggingChat, Gemini Web, Qwen, Z.ai, Yuanbao, Arena,
ZenMux, Meta AI, t3.chat, plus your ChatGPT/Grok/Poe/etc. logins) and pushes
them straight into the local OmniRoute gateway — no copy-pasting cookies by
hand.

This copy is managed by the kit's `setup.ps1`: it is copied to
`%USERPROFILE%\omniroute-cookie-pusher` and `config.js` is filled with a fresh
per-machine admin token.

## Why this exists

Chrome/Edge now encrypt cookies with **app-bound encryption** (the `v20`
scheme), which only the browser itself can decrypt. A script can't read your
cookies — but the browser can, through an extension. This extension uses
`chrome.cookies` for cookies and `chrome.scripting` for localStorage tokens,
then re-uses the exact same login + push API the OmniRoute dashboard uses.

## Install (one time, ~1 minute)

1. Run `setup.ps1` from the kit first (it copies this folder + mints the token).
2. Open `chrome://extensions` (Edge: `edge://extensions`).
3. Turn on **Developer mode** (top-right toggle).
4. Click **Load unpacked** and select:
   ```
   %USERPROFILE%\omniroute-cookie-pusher
   ```
5. Pin the extension (puzzle icon → 📌 "OmniRoute Cookie Pusher").

(Works in both Chrome and Edge. Note: Chrome's official builds block
command-line `--load-extension` automation, but the manual **Load unpacked**
flow above is fully supported.)

## Use

1. Make sure OmniRoute is running (`http://localhost:20128` answers).
2. Click the extension icon.
3. Click **Grab & push sessions**.

Each provider shows a status:

- **✓ pushed** — a session was found and sent to OmniRoute
- **not signed in** — no cookies/token for that site (sign in there first)
- **open tab needed** — the site keeps its token in localStorage (Qwen,
  DeepSeek, Kimi, Hailuo, t3.chat); keep a tab open for that site, then click
  again
- **error** — hover the row for details (usually "login failed" → wrong
  password, or the gateway is down)

Sessions expire. When a provider stops working, just re-open the site, and run
the grab again — the push **replaces** the old connection (each provider keeps
one connection named "… (auto)").

## Settings

Open the **Settings** section in the popup:

- **OmniRoute URL** — default `http://localhost:20128`
- **API key (Bearer)** — an admin-scope OmniRoute access token, minted by
  `setup.ps1` into `config.js`. To rotate or create another: OmniRoute
  dashboard → **Settings → API Keys**, or run
  `omniroute tokens create --name "Cookie Pusher" --scope admin` and paste it
  here (it persists in `chrome.storage.local`).
- **Auto-refresh sessions** (default ON) — see below
- **Full refresh every** — 2h / 6h / 12h / 24h / 1 week (default 6h)

The extension only talks to the URL above. Credentials never leave your
machine. The API key grants local OmniRoute admin access — treat it like a
password and don't share `config.js`.

## Auto-refresh

With **Auto-refresh** on (default), the extension's background worker:

1. **Scheduled full grab** — re-grabs and re-pushes *all* signed-in sessions
   every N hours (the setting above), so expiring cookies never go stale.
2. **Expired-session check** — every 30 minutes it asks OmniRoute for the
   connection list and re-pushes any of our web-cookie connections that
   OmniRoute reports as failed/expired (`forbidden`, `401/403`,
   `SESSION_EXPIRED`-style errors) — without waiting for the full schedule.

Re-pushes are **upserts**: each provider keeps exactly one `… (auto)`
connection (the old one is deleted before the new one is created), so
auto-refresh never piles up duplicates.

Notes:
- Alarms only fire **while the browser is running** (that's a browser
  limitation, not a bug) — sessions are re-grabbed the next time the browser
  is open.
- localStorage-only providers (Qwen, DeepSeek, Kimi, Hailuo, t3.chat) are
  refreshed only if a tab for that site is open at alarm time; otherwise they
  show as "skipped" and get picked up on the next scheduled run.
- You can also hit **Check expired** in the popup to run the expiry check on
  demand.

## Why an API key and not the dashboard password?

OmniRoute rejects cookie-authed dashboard mutations from foreign origins
(CSRF/origin guard). Bearer-token (API key) requests skip that guard entirely,
so the extension authenticates with a token instead of a password session.

## Which providers are covered

| Provider | What gets pushed | Needs open tab? |
|---|---|---|
| HuggingChat | full cookie header | no |
| Gemini Web | `__Secure-1PSID` (+ `__Secure-1PSIDTS`) | no |
| Z.ai GLM | full cookie header (`token=`) | no |
| Tencent Yuanbao | full cookie header | no |
| Arena (LMArena) | full cookie header | no |
| Meta AI Muse | full cookie header | no |
| ZenMux | full cookie header | no |
| Qwen Web | `token` (localStorage) → `tongyi_sso_ticket` fallback | yes (or cookie fallback) |
| t3.chat | `convex-session-id` + cookie header | yes |
| DeepSeek Web | `userToken` | yes |
| ChatGPT / Perplexity / Poe / Blackbox | session cookie | no |
| Grok / Claude Web / Venice / Copilot / v0 / Dola | full cookie header | no |
| Kimi | `access_token` → `kimi-auth` fallback | yes (or cookie fallback) |
| Hailuo | `_token` | yes |
| Notion AI | `token_v2` value | no |
| Gemini Business | `__Secure-1PSID` | no |

## Files

- `manifest.json` — MV3 manifest (`alarms` permission, module service worker)
- `config.js` — default URL + API key (written by setup.ps1 — local secret)
- `core.js` — shared logic (catalog, grab, push/upsert, expiry, alarms)
- `popup.html` / `popup.js` — manual grab + settings UI
- `background.js` — scheduled + expiry-driven auto-refresh worker
