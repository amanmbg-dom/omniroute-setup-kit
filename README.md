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
  Meta AI, DeepSeek, t3.chat, ChatGPT, Grok, Perplexity…) and pushes them in, with
  auto-refresh so expired sessions re-push themselves
- **`auto` fallback pool** — keyless providers (felo, opencode built-in, agy,
  blackbox, duckduckgo-web, friendliai)

Everything lives in this repo except **one** thing: the script runs
`npm install -g omniroute@3.8.49` (the gateway itself) if it isn't already
installed. No manual cookie copying, no hunting for skills, no extra repos.

## Push to GitHub (optional, for cloning on other machines)

```powershell
gh auth login          # once — opens a browser for the OAuth flow
powershell -ExecutionPolicy Bypass -File push-to-github.ps1
```

The script creates a **private** repo and pushes `main`. Then on any other
machine: `git clone <url>` → run `setup.ps1`. (If you'd rather host it
somewhere else — GitLab, Gitea, a USB stick — the kit is just a folder; copy
it and run `setup.ps1` from there.)

## One command — any new Windows device (even a BRAND-NEW, empty PC)

The kit ships `bootstrap.ps1`, which assumes **nothing but PowerShell and
internet** (PowerShell is built into Windows). It installs the prerequisites
(Git, Node.js LTS, Python, Google Chrome, GitHub CLI — via winget, installing
winget itself first if needed), then runs the full setup.

**This repo is private**, so on a fresh machine the zero-typing path is:

1. On the new PC, log into GitHub → open the repo page → **Code → Download
   ZIP** → extract anywhere
2. Double-click **`install.cmd`** — it installs any missing prerequisites
   automatically, then runs the full setup. That's it.

Already have a machine with Git/Node, or a **public** fork? One line end to
end (or use `irm … | iex` on a truly bare PC for a public repo):

```bash
git clone https://github.com/amanmbg-dom/omniroute-setup-kit.git omniroute-kit && cd omniroute-kit && powershell -ExecutionPolicy Bypass -File setup.ps1
```

The setup is **idempotent** — safe to re-run any time; it skips what's
already configured. Downloads on a fresh PC: the prerequisite installers
(via winget) + OmniRoute (npm) + the flowui bridge's Playwright. Everything
else ships in the repo.

After setup, two one-time manual steps (about 1 minute):

1. **Cookie Pusher** — `edge://extensions` → Developer mode → Load unpacked →
   `%USERPROFILE%\omniroute-cookie-pusher` → click the extension → Grab & push
   sessions (for the free web-cookie providers)
2. **AI images** — `bridge\flow-browser\re-sign-in.cmd` once, sign in to
   Google in the Chrome window that opens (Flow Automation profile). After
   that, `flowui/nano-banana-2` works headless forever, and the `/images`
   command in Claude Code queues a full site's image batch with one prompt.

### After the script (once, ~1 minute)

The extension cannot be installed into the browser automatically, so do this
one manual step:

1. Open `edge://extensions` (or `chrome://extensions`)
2. Turn on **Developer mode**
3. **Load unpacked** → `%USERPROFILE%\omniroute-cookie-pusher`
4. Click the extension icon → **Grab & push sessions**

## What setup.ps1 does

