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
- **Codex CLI wired too** — OpenAI's agent CLI gets the same free pool via the
  gateway's native Responses API (`~/.codex/config.toml`, one line: `codex`)

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

### Cloning on another machine (your own keys)

`config/local.env` is **gitignored** — it never leaves your machine. To set up
another machine with your own keys:

```powershell
# 1. Clone the repo
gh repo clone amanmbg-dom/omniroute-setup-kit omniroute-kit
# or: git clone <your-fork-url> omniroute-kit

# 2. Copy your local.env (from the other machine, or recreate it)
#    Option A: copy the file manually (USB, secure transfer, etc.)
#    Option B: recreate it — the example template is in the repo:
copy config\local.env.example config\local.env
#    Then fill in your API keys in config\local.env

# 3. Run setup
powershell -ExecutionPolicy Bypass -File setup.ps1
```

**Quick transfer between your own machines:** if both machines have the kit,
you can copy `config\local.env` directly (USB drive, secure cloud paste,
`scp`, etc.) — the file is small and plain text.

### Forking for others (private repo, no keys)

If you want someone else to use the kit with your private repo:

1. **Create a fork** of the private repo on GitHub (Settings → Forks → Allow
   forking to private repos, or just share the repo directly)
2. They clone it — `config/local.env` is gitignored, so **no keys leak**
3. They copy `config/local.env.example` to `config/local.env` and fill in
   their own API keys
4. Run `setup.ps1`

The `.example` file shows every key with its registration URL and what it
does. Keys left blank are simply skipped — the free providers still work
without any keys at all (the `auto` fallback pool: felo, opencode built-in,
agy, blackbox, duckduckgo-web, friendliai).

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
8d. Installs the **mimo-web bridge** (free MiMo V2.5 / V2.5-Pro chat via your
    aistudio.xiaomimimo.com session — `mimo-web/*` + `combo/mimo-web`; the
    Cookie Pusher sends the session straight to the bridge, since the gateway
    ships no `xiaomimimo-web` executor)
9. Installs the **Claude Code CLI** if missing (`npm i -g
   @anthropic-ai/claude-code`), then **wires Claude Code** to the gateway
   (merges the `ANTHROPIC_*` env block into `~/.claude/settings.json`,
   preserving existing settings), enables gateway model discovery
   (`CLAUDE_CODE_USE_GATEWAY` + `CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY`),
   patches the installed native binary so the `/model` picker shows the full
   live catalog (`patch-claude-picker.mjs`), and seeds the fallback
   gateway-model cache
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
9d. Installs the **Codex CLI** (`npm i -g @openai/codex`) and wires it to the
    gateway (`~/.codex/config.toml` → `model_provider omniroute`, base
    `http://localhost:20128/v1`). Current Codex accepts only the Responses API
    for custom providers, and the gateway implements `/v1/responses` natively,
    so no adapter is needed. Existing configs without the omniroute provider
    are backed up to `config.toml.bak-kit` first.
10. Registers the gateway, **flowui**, **gflow** (gemini-bridge) and **mimo-web**
    bridges plus the logon self-heal to **auto-start at login — fully hidden**.
    Startup holds tiny `.vbs` wrappers that run each service with no console
    window and no flash (`launcher\start-hidden.vbs` is the same mechanism for
    manual use). The `.cmd` launchers stay in the kit for visible manual runs.
    The `OmniRoute-Watchdog` scheduled task (every 5 min **and** at logon)
    probes the gateway **and all three bridges**, restarts anything that is
    down (hidden), and re-syncs the `combo/*` routes after a gateway restart.

Flags: `-SkipInstall`, `-SkipProviders`, `-SkipExtension`, `-SkipClaudeCode`,
`-SkipCodex`, `-SkipAutoStart`, `-SkipBridge` (gemini-bridge),
`-SkipFlowBridge` (flowui), `-SkipMimoBridge` (mimo-web), `-Pull` (git pull the
kit first), `-UpdateSkills` (overwrite existing skills, backing up to
`<name>.bak-kit`).

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
- `mimo-web/<model>` / `combo/mimo-web` — the **MiMo web version**: your
  aistudio.xiaomimimo.com session through the local `mimo-web-bridge`
  (`bridge/mimo-web-bridge`, port 20135). The gateway registers `xiaomimimo-web`
  but ships no executor for it, so the bridge implements the web chat API
  (`/open-apis/bot/chat`, cookie auth, `<think>` SSE) behind the gateway's
  supported `openai-compatible` node mechanism — same pattern as `gflow`/
  `flowui`. `fix-model-cache.ps1` auto-starts it; sign in at
  aistudio.xiaomimimo.com, then Cookie Pusher → Grab & push sessions

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
| `CLAUDE_CODE_USE_GATEWAY` | `true` | registers the auth token as a gateway credential — Claude Code >= 2.1.233 only fetches the gateway catalog for `/model` when this is set |
| `CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY` | `true` | turns on the gateway `/v1/models` bootstrap fetch; `fix-model-cache.ps1` byte-patches the installed native binary (`patch-claude-picker.mjs`) so the picker keeps **every** route instead of filtering to claude-named ids. The patch is re-applied automatically after each Claude Code update |
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

