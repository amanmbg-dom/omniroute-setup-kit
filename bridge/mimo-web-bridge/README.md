# mimo-web-bridge

Free **MiMo V2.5 / V2.5-Pro** chat through your **aistudio.xiaomimimo.com** session
— the "web version" of Xiaomi's open-weights models, routed as `mimo-web/<model>`
through OmniRoute.

The OmniRoute gateway registers `xiaomimimo-web` as a cookie-credential stub, but
the shipped build has **no executor** for it, so there is no `xiaomimimo-web/*`
route. Instead of patching the compiled gateway (which would break on every
update), this bridge implements the MiMo web API and plugs in through the
gateway's **supported** `openai-compatible` provider-node mechanism — the same
pattern as `gflow` / `flowui`.

## How it works

```
Claude Code / picker
   └─ gateway  POST /v1/chat/completions  model=mimo-web/mimo-v2.5
        └─ provider node (openai-compatible, prefix mimo-web)
             └─ http://127.0.0.1:20135/v1/chat/completions   (this bridge)
                  └─ POST https://aistudio.xiaomimimo.com/open-apis/bot/chat
                     (session cookie + xiaomichatbot_ph)
```

The MiMo web chat protocol was reverse-engineered from the deployed webpack
bundle (`main.*.chunk.js` + `6670.*.chunk.js`):

- **Endpoint** `POST /open-apis/bot/chat` — production build uses no `/fastchat`
  prefix (that is `ultra`-environment only).
- **Auth** — plain cookies: `session` (+ optional `xiaomichatbot_ph`, which is
  also echoed as a URL query parameter of the same name). No bearer token.
- **Request** — `{ msgId, conversationId, query, isEditedQuery,
  previousDialogueId?, sceneType?, params?, modelConfig: { model,
  enableThinking, webSearchStatus, temperature?, topP? }, multiMedias }`.
  A fresh `conversationId` (`chat-<uuid>`) starts a new chat; the server issues
  the real `dialogId` over SSE.
- **Response** — named SSE events: `message` (`{content: <delta>}`), `finish`,
  `usage`, `dialogId`, `error`, `web_search`, `doc`, `tip_ratio`.
  Thinking deltas are wrapped in `<think>\0 ... </think>\0` markers (stripped and
  re-emitted as `reasoning_content` here).

## Install

`setup.ps1` step 8d copies this folder, registers the node, and prints the start
command. `fix-model-cache.ps1` also auto-starts the bridge when it is down and
seeds `mimo-web/*` (+ `combo/mimo-web`) into the picker.

```cmd
bridge\mimo-web-bridge\start-bridge.cmd
```

## First run

1. Sign in at **aistudio.xiaomimimo.com** (any account; MiMo V2.5 open weights
   are free, no Claw subscription needed).
2. Cookie Pusher → **Grab & push sessions** — the pusher detects
   `aistudio.xiaomimimo.com` and POSTs the cookies to the bridge
   (`POST /v1/cookies`), which writes `~/.omniroute/mimo-cookies.json`.
3. Use the models:

```
mimo-web/mimo-v2.5        (flagship, thinking on by default)
mimo-web/mimo-v2.5-pro    (largest open model)
mimo-web/mimo-v2-pro
mimo-web/mimo-v2-flash
mimo-web/mimo-v2-omni
combo/mimo-web            (flagship-first routing across all of the above)
```

Session expired? Re-run Grab & push sessions — that is the only refresh path
(the bridge itself never touches the browser).

## Endpoints

| Path | Purpose |
|---|---|
| `GET /v1/models` | live model list from `/open-apis/bot/config` (cached 1 h) |
| `POST /v1/chat/completions` | OpenAI format → MiMo web chat, SSE back |
| `POST /v1/cookies` | Cookie Pusher hook (`{cookies: {name: value}}`) |
| `GET /healthz` | liveness |

## Notes / limits

- **Context** — the web API takes only the latest query plus a server-side
  `previousDialogueId`; a stateless bridge cannot reuse that, so multi-turn
  requests are sent as a flattened `User:/Assistant:` transcript (last 16
  messages, capped at 40k chars).
- **Images** — MiMo web images need the app's upload flow (`/open-apis/resource`
  pre-signed URLs); not implemented. Text chat only.
- **Web search** — always `DISABLED` (matches the default; the app's search
  toggle uses the same field).
- **Zero dependencies** — `node:http` + global `fetch` (node ≥ 20).
