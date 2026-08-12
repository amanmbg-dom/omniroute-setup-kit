# Google Flow bridge — the "token method"

Free **Nano Banana** (the engine behind Google Flow / the Gemini app) image
generation, using your **Google session token** instead of an API key or a
billing-enabled Google Cloud project.

## How it works

Google Flow (labs.google/fx/tools/flow) has no public API — the third-party
wrappers that drive it charge $15/mo. But the **Gemini web app** (`gemini.google.com`,
same Google account, same Nano Banana engine) serves free images to a signed-in
session. This bridge turns that session into an OpenAI-compatible endpoint:

```
Cookie Pusher (Edge)                    OmniRoute gateway               bridge
  grabs __Secure-1PSID + __Secure-1PSIDTS  │  /v1/images/generations      │
  from google.com                          ─►  model: gflow/nano-banana-2 ─► sync-cookies.mjs
       │                                        (custom model)             │  reads session from
       ▼                                        │                          │  OmniRoute DB
  pushed to OmniRoute                           └───────► bridge.py ───────► gemini_webapi
  (gemini-web connection)                       (127.0.0.1:20133)          │  → Gemini web backend
                                                                           ▼
                                                        base64 PNG back through the gateway
```

## Files

| File | Job |
|---|---|
| `sync-cookies.mjs` | Reads the `gemini-web` connection from `~/.omniroute/storage.sqlite`, decrypts it, writes `~/.omniroute/gemini-cookies.json` (self-contained: node:sqlite + node:crypto, no deps) |
| `bridge.py` | Stdlib HTTP server on `127.0.0.1:20133` — `POST /v1/images/generations` (OpenAI format), drives `gemini_webapi`, returns `b64_json` |
| `register-gflow.mjs` | Idempotently registers the `gflow` provider connection + `gflow/nano-banana-2` custom model in OmniRoute so the gateway routes to the bridge |
| `start-bridge.cmd` | Launcher (uses the `.venv`) |
| `requirements.txt` | `gemini_webapi` (the reverse-engineered Gemini web API) |

## First-time setup (already done by setup.ps1 step 8b)

```
python -m venv .venv
.venv\Scripts\pip install -r requirements.txt
node register-gflow.mjs          # registers provider + custom model
.venv\Scripts\python bridge.py   # starts on 127.0.0.1:20133
```

## The ONE manual step (needs your Google login)

1. In Edge, open **gemini.google.com** and confirm you're **signed in** (avatar, not "Sign in").
2. Click the **OmniRoute Cookie Pusher** icon → **Grab & push sessions** (the Gemini Web row needs no extra config).
3. The bridge picks it up automatically on the next request (it re-syncs per request).

## Use it

```bash
curl -X POST http://127.0.0.1:20128/v1/images/generations \
  -H "Authorization: Bearer omniroute" \
  -d '{"model":"gflow/nano-banana-2","prompt":"a logo for a coffee roaster, flat design","n":1}'
```

Or in Claude Code via the `single-page-site` skill ("with AI images").

## Notes & limits

- Binds `127.0.0.1` only — no external access.
- Free-tier Gemini image generation is rate-limited by Google per account
  (roughly a handful of images per day on a fresh free account).
- If the session dies, re-run the Cookie Pusher grab — the bridge re-reads the
  cookies on every request.
- Log: `~/.omniroute/gemini-bridge.log`. Health: `GET http://127.0.0.1:20133/health`.