The `/model` picker shows the **full live gateway catalog** (auto/* majors,
combo/* routes, mimo-web/*, lmarena/*, qwen-web/zai-web/deepseek-web,
NVIDIA NIM, OpenCode/OpenRouter free routes — 2600+ entries). This is driven
by Claude Code's gateway model discovery (`CLAUDE_CODE_USE_GATEWAY` +
`CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY` + the `patch-claude-picker.mjs`
native-binary patch, applied by `fix-model-cache.ps1`). The patch covers BOTH
gateway-discovery filter sites in the binary — the `[Bootstrap]` fetch and the
`[gatewayDiscovery]` periodic refetch (the refetch used to replace the cached
model list with its claude/anthropic-filtered result, collapsing the picker
again — the “it worked, then broke again” loop) — and is applied to the VS
Code extension binary AND the standalone `~/.local/bin/claude.exe` CLI. It is
re-applied at every logon and every 5 minutes by the `OmniRoute-Watchdog`
task (`-PickerOnly`), so a Claude Code auto-update self-heals within minutes
instead of at the next reboot. The gateway-model cache and `availableModels`
are seeded with the full catalog + combo/* routes as a fallback for older
builds — a full cache also survives an unpatched refetch, keeping the picker
complete even in the update window.

**Per-family routing routes** — `fix-model-cache.ps1` also creates
`combo/*` routes for the cookie/web providers (`combo/qwen`, `combo/glm`,
`combo/deepseek`, `combo/lmarena`, plus `combo/lmarena-fast` and
`combo/lmarena-slow` for arena by thinking speed, and `combo/mimo-web` for the
MiMo web bridge) via the dashboard API. Each
picks the best live model of its family (flagship first, then every chat-capable
route of that provider), so `combo/qwen` auto-falls-back across qwen3.8-max →
qwen3.7-max → qwen3.7-plus, `combo/deepseek` across v4-pro → v4-flash →
chat/reasoner/R1, and `combo/glm` / `combo/lmarena` across the whole GLM and
arena model lists (including the `-low/-medium/-high/-xhigh` thinking levels —
"fast/slow"). `combo/lmarena-fast` restricts to the `-low`/`-medium` arena
levels and `combo/lmarena-slow` to the `-high`/`-xhigh` ones, so you can route
by speed explicitly. They're mirrored into `availableModels` too, so the picker
lists them like any other route. If a picker ever looks empty or partial,
run `fix-model-cache.ps1` (it re-applies the binary patch, re-ensures the env
vars, and reseeds the cache — a scheduled task runs it at logon, so Claude
Code auto-updates self-heal) and reload the VS Code window.

Skip with `-SkipClaudeCode` if you want to leave Claude Code alone.

## Codex CLI (OpenAI's agent — same free pool)

`setup.ps1` also installs the **Codex CLI** (`npm i -g @openai/codex`) and
wires it to the gateway by writing `~/.codex/config.toml`:

```toml
model = "auto/coding:reliable"
model_provider = "omniroute"

[model_providers.omniroute]
name = "OmniRoute free pool (localhost:20128)"
base_url = "http://localhost:20128/v1"
experimental_bearer_token = "omniroute"
```

Current Codex accepts only the **Responses API** for custom providers
(`wire_api = "responses"` is the only supported value), and the gateway
implements `/v1/responses` natively — so Codex points straight at it, no
adapter. The token is the gateway's localhost magic token, not a real secret
(same value as Claude Code's `ANTHROPIC_AUTH_TOKEN`). If a
`~/.codex/config.toml` already exists **without** the omniroute provider, it
is backed up to `config.toml.bak-kit` before the kit's block is written, so
local customizations are never silently clobbered.

Then just run `codex` in any folder — traffic goes to the free pool. Switch
models any time with `-m`, or use it non-interactively:

```bash
codex -m auto/best-fast
codex -m combo/qwen
codex -m nvidia/nvidia/nemotron-ultra-550b
codex exec "explain this repo"
```

### The `/model` picker shows the gateway routes

By default Codex only lists OpenAI's built-in models in `/model`. The kit
generates a **model catalog** from the live gateway (same curated list the
Claude Code picker gets — `auto/*`, `combo/*`, `lmarena/*`, `qwen-web/*`,
`zai-web/*`, `deepseek-web/*`, `mimo-web/*`, alive `nvidia/*`, OpenCode/OpenRouter
free routes) and wires it into `config.toml`:

```toml
model_catalog_json = "C:/Users/<you>/.codex/model-catalogs/omniroute.json"
```

So the picker lets you browse and switch between all ~270 gateway routes.
`fix-model-cache.ps1` rebuilds the catalog from the live catalog (run it after
adding providers, or the `OmniRoute-Watchdog` scheduled task refreshes it
after a gateway restart), and the path uses forward slashes because TOML
basic strings treat backslashes as escapes.

The kit also ships **model profiles** — `codex --profile <name>` overlays
`~/.codex/<name>.config.toml` and switches the route in one flag:

| Profile | Route | When |
|---|---|---|
| `--profile fast` | `auto/best-fast` | quick questions, low-latency tasks |
| `--profile coding` | `auto/best-coding` | everyday coding |
| `--profile reasoning` | `auto/best-reasoning` | hard problems, math, planning |
| `--profile vision` | `auto/best-vision` | screenshots / image input |

```bash
codex --profile reasoning "design the retry/backoff algorithm"
codex exec --profile fast "summarize this diff"
```

Skip with `-SkipCodex` if you want to leave Codex alone.

## Gateway watchdog (self-healing)

The gateway occasionally wedges: the port keeps listening but HTTP requests
hang (CLOSE_WAIT sockets pile up) — which looks like "the routes disappeared"
and makes tool calls time out. `setup.ps1` registers an
**`OmniRoute-Watchdog`** scheduled task (every 5 minutes) that:

1. Probes `http://127.0.0.1:20128/v1/models` — exits immediately when healthy.
2. If a listener is unresponsive for 30s, kills it (the gateway package's own
   supervisor respawns the server within seconds).
3. Starts the launcher only if nothing is running at all.
4. Re-syncs the `combo/*` routes and the Codex model catalog after a restart.

`launcher/watchdog.ps1` runs from a stable copy at `~/.omniroute/watchdog.ps1`
and logs to `~/.omniroute/watchdog.log`. The gateway launcher also raises the
Node heap (`NODE_OPTIONS=--max-old-space-size=6144`) — the wrapper honors a
user-pinned heap — so the 2600+ route catalog / 250-model combo resolution
stays well under memory pressure — and the watchdog proactively restarts the
gateway if its working set climbs past 5 GB (the wedge has been seen at ~2 GB
and growing), before it can stall.

## Headless (invisible) — browsers AND console windows

Everything the kit starts runs with **nothing visible on screen**:

- **Browsers**: the only web-cookie work that opens a real browser is the
  **z.ai captcha worker** (`ZAI_CAPTCHA_WORKER`) — a Chrome window appears for a
  few seconds whenever z.ai challenges the account (HTTP 405) and needs a fresh
  Aliyun anti-bot token. This is the ONE component that cannot run headless:
  Aliyun's anti-bot detects headless Chrome (verifyResult F001) and refuses the
  solve, so the 405 challenge never clears and zai stays broken. The kit keeps
  the worker headed (`patch-zai-captcha-headed.mjs`, same-length byte replace,
  idempotent, re-applied by `fix-model-cache.ps1` / the logon `FixModelCache.cmd`
  after every gateway update). The Google Flow image bridge is already headless
  by default (`FLOW_HEADLESS=1`), the gflow/mimo bridges are plain HTTP servers,
  and the Cookie Pusher extension needs no browser at all.
- **Console windows**: every Startup entry is a tiny `.vbs` wrapper that runs
  the service with window style 0 — no console window, no flash at login. The
  gateway starts with `--no-open` (no dashboard tab), and the watchdog, the
  logon self-heal and every auto-restart use `-WindowStyle Hidden` / `SW_HIDE`
  as well. The `.cmd` launchers in the kit still show output when you run them
  manually — only the automatic paths are invisible.

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

- `config/local.env` contains **live API keys**. It is **gitignored** and
  never committed to the repo. Keep the repo private; if you ever plan to
  make it public, empty the keys first (the script just skips empty ones).
- `config/local.env.example` is a **safe template** — no real keys, just
  placeholders and registration URLs. It IS committed so others know what
  to fill in.
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
