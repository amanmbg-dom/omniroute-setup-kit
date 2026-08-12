# OmniRoute — The Complete Plain-English Guide

*A guide to every function of OmniRoute (v3.8.49), written for a normal technical person. No jargon walls — if you can use a command line and a browser, you can use everything here.*

---

## 1. What OmniRoute actually is

Imagine you have 20 different shops (AI providers) that all sell slightly different products. Each shop has its own door, its own rules, and its own membership card. OmniRoute is the **one front door you install on your own computer** that connects to all of them for you. Your AI tools (Claude Code, VS Code extensions, scripts) talk to *only* this front door, and OmniRoute decides which real shop to run to behind the scenes — switching instantly if one shop is closed, slow, or out of stock.

Concretely:

- It runs as a **local server** on your machine at `http://localhost:20128`.
- It speaks the **same language every AI tool already speaks** (the "OpenAI-compatible" API), so you don't change your tools — only their address.
- It holds **290+ providers** in its catalog, **90+ of them free** (no credit card).
- It does the boring-but-important work for you: **fallback** (if one provider fails, silently try the next), **compression** (uses fewer tokens so free limits last longer), **cost tracking**, **caching**, **memory**, and **security**.
- **Everything stays on your machine.** Your API keys are encrypted on disk (AES-256-GCM). No account, no cloud, no telemetry by default.

> **Analogy for the whole thing:** OmniRoute is the receptionist + dispatcher + accountant for all your AI providers. You hand it a request; it picks the best provider, pays attention to who's tired (rate-limited), remembers the past (memory), shrinks the paperwork (compression), and gives you a receipt (cost reports).

---

## 2. The big picture — how a request flows

```
Your tool (Claude Code / script / VS Code)
        │  "chat, model=auto, ..."
        ▼
OmniRoute at http://localhost:20128/v1
        │ 1. security checks (key valid? policy allows?)
        │ 2. compression pipeline (shrink the prompt)
        │ 3. routing (which provider? which strategy?)
        │ 4. resilience (is that provider healthy? try next if not)
        ▼
Real provider (NVIDIA NIM, OpenCode Zen, HuggingChat, GitLab Duo, ...)
        │  answer comes back
        ▼
OmniRoute (un-compresses, logs usage + cost, caches if asked)
        │
        ▼
Back to your tool
```

Every step is optional and configurable. The simplest install works with zero configuration.

---

## 3. The Dashboard (the web admin panel)

Open `http://localhost:20128/admin` (or just `localhost:20128`) in your browser. This is the visual control room. Main areas:

| Area | What it's for |
|---|---|
| **Providers** | Add/remove provider connections (API keys, OAuth logins, browser-cookie sessions) |
| **Endpoints** | Shows you the exact Base URL + API key to paste into any tool |
| **Models** | Browse the catalog, search, test models |
| **Combos** | Build routing chains ("use this, fall back to that") |
| **Keys** | Create/manage the API keys used to talk to OmniRoute itself |
| **Usage / Cost / Quota** | See what you've used, what it cost, what's left |
| **Cache** | See cached responses, clear the cache |
| **Logs** | See every request that went through |
| **Settings / Environment** | Server config, port, security, compression |
| **Free Tiers** | A live honest budget of all your free provider limits combined |

The dashboard and the CLI control the **same** server — anything you do in one shows in the other.

---

## 4. Providers — the "connections"

A **provider** is one way to get AI. OmniRoute has a catalog of 290+; you create a **connection** to the ones you want to use. A connection is one of three kinds:

1. **API key** — you paste a key (e.g. NVIDIA NIM: `nvapi-...`, OpenCode Zen: `sk-...`).
2. **OAuth** — you click "Connect" and log in with the provider in your browser (e.g. GitLab Duo, GitHub Copilot, Kimi Code). OmniRoute stores the tokens and refreshes them.
3. **Web session / cookie** — OmniRoute logs into a website's free chat using a cookie (e.g. HuggingChat, Gemini Web, Qwen Web). This is what the Cookie Pusher extension feeds.

**CLI commands:**