1. Checks Node.js (on a fresh PC `bootstrap.ps1` installs it first)
2. Installs OmniRoute (`npm i -g omniroute@3.8.49`) — the core download
3. Writes the gateway launcher to `~\.omniroute\` and starts the server
4. Logs in to the dashboard (password from `config/local.env`)
5. Adds **NVIDIA NIM** + **OpenCode Zen** with your keys (skips if present)
6. Applies the Zen fixes: Chrome user-agent (Cloudflare 1010 workaround) and
   wider rate-limit budget (the 503 fix)
7. Mints a fresh **per-machine admin API key** for the extension and writes it
   into the copied `config.js` (old keys minted by the kit are revoked first;
   manually-created keys are left alone)
8. Copies the extension to `%USERPROFILE%\omniroute-cookie-pusher`
8b. Installs the **gemini-bridge** (free Nano Banana images via your
    google.com session token — `gflow/nano-banana-2`)
8c. Installs the **flowui bridge** (Google Flow images via your real Chrome
    session — `flowui/nano-banana-2`), **headless by default**, and registers
    the `flowui` **MCP server** in Claude Code (`generate_image` tool) so every
    image request funnels through the same engine
9. Installs the **Claude Code CLI** if missing (`npm i -g
   @anthropic-ai/claude-code`), then **wires Claude Code** to the gateway
   (merges the `ANTHROPIC_*` env block into `~/.claude/settings.json`,
   preserving existing settings), discovers **all `auto/` routes** from the
   gateway into the `/model` picker allowlist, and clears the stale
   gateway-model cache so the picker shows the live catalog
9b. **Extra MCPs + skills.sh**: registers Playwright, Context7, Chrome DevTools,
    Memory, Filesystem, Sequential Thinking, Everything, Fetch and GitHub MCP
    servers (idempotent, GitHub only when `gh` is logged in), installs the
    `skills` CLI and a curated set of high-value skills (tdd, diagnosing-bugs,
    improve-codebase-architecture, grill-me, vercel-react-best-practices,
    deploy-to-vercel)
9c. **Claude Desktop** (official app — the Code tab is Claude Code in a GUI
    and reads the same settings, so it routes through this gateway with **no
    extension**). Downloads the installer from claude.ai if the app isn't
    installed, launches it, and prints the sign-in guide. Standalone helper:
    `setup-desktop.cmd`
10. Registers the gateway **and the flowui bridge** to **auto-start at login**
    (Startup folder)

Flags: `-SkipInstall`, `-SkipProviders`, `-SkipExtension`, `-SkipClaudeCode`,
`-SkipAutoStart`, `-SkipBridge` (gemini-bridge), `-SkipFlowBridge` (flowui),
`-Pull` (git pull the kit first), `-UpdateSkills` (overwrite existing skills,
backing up to `<name>.bak-kit`).

## Update everything on an existing machine — one command

Re-runs are safe and idempotent. To pull the latest kit **and** refresh
skills, extension, commands, MCPs and bridges in one action:

```powershell
# double-click update.cmd inside the kit folder, or from any folder:
powershell -ExecutionPolicy Bypass -File "$HOME\omniroute-kit\setup.ps1" -Pull -UpdateSkills
```

That one command is the whole update:

- `-Pull` runs `git pull --ff-only` first, so the kit, extension, commands
  and skill files are the latest from GitHub (commit or stash local edits
  in the kit first if a pull refuses).
- `-UpdateSkills` re-copies the kit's skills to `~/.claude/skills`, backing
  up any existing copy to `~/.claude/skills/<name>.bak-kit` first. Without
  the flag, already-installed skills are left untouched to protect local
  customizations.
- Everything else re-runs idempotently: extension + fresh per-machine
  token, slash commands, MCP servers, skills.sh, bridges, gateway wiring,
  auto-start.

After updating, reload the Cookie Pusher extension in `edge://extensions`
(Developer mode → reload) so the browser picks up the new files.

## Configuration — `config/local.env`

