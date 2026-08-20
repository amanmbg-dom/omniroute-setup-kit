# Using Freebuff with the OmniRoute free-model gateway

Freebuff Desktop is a coding agent that talks to a model provider the same way
Claude Code / Codex do. The OmniRoute gateway is a drop-in Anthropic- and
OpenAI-compatible endpoint, so you can point Freebuff at the free-model pool
instead of a paid API key.

## The quick way: `freebuff-gateway.cmd`

```bat
freebuff-gateway.cmd                                   :: gateway on this PC
freebuff-gateway.cmd http://192.168.1.50:20128         :: phone as the gateway
freebuff-gateway.cmd http://192.168.1.50:20128 "C:\path\Freebuff.exe"
```

The launcher reads the gateway API key from the Cookie Pusher extension config
(`%USERPROFILE%\omniroute-cookie-pusher\config.js`), sets
`ANTHROPIC_BASE_URL` / `ANTHROPIC_AUTH_TOKEN` / `OPENAI_BASE_URL` /
`OPENAI_API_KEY`, and starts Freebuff. In Freebuff's model picker, choose any
curated route:

- `auto/coding:reliable` — the gateway's best auto-routed coding model (default)
- `combo/qwen`, `combo/glm`, `combo/deepseek` — web-cookie provider families
- `mimo-web/mimo-v2.5-pro` — Xiaomi MiMo web session
- `lmarena/claude-sonnet-5` — arena pool claude-class model

The catalog the gateway serves is the **curated free list** (see
`fix-model-cache.ps1` / `android/fix-model-cache.sh`): every visible route is
free and answers `/v1/chat/completions`.

## If Freebuff has a custom-provider UI

Point it at:

| Field      | Value                                  |
|------------|----------------------------------------|
| Base URL   | `http://localhost:20128` (or the phone's IP + `:20128`) |
| API key    | the value of `DEFAULT_API_KEY` in `%USERPROFILE%\omniroute-cookie-pusher\config.js` |
| Models     | `auto/coding:reliable`, `combo/qwen`, … (gateway auto-lists them at `/v1/models`) |

## What does NOT work

- **Freebuff Cloud** (the browser/server-side agent) runs inside the provider's
  cloud and cannot reach a local/phone gateway — only the desktop app can use it.
- If the gateway is on the phone, the PC and phone must be on the same Wi-Fi,
  and the phone's battery whitelist (Settings → Apps → Termux → Battery →
  Unrestricted) must be set so the stack stays alive.

## Why this works

The gateway speaks both the Anthropic (`/v1/messages`) and OpenAI
(`/v1/chat/completions`) wire formats with a bearer token. Any agent that
respects `ANTHROPIC_BASE_URL` / `OPENAI_BASE_URL` env vars — or lets you type a
custom base URL — can consume the free pool. The env-var launcher covers the
first case; the custom-provider table covers the second.