```
omniroute providers available            # all 290+ in the catalog
omniroute providers list                 # your configured connections
omniroute providers test <id>            # is one connection actually working?
omniroute providers test-all             # test every connection at once
omniroute providers validate             # check config without calling out
omniroute providers rotate <id>          # swap in a new upstream API key
omniroute providers status               # key health: age, expiry, cooldown
omniroute providers metrics              # latency / success rate / cost per connection
omniroute keys add <provider> <key>      # quick way to add an API key
omniroute keys list                      # all keys (masked)
omniroute keys remove <provider>         # remove one
```

> **`omniroute oauth`** — lists providers that support OAuth (`oauth providers`), starts the browser login (`oauth start`), shows active connections (`oauth status`), and disconnects them (`oauth revoke`). This is how GitLab Duo, Copilot, and similar get connected.

> **Web-session providers** (chatgpt-web, qwen-web, lmarena, claude-web, zai-web...) appear in the provider list and usually need a fresh cookie from your browser. If a connection shows "unknown" status or returns `User not found` / `401`, its session expired — refresh it (with the Cookie Pusher extension) or re-add it.

---

## 5. Models — what you can call

`omniroute models` (or `curl localhost:20128/v1/models`) lists every model you can use. Model IDs have a **`provider/model-name`** shape:

- `auto` and `auto/...` — the smart router's own virtual models (see Combos).
- `nvidia/nvidia/nemotron-ultra-253b-v1`, `opencode-zen/deepseek-v4-pro`, `aug/opus4.7`, `lmarena/qwen-image-2.0`, `gitlab-duo/claude-sonnet-4-6` — real models, pinned to one provider.

```
omniroute models --search nemotron     # find models by name
omniroute models nvidia                # only that provider's models
```

A pinned model uses exactly that provider. If that provider is down or rate-limited, the request fails — pinned means pinned. `auto` is the opposite: it routes around problems.

---

## 6. Combos — the flagship feature

A **combo** is a **chain of models** you define, and OmniRoute automatically slides down the chain: first choice fails or runs out of quota → second choice → third...

**The zero-config version:** just use `auto`. OmniRoute builds a virtual combo from all your connected providers and scores them live on 12 factors (health, quota, cost, latency, success rate, freshness...).

| Model ID | What it optimizes for |
|---|---|
| `auto` | Balanced default (sticks to the last provider that worked) |
| `auto/coding` | Best for writing code |
| `auto/fast` | Lowest latency first |
| `auto/cheap` | Cheapest per token |
| `auto/offline` | Most free quota / headroom first |
| `auto/smart` | Quality first, with a little exploration |
| `auto/best-coding`, `auto/best-reasoning`, ... | The "best of" family you saw in `/v1/models` |

**Building your own combo** — you pick models and, per step, one of **19 routing strategies**:

| Strategy | Plain meaning |
|---|---|
| `priority` | Use targets in the order you listed |
| `fill-first` | Exhaust one target's quota before moving on |
| `weighted` | Random pick, but heavier-weighted targets get picked more |
| `round-robin` | Cycle through in order |
| `p2c` | Randomly pick between two candidates, keep the less-loaded |
| `least-used` | Pick the least busy |
| `random` | Random (no repeats) |
| `strict-random` | Truly random |
| `cost-optimized` | Cheapest per request |
| `headroom` | The one with most quota left |
| `reset-window` | The one whose quota resets soonest |
| `reset-aware` | Same idea, ranked |
| `context-relay` | Pass the conversation context between models |
| `context-optimized` | Best fit for your current context size |
| `cache-optimized` | Keep repeat prefixes on the same account for cache hits |
| `lkgp` | "Last Known Good Path" — stick to what worked last time |
| `auto` | The 12-factor live scoring engine |
| `fusion` | Ask a panel of models, a judge model blends one answer |
| `pipeline` | Chain: each model's output feeds the next |

**CLI:**

```
omniroute combo list                    # your combos
omniroute combo switch <name>           # make one active
omniroute combo create <name>           # create one (interactive or flags)
omniroute combo delete <name>
omniroute combo suggest                 # AI suggests the best combo for your task
```

> Tip: `auto/<category>:<tier>` gives fine control, e.g. `auto/coding:free` = best free coding model, `auto/coding:pro` = allow paid. This was in your model list.

---

## 7. Resilience — what happens when things break

OmniRoute protects itself (and you) with **3 independent layers**, so one failure never stops your work:

