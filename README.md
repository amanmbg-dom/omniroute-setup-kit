# OmniRoute Setup Kit — free models, one click

Clone this repo on any Windows machine, run **one PowerShell script**, and you
get the entire working free-model gateway:

- **OmniRoute** on `http://localhost:20128` (auto-starts at login)
- **NVIDIA NIM** — 100+ free models: Nemotron Ultra 550B, Omni 30B vision,
  DeepSeek V4 Pro/Flash, GLM-5.2, MiniMax, Qwen…
- **OpenCode Zen** — free tier (deepseek-v4-flash-free, GPT-5.x line),
  including the Cloudflare user-agent + rate-limit fixes that make it actually
  work
- **Cookie Pusher extension** — grabs your signed-in sessions for 24
  web-cookie providers (HuggingChat, Gemini Web, Qwen, Z.ai, Yuanbao, Arena,
  Meta AI, t3.chat, ChatGPT, Grok, Perplexity…) and pushes them in, with
  auto-refresh so expired sessions re-push themselves
- **`auto` fallback pool** — keyless providers (felo, opencode built-in, agy,
  blackbox, duckduckgo-web, friendliai)

Everything lives in this repo except **one** thing: the script runs
`npm install -g omniroute@3.8.49` (the gateway itself) if it isn't already
installed. No manual cookie copying, no hunting for skills, no extra repos.

## Quick start

```powershell
git clone <this-repo-url> omniroute-kit
cd omniroute-kit
powershell -ExecutionPolicy Bypass -File setup.ps1
```

That's it. The script is **idempotent** — safe to re-run any time; it skips
what's already configured.

### After the script (once, ~1 minute)

The extension cannot be installed into the browser automatically, so do this
one manual step:

1. Open `edge://extensions` (or `chrome://extensions`)
2. Turn on **Developer mode**
3. **Load unpacked** → `%USERPROFILE%\omniroute-cookie-pusher`
4. Click the extension icon → **Grab & push sessions**

## What setup.ps1 does

1. Checks Node.js (install with `winget install OpenJS.NodeJS.LTS` if missing)
2. Installs OmniRoute (`npm i -g omniroute@3.8.49`) — the only download
3. Writes the gateway launcher to `~\.omniroute\` and starts the server
4. Logs in to the dashboard (password from `config/local.env`)
5. Adds **NVIDIA NIM** + **OpenCode Zen** with your keys (skips if present)
6. Applies the Zen fixes: Chrome user-agent (Cloudflare 1010 workaround) and
   wider rate-limit budget (the 503 fix)
7. Mints a fresh **per-machine admin API key** for the extension and writes it
   into the copied `config.js` (old keys minted by the kit are revoked first;
   manually-created keys are left alone)
8. Copies the extension to `%USERPROFILE%\omniroute-cookie-pusher`
9. Registers the gateway to **auto-start at login** (Startup folder)

Flags: `-SkipInstall`, `-SkipProviders`, `-SkipExtension`, `-SkipAutoStart`.

## Configuration — `config/local.env`

| Key | Purpose |
|---|---|
| `OMNIROUTE_PORT` | Gateway port (default `20128`) |
| `DASHBOARD_PASSWORD` | Dashboard password (default `CHANGEME` — change it after first login at `http://localhost:20128/admin`) |
| `NVIDIA_NIM_API_KEY` | `nvapi-…` from https://build.nvidia.com (free tier) |
| `OPENCODE_ZEN_API_KEY` | `sk-…` from https://opencode.ai/zen (free tier) |

Any key left empty simply skips that provider.

## Using the models

Point any OpenAI-compatible client at `http://localhost:20128/v1` with an
OmniRoute API key, or use the model names directly:

- `nvidia/nvidia/nemotron-ultra-550b` (and every other NIM model)
- `nvidia/...` / `opencode-zen/<model>` — see the dashboard's model list
- leave the model blank for the `auto` pool

Claude Code / VS Code: set `ANTHROPIC_BASE_URL` to the OmniRoute endpoint and
`ANTHROPIC_AUTH_TOKEN` to an OmniRoute API key, then pick a model name above.

## What's NOT included (by design)

- **Node.js** — a prerequisite; the script checks for it
- **Your browser sessions** — the extension can only grab cookies for sites
  you're signed in to in the browser you install it on; run "Grab & push
  sessions" after signing in

## Security notes

- `config/local.env` contains **live API keys**. Keep this repo **private**;
  if you ever plan to share/publish it, empty the keys and distribute them
  out-of-band (the script just skips empty ones).
- The dashboard password defaults to `CHANGEME` — change it in Settings on
  first login. The gateway listens on all interfaces and stores your keys.
- The extension's token grants local OmniRoute admin — it never leaves the
  machine, but don't share `config.js`.
- The gateway only runs while the machine is on. For 24/7 access, run it on an
  always-on box (old laptop/RPi/phone or a VPS) and point the extension's URL
  at it.

## Troubleshooting

- **`Connection refused` on 20128** — the gateway didn't start; check
  `%USERPROFILE%\.omniroute\logs`, then re-run `setup.ps1`.
- **Zen gives 403/1010** — the user-agent fix wasn't applied; re-run the
  script (it patches the connection in place).
- **Zen 503s** — the rate-limit budget is too tight for the slow cold start;
  the script's `rateLimitOverrides` fix handles this; first call can take
  30-80s.
- **Extension shows "error" for a provider** — session expired; visit the site,
  sign in, hit "Grab & push sessions" again.
- **"open tab needed"** — Qwen/DeepSeek/Kimi/Hailuo/t3.chat keep tokens in
  localStorage; keep that site's tab open and click again.