| Key | Purpose |
|---|---|
| `OMNIROUTE_PORT` | Gateway port (default `20128`) |
| `DASHBOARD_PASSWORD` | Dashboard password (default `CHANGEME` — change it after first login at `http://localhost:20128/admin`) |
| `NVIDIA_NIM_API_KEY` | `nvapi-…` from https://build.nvidia.com (free tier) |
| `OPENCODE_ZEN_API_KEY` | `sk-…` from https://opencode.ai/zen (free tier) |
| `GEMINI_API_KEY` | Google Gemini free tier (AI Studio) |
| `GROQ_API_KEY` | Groq — no card, 30 RPM (https://console.groq.com/keys) |
| `OPENROUTER_API_KEY` | OpenRouter — free `:free` models after a one-time $10 topup (https://openrouter.ai/keys) |
| `GITHUB_MODELS_API_KEY` | GitHub Models — no card (GitHub → Settings → Tokens) |
| `CLOUDFLARE_API_KEY` | Cloudflare Workers AI — no card, 10K neurons/day |
| `MODELSCOPE_API_KEY` | ModelScope — registration, 2K RPD |
| `LLM7_API_KEY` | LLM7.io — no card |
| `OVHCLOUD_API_KEY` | OVHcloud AI Endpoints — registration |
| `OLLAMA_API_KEY` | Ollama Cloud — registration |
| `SAMBANOVA_API_KEY` | SambaNova — registration |
| `AION_API_KEY` | Aion Labs — registration |
| `AGNES_API_KEY` | Agnes AI — registration |
| `CHUTES_API_KEY` | Chutes.ai — registration |
| `AI21_API_KEY` | AI21 Labs — registration |
| `NSCALE_API_KEY` | Nscale — registration |
| `ALIBABA_API_KEY` | Alibaba Model Studio — registration |
| `ZAI_API_KEY` | Z AI (Zhipu) — no card |
| `MISTRAL_API_KEY` | Mistral AI — no card |
| `COHERE_API_KEY` | Cohere — no card |
| `CEREBRAS_API_KEY` | Cerebras — no card |
| `HUGGINGFACE_API_KEY` | Hugging Face — no card |
| `DEEPSEEK_API_KEY` | DeepSeek — registration |
| `XAI_API_KEY` | xAI (Grok) — registration, credit-based |
| `NEBIUS_API_KEY` | Nebius — registration |
| `SILICONFLOW_API_KEY` | SiliconFlow — registration |

Any key left empty simply skips that provider. All of the above come from the
freellm.net free-tier directory (https://freellm.net/free-llm-api-keys/).
Once a key is added, run `setup.ps1` again to wire the provider into the
`/model` picker (OpenRouter free models appear as `openrouter/<model>:free`).

## Using the models

Point any OpenAI-compatible client at `http://localhost:20128/v1` with an
OmniRoute API key, or use the model names directly:

- `nvidia/nvidia/nemotron-ultra-550b` (and every other NIM model)
- `nvidia/...` / `opencode-zen/<model>` — see the dashboard's model list
- `auto/best-coding` / `auto/best-reasoning` / `auto/best-fast` /
  `auto/best-vision` — smart aliases over the whole free pool
- `auto/coding:reliable` — **the default**: health-scored routing that skips
  dead/failed providers (fixes "hitting dead NIM models over and over")
- `combo/qwen` / `combo/glm` / `combo/deepseek` / `combo/lmarena` — per-family
  routing routes over the cookie/web providers: pick the flagship model of the
  family, auto-falling back down its live model list (all thinking levels for
  lmarena, instant/expert/think/search for deepseek, all GLM / Qwen models)
- `combo/lmarena-fast` / `combo/lmarena-slow` — arena by thinking speed:
  `-fast` routes only the `-low`/`-medium` (fast) thinking levels,
  `-slow` only the `-high`/`-xhigh` (slow) ones, so you pick speed explicitly
- `combo/mimo` — Xiaomi MiMo open-source V2.5 / V2.5-Pro (the free open weights,
  **not** the subscription "Claw" flagship with its ~4h/day usage cap), routed
  across every provider that serves them (opencode-zen/oc free tier, openrouter,
  lmarena, llm7, huggingchat/hf, mcode)

## Claude Code

`setup.ps1` wires Claude Code to the gateway by merging an `env` block into
`~/.claude/settings.json` (your existing permissions/hooks are preserved, and
the original is backed up to `settings.json.bak-kit`):

| Env var | Value | Why |
|---|---|---|
| `ANTHROPIC_BASE_URL` | `http://localhost:20128` | Claude Code appends `/v1/messages` itself — no `/v1` suffix |
| `ANTHROPIC_AUTH_TOKEN` | `omniroute` | the gateway's localhost magic token — no secret stored in settings.json |
| `ANTHROPIC_MODEL` | `auto/coding:reliable` | default model — the reliability-first auto combo: it scores providers by health and auto-falls-back when a model is dead, so NIM outages never interrupt a session (any `nvidia/…`, `opencode-zen/…`, `auto/best-*` also works) |
| `ANTHROPIC_SMALL_FAST_MODEL` | `auto/best-fast` | background/summarization tasks |
| `CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY` | *(not set)* | Intentionally OFF: it makes Claude Code refetch the live catalog on every start and filter it to claude-named models, clobbering the curated cache and collapsing `/model` to just Default. The picker list is driven by `availableModels` instead (see `fix-model-cache.ps1`) |
| `CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT` | `1` | stops window enforcement errors on non-Claude models |

Then just run `claude` in any folder — traffic goes to the free pool. Switch
models anytime with `/model` in the CLI, or set a specific one. For quick
tasks, use the `/fast` command (ships with the kit) to switch to
`auto/best-fast` latency-first routing; it also tells the agent to skip
unnecessary verification and answer directly.

**Cycle the model in one keystroke:** the `/cycle-model` command (ships with
the kit) rotates the default through `auto/coding:reliable` → `auto/best-coding`
→ `auto/best-fast` (pass a slot to jump straight there: `/cycle-model fast`).
It updates `~/.claude/settings.json` for new sessions and prints the exact
`/model` value to apply to the current one. In VS Code, `Ctrl+Alt+M` focuses
the Claude Code input so `/cycle-model` is one keystroke + Enter away
(keybinding written by `setup.ps1` to `%APPDATA%\Code\User\keybindings.json`).

```
ANTHROPIC_MODEL=nvidia/nvidia/nemotron-ultra-550b claude
```

The `/model` picker shows **every `auto/` route** (reliable, best-coding,
best-vision, best-fast, best-chat, per-family routes like `auto/glm` /
`auto/minimax` / `auto/zai`, chaos, offline… — 38 in total) via
`availableModels`. `fix-model-cache.ps1` mirrors those `auto/*` majors into
`availableModels`, so the **VS Code** extension's model picker lists the same
routes as the terminal `/model` picker.

**Per-family routing routes** — `fix-model-cache.ps1` also creates
`combo/*` routes for the cookie/web providers (`combo/qwen`, `combo/glm`,
`combo/deepseek`, `combo/lmarena`, plus `combo/lmarena-fast` and
`combo/lmarena-slow` for arena by thinking speed) via the dashboard API. Each
picks the best live model of its family (flagship first, then every chat-capable
route of that provider), so `combo/qwen` auto-falls-back across qwen3.8-max →
qwen3.7-max → qwen3.7-plus, `combo/deepseek` across v4-pro → v4-flash →
chat/reasoner/R1, and `combo/glm` / `combo/lmarena` across the whole GLM and
arena model lists (including the `-low/-medium/-high/-xhigh` thinking levels —
"fast/slow"). `combo/lmarena-fast` restricts to the `-low`/`-medium` arena
levels and `combo/lmarena-slow` to the `-high`/`-xhigh` ones, so you can route
by speed explicitly. They're mirrored into `availableModels` too, so the picker
lists them like any other route. If a picker ever looks empty or partial, the
model cache is stale — clear `~/.claude/cache/gateway-models.json` (setup.ps1
does this automatically) and restart Claude Code.

Skip with `-SkipClaudeCode` if you want to leave Claude Code alone.

## Using the models in OTHER apps (not just Claude Code)

The gateway speaks standard **OpenAI-compatible** APIs, so any app that lets you
point it at a custom endpoint (chat UIs, IDEs, scripts, other agents) can use
the same free pool:

```
Base URL : http://localhost:20128/v1          (or http://<vps>:20128/v1)
API key  : omniroute                           (or your minted key)
Model    : any id from http://localhost:20128/v1/models
```

- **Chat completions** — OpenAI SDK / curl `POST /v1/chat/completions` (this is
  exactly what every probe above uses):
  ```bash
  curl http://localhost:20128/v1/chat/completions \
    -H "Authorization: Bearer omniroute" -H "Content-Type: application/json" \
    -d '{"model":"auto/coding:reliable","messages":[{"role":"user","content":"hello"}]}'
  ```
- **Anthropic-format** (`POST /v1/messages`) — for apps that speak Claude's API.
- **Images** — `POST /v1/images/generations` (e.g. `flowui/nano-banana-2`).

Set the model to any picker entry: `auto/best-coding`, `auto/coding:reliable`,
`nvidia/nvidia/nemotron-ultra-550b`, `combo/qwen`, `combo/mimo`, … For apps that
have a model dropdown but no free-text field, add the id to their custom-model
list and pick it. The gateway is OpenAI-compatible end to end, so everything
Claude Code can reach is reachable the same way from any other tool.

## Claude Desktop (official app — no extension)

Anthropic's official desktop app (`claude.com/download`) has a **Code tab**
that *is* Claude Code in a GUI (chat + diff review + integrated terminal +
browser preview), and it reads the **same `~/.claude/settings.json`** as the
CLI. That means it inherits the gateway wiring above automatically — run
`setup-desktop.cmd` (or setup step 9c) to install it, then:

1. Open the app → sign in with any Claude account
2. Click the **Code** tab → Environment: **Local** → pick a project folder
3. Type a message — it routes through `http://localhost:20128` (your free
   pool), model `auto/coding:reliable`, all 38 `auto/` routes in the model
   menu (Ctrl+Shift+I). **No VS Code extension needed** — you can uninstall it.

Two honest notes:

- The app's model *dropdown* deliberately only displays Claude-family names;
  `ANTHROPIC_MODEL` still pins your combo, so this is cosmetic. (Same behavior
  as other gateways — documented in the Claude Desktop routing guides.)
- **Deep option**: Claude Desktop has a native **Gateway** inference provider
  (Settings → Developer → Inference provider = Gateway → base
  `http://localhost:20128`, auth `bearer` / `omniroute`) that routes the app's
  own inference — Chat tab included. It only appears in some builds/plans; if
  you don't see it, the Code-tab route above is the one to use.

The desktop app needs **Git for Windows** on first launch — the kit's
`bootstrap.ps1` installs it.

## Free AI images (Google Flow — `flowui`)

`flowui/nano-banana-2` (Nano Banana 2) generates premium images through your
**real, signed-in Google session** — no API key, no credits, no captcha. The
bridge drives the actual Google Flow web app in a dedicated Chrome profile
(headless by default). Setup: sign in once with `bridge\flow-browser\re-sign-in.cmd`;
the bridge then auto-starts at login.

Every caller hits the **same bridge → same Chrome session → same model → same
ratio mapping**, so image quality is consistent whether you ask via the
`generate_image` **MCP tool** in Claude Code, via the `single-page-site`
skill, or via raw HTTP:

```bash
curl -s -X POST http://127.0.0.1:20128/v1/images/generations \
  -H "Authorization: Bearer omniroute" -H "Content-Type: application/json" \
  -d '{"model":"flowui/nano-banana-2","prompt":"a red sports car, studio lighting","size":"1536x1024","n":4}'
```

Sizes: `1792x1024` (16:9 hero) · `1536x1024` (4:3) · `1024x1024` (square) ·
`1024x1536` (3:4) · `1024x1792` (9:16). Flow gives free daily image credits
per Google account — on exhaustion, switch account or wait for the reset.
Details: `bridge\flow-browser\README-flowui.md`.

## Remote VPS — run the provider farm in the cloud

Want the AI tabs off your machine entirely? The kit ships a complete VPS
deploy package (`vps/`): **setup-vps.sh** installs OmniRoute + a headless
Chromium provider profile + a systemd service + a reclamation-proof keep-alive
cron + a Cloudflare/Tailscale tunnel on any fresh Ubuntu box, then mints an
admin API key. Your laptop becomes a thin client pointing at the VPS.

```bash
# on the VPS (one shot; cloudflare tunnel + random password by default)
bash setup-vps.sh

# on your laptop afterwards (ships with the kit, also at ~/.omniroute)
powershell -ExecutionPolicy Bypass -File ~\.omniroute\omni-remote.ps1
powershell -ExecutionPolicy Bypass -File ~\.omniroute\omni-local.ps1   # switch back
```

`omni-remote.ps1` health-checks the tunnel, SSH-starts the service if it's
down (needs `SSH_HOST` in `~/.omniroute/remote.env`), rewrites
`~/.claude/settings.json` to the VPS, and prints the key. Session helpers in
`~/.omniroute/vps/`: `import-cookies.sh` (import Cookie Pusher cookie JSONs
into the headless profile), `refresh-sessions.sh` (headless session refresh),
`signin.sh` (one-time interactive sign-in, needs install with `--with-gui`).

Honest notes: free tiers (Oracle Always Free, Google, AWS) all require a credit
card for signup, and Oracle reclaims idle instances — the included keep-alive
cron (10-min cadence) burns a little CPU to prevent that, so prefer 24/7
running over stop/start. trycloudflare.com quick-tunnel URLs are ephemeral; add
a DNS route with your own domain for a permanent URL.

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