1. **Circuit breaker (whole provider)** — if a provider starts failing (server errors), it "trips" and stops being used for a while, then tries a small probe to see if it recovered. While tripped, the combo uses the next provider. *You do nothing; it self-heals.*
2. **Connection cooldown (one key/account)** — a single key that gets rate-limited (HTTP 429) is "cooled down" with backoff; other keys for the same provider keep serving. Success clears the history.
3. **Model lockout (one model)** — if a *specific model* is rate-limited or missing, only that model is paused — the connection stays usable.

Terminal states (account **banned**, **expired**, or **credits exhausted**) are *not* auto-retried — those need you to fix the account.

**CLI:**

```
omniroute resilience status           # everything at a glance
omniroute resilience breakers         # which providers are tripped
omniroute resilience cooldowns        # which keys are cooling down
omniroute resilience lockouts         # which models are paused
omniroute resilience reset            # manually clear breaker/cooldown state
omniroute resilience profile          # per-profile behavior
omniroute resilience config           # tuning knobs
```

---

## 8. Compression — make every token count

Free tiers are token-limited, and tool-heavy AI sessions burn tokens fast. OmniRoute can **shrink prompts before sending them** and restore the answer after — transparently, no changes to your tools. It stacks **12 engines**, each doing one type of shrinking:

| # | Engine | What it does |
|---|---|---|
| 1 | Session-Dedup | Removes content you already sent this conversation |
| 2 | CCR | Archives big blocks, fetches them back only if needed |
| 3 | Lite | Trims whitespace and image URLs (safe baseline) |
| 4 | RTK | Smartly trims tool results (shell/build/test output) |
| 5 | Responses Tool Output | Lossless-first compression of tool output JSON |
| 6 | Headroom | Compacts JSON arrays (~30% smaller) |
| 7 | Relevance | Keeps sentences relevant to your latest question |
| 8 | Caveman | Rewrites prose telegraph-style (65–75% smaller) |
| 9 | Aggressive | Summarizes + ages out old turns |
| 10 | LLMLingua-2 | ML-based pruning (code-safe) |
| 11 | Ultra | Heuristic token pruning |
| 12 | OmniGlyph | Experimental: encodes context as an image (opt-in) |

**Always protected:** code blocks, URLs, and JSON are never broken by compression.

**Presets** (one command, pick your appetite):

| Preset | ~Savings | Best for |
|---|---|---|
| Lite | 15% | Always-on safe default |
| Standard (Caveman) | 30% | Daily coding |
| Aggressive | 50% | Long tool-heavy sessions |
| Ultra | 75% | Maximum savings |
| RTK | 60–90% | Shell/test/build output |
| Stacked (RTK→Caveman) | 78–95% | Mixed prompts + tool logs |

**CLI:**

```
omniroute compression status             # what's on
omniroute compression configure          # set the mode/preset
omniroute compression engine             # pick/change the active engine
omniroute compression combos             # per-combo compression stats
omniroute compression rules              # add custom rules
omniroute compression language-packs     # human-language packs
omniroute compression preview            # see what compression would do to a request
```

Per-request override: send header `x-omniroute-compression: off` (or a profile name) to disable/change it for one request.

---

## 9. The API — what your tools actually call

Everything is served from `http://localhost:20128`. The main ones:

| Endpoint | Purpose |
|---|---|
| `POST /v1/chat/completions` | OpenAI-style chat (most tools use this) |
| `POST /v1/messages` | Anthropic/Claude-style chat (Claude Code uses this) |
| `POST /v1/responses` | OpenAI Responses API |
| `GET /v1/models` | List models |
| `POST /v1/embeddings` | Vector embeddings |
| `POST /v1/images/generations` | AI images (flux, qwen-image, ...) |
| `POST /v1/audio/speech`, `/v1/audio/translations` | Text-to-speech, transcription |
| `POST /v1/ocr` | Text extraction from images |
| `POST /v1/rerank` | Rerank documents |
| `POST /v1/moderations` | Content moderation |
| `POST /v1/files`, `/v1/batches` | File uploads, batch jobs |
| `/api/mcp/stream`, `/api/mcp/sse` | MCP protocol endpoints |
| `/api/webhooks` | Webhook management |

**Auth:** send `Authorization: Bearer <your-omniroute-key>`. The special localhost key `omniroute` works when the server is on this machine. Keys are created via Dashboard → Keys or `omniroute keys add`.

> **No-header tools?** Some clients can't send custom headers. OmniRoute gives you tokenized URL aliases like `http://localhost:20128/vscode/YOUR_KEY/chat/completions` — the key lives in the URL instead.

**Quick test from a terminal:**

```bash
curl http://localhost:20128/v1/chat/completions \
  -H "Authorization: Bearer omniroute" -H "Content-Type: application/json" \
  -d '{"model":"auto","messages":[{"role":"user","content":"Hello!"}]}'
```

---

## 10. The CLI — every command, explained

`omniroute` alone starts the server. Here's the **whole command family** in plain words. (Raw full help output for every command is saved in `docs/ref/`.)

### 10.1 Daily drivers

| Command | What it does |
|---|---|
| `omniroute` | Start the server (gateway + dashboard) |
| `omniroute status` | One-screen status of the whole system |
| `omniroute dashboard` / `omniroute open` | Open the web dashboard in your browser |
| `omniroute doctor` | Diagnose providers, ports, native deps — the "is everything OK?" tool |
| `omniroute setup` | Guided first-run wizard (interactive) |
| `omniroute stop` / `restart` | Stop / restart the server |
| `omniroute health` / `health components` / `health watch` | Health checks; `watch` = live refresh every few seconds |
| `omniroute logs` | Stream or export request logs |
| `omniroute update` | Update OmniRoute itself |

### 10.2 Talking to models

| Command | What it does |
|---|---|
| `omniroute chat "question"` | One-shot chat (flags: `-m` model, `--combo`, `--stream`, `--responses-api`, `--system`, `--file`, `--stdin`, `--temperature`, `--reasoning-effort`, `--thinking-budget`) |
| `omniroute stream "question"` | Stream a chat with SSE inspection modes |
| `omniroute repl` | Interactive multi-turn chat in the terminal |
| `omniroute simulate "question"` | **Dry run** — shows which provider WOULD be picked, without actually calling anyone. Great for debugging routing. |
| `omniroute test <provider> <model>` | Test a live connection/model |

### 10.3 Providers, keys, models (see sections 4–5)

`providers` (available/list/test/test-all/validate/rotate/status/metrics) · `provider` (older interface) · `keys` (add/list/remove/regenerate/revoke/reveal/usage/rotate + `policy`, `expiration` sub-commands) · `models [provider] [--search]` · `oauth` (providers/start/status/revoke) · `nodes` (manage **provider nodes** = endpoint URLs: list/get/add/update/remove/validate/test/metrics) · `oneproxy` (upstream proxy pool: status/stats/fetch/rotate/config/pool).

### 10.4 Routing & combos (see section 6)

`combo` (list/switch/create/delete/suggest) · `sessions` (list/show/expire/expire-all/current) · `tags` (organize resources: list/add/remove/assign/unassign/resources) · `policy` (authorization policies: list/get/create/update/delete/evaluate/export/import).

### 10.5 Resilience & performance (see sections 7–8)

`resilience` (status/breakers/cooldowns/lockouts/reset/profile/config) · `compression` (status/configure/engine/combos/rules/language-packs/preview) · `context-eng` (Caveman/RTK/combos/analytics — the context-engineering pipeline) · `cache` (status|stats/clear) · `redis` (launch a local Redis container for caching + quota tracking).

### 10.6 Money & usage

| Command | What it does |
|---|---|
| `omniroute cost` | Cost report; `--group-by provider|model|api-key|combo|day`, `--period`, `--since/--until` |
| `omniroute usage analytics` | Aggregated usage analytics |
| `omniroute usage budget` | Manage cost budgets |
| `omniroute usage quota` | Provider quota usage |
| `omniroute usage logs` / `history` / `proxy-logs` | Request call logs / history / proxy logs |
| `omniroute usage utilization` | Per-API-key utilization |
| `omniroute quota` | Show provider quota usage |
| `omniroute pricing` | Model pricing: `sync` (from upstream), `list`, `get <model>`, `defaults`, `diff` |
| `omniroute telemetry` | Aggregated telemetry: `summary`, `export` |

### 10.7 Memory, skills, evals

| Command | What it does |
|---|---|
| `omniroute memory` | The "remember things across conversations" feature: `search` (semantic), `add`, `list`, `get`, `delete`, `clear`, `health` |
| `omniroute skills` | Skills = packaged capabilities: `list`, `get`, `install` (file/URL), `enable`, `disable`, `delete`, `execute`, `executions`, `skillssh`, `marketplace` |
| `omniroute eval` | Evaluate model/combo quality: `suites`, `run <suiteId>`, `list`, `get`, `results`, `cancel`, `scorecard` |

> Memory is **off by default** — you opt in. When on, OmniRoute can remember facts between requests (FTS5 + vector search) unless you send `x-omniroute-no-memory: 1` for a private request.

### 10.8 Automation & integrations

| Command | What it does |
|---|---|
| `omniroute webhooks` | Push events to your URL: `events`, `list`, `get`, `add`, `update`, `remove`, `test` |
| `omniroute files` | Upload/manage files: `list`, `upload`, `get`, `content`, `delete` |
| `omniroute batches` | OpenAI-style batch jobs: `create`, `submit` (JSONL), `list`, `get`, `cancel`, `wait`, `output`, `errors` |
| `omniroute translator` | Convert requests between API formats: `detect`, `translate`, `send`, `stream`, `history` |
| `omniroute openapi` | Work with the OpenAPI spec: `dump`, `validate`, `try <path>`, `endpoints`, `paths` |
| `omniroute api` | Direct REST access generated from the spec: `tags`, `chat`, `messages`, `responses`, `embeddings`, `images`, `audio`, `moderations`, `rerank`, `system`, `models`, `providers`, `playground`, `memory` |
| `omniroute mcp` | MCP server (stdio): `omniroute --mcp` |
| `omniroute a2a` | Agent-to-Agent server |
| `omniroute plugin` | Extend the CLI: `list`, `install`, `remove`, `info`, `search`, `update`, `scaffold` |

### 10.9 Remote, sync, tunnels

| Command | What it does |
|---|---|
| `omniroute connect <host>` | Point this CLI at a *remote* OmniRoute (e.g. a VPS) — then every command runs there |
| `omniroute contexts` | Save/switch server profiles: `add`, `use`, `current`, `show`, `list`, `remove`, `rename`, `export`, `import` |
| `omniroute tokens` | Scoped access tokens for remote mode: `create` (scope read/write/admin), `list`, `revoke`, `scopes` |
| `omniroute sync` | Sync config between instances: `push`, `pull`, `diff`, `bundle <file>` (export), `import`, `initialize`, `tokens`, `status`, `resolve` |
| `omniroute tunnel` | Expose the server: `create` (tailscale/cloudflare/ngrok...), `list`, `stop`, `status`, `logs`, `info`, `rotate` |

> **Plain version:** `connect` + `contexts` + `tokens` = "run the CLI here, control a server elsewhere." `sync bundle/import` = copy your whole config to another machine as a file. `tunnel` = let other devices reach your server.

### 10.10 One-click tool setup

These write the config for a specific AI coding tool, pointing it at OmniRoute:

```
omniroute setup-claude      # ~/.claude profiles for each model
omniroute setup-codex       # ~/.codex profiles
omniroute setup-opencode    # opencode.json provider
omniroute setup-cline / setup-kilo / setup-roo / setup-continue / setup-cursor
omniroute setup-goose / setup-aider / setup-qwen / setup-crush
omniroute launch            # start Claude Code pointed at OmniRoute
omniroute launch-codex      # same for Codex
omniroute configure <cli>   # pick a model, write the local config
```

### 10.11 Cloud agents

`omniroute cloud` — run tasks on **hosted agents** (Codex, Devin, Jules cloud versions): `cloud agents`, `cloud codex`, `cloud devin`, `cloud jules`. (These call a hosted service — not the same as local routing.)

### 10.12 Ops & environment

| Command | What it does |
|---|---|
| `omniroute env` | See env vars: `show|list`, `get <key>`, `set <key> <value>` |
| `omniroute runtime` | Native dependencies: `check`, `repair`, `clean` |
| `omniroute tray` | System tray: `show`, `hide`, `quit` (needs `--tray`) |
| `omniroute autostart` | Start at login/boot: `enable|on`, `disable|off`, `toggle`, `status` |
| `omniroute completion` | Shell tab-completion scripts |
| `omniroute backup` | `create` a backup, `auto` schedule |
| `omniroute restore [backupId]` | Restore from a backup |
| `omniroute audit` | Compliance/audit log: `tail`, `search`, `export`, `stats`, `get` |
| `omniroute login` | Local OAuth helpers for remote installs |

### 10.13 Global flags on every command

```
-v, --version        version number
--output <fmt>       table | json | jsonl | csv   (script-friendly!)
-q, --quiet          less noise
--no-color           plain output
--timeout <ms>       HTTP timeout for the command
--api-key <key>      which OmniRoute key to use (env: OMNIROUTE_API_KEY)
--base-url <url>     which server (env: OMNIROUTE_BASE_URL)
--context <name>     which server profile (env: OMNIROUTE_CONTEXT)
--lang <code>        CLI display language
```

> **Superpowers tip:** `omniroute providers list --output json` and friends make every command scriptable — you can pipe them into PowerShell/Python for automation.

---

## 11. Security features

| Feature | Plain meaning |
|---|---|
| **API keys** (`keys`) | Keys with scopes; `keys policy` (rules), `keys expiration` (auto-expire), `keys rotate/revoke` |
| **Policies** (`policy`) | Rules like "user X may only use models Y and Z" — evaluated per request |
| **Guardrails** | Prompt-injection guard on every route; optional credential-masking (redacts leaked keys) |
| **Encryption** | Your provider keys encrypted at rest (AES-256-GCM) with `STORAGE_ENCRYPTION_KEY` |
| **Local-first** | Loopback-only processes; upstream headers scrubbed; nothing phones home |
| **Audit log** (`audit`) | Every sensitive action recorded in your local SQLite |
| **OIDC login** | Optional single-sign-on gate for the dashboard (password still works) |

---

## 12. The most useful day-to-day sequence

```bash
omniroute status                        # feeling: is everything up?
omniroute health                        # detailed health
omniroute providers test-all            # which connections actually work
omniroute simulate "hello"              # which provider WOULD answer (no cost)
omniroute chat "hello" -m auto          # actually ask something
omniroute cost --group-by provider      # where did the week's tokens go?
omniroute usage quota                   # what's left on each free tier
omniroute cache status && cache clear   # cache check / reset
omniroute backup create                 # safety snapshot before changes
```

---

## 13. Quick troubleshooting

| Symptom | What to check |
|---|---|
| "Connection refused" | Server not running → `omniroute` (or your launcher) |
| Model call fails | `omniroute providers test <id>` — the connection may be dead |
| `401 User not found` on a web provider | Cookie/session expired → refresh with the Cookie Pusher, or re-connect |
| `429` rate limited | Normal — resilience will cool the key down; use `auto` to route around it |
| Always the same provider, even when slow | That's `lkgp`/`auto` being sticky — switch to `auto/fast` or a combo |
| Token usage climbing | Turn on compression: `omniroute compression configure` |
| Everything works in browser but not a tool | Check the tool's Base URL (`http://localhost:20128/v1`) and the API key |
| `localhost` fails but `127.0.0.1` works (Windows) | The server binds IPv4 only — use `127.0.0.1` in clients |
| Port already in use | Another instance is running — `omniroute status` / task manager, or change `PORT` |

---

## 14. Where everything lives on disk

| Path | What |
|---|---|
| `~/.omniroute/` | Data dir: `.env` (server env), `storage.sqlite` (config, keys encrypted), logs, backups |
| `~/.omniroute/cli-history.jsonl` | Your `chat`/`repl` command history |
| `%APPDATA%\npm\node_modules\omniroute\` | The installed program (Windows) |
| `~/.claude/settings.json` | Claude Code wiring (base URL/token/model) |

**Backup = copy the data dir** (`omniroute backup create` does it properly, including scheduled `backup auto`).

---

*Raw reference: full `--help` output for every command is in `docs/ref/` (generated from the same installed version). The guide covers v3.8.49; newer versions add providers and features but the shape stays the same.*
