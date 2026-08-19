# DeepSeek Web Bridge (with auto-continue)

OpenAI-compatible local bridge for **chat.deepseek.com** web chat, token-authenticated.
Serves `deepseek-web/*` routes to the OmniRoute gateway and fixes the one thing the
gateway's built-in executor cannot: **long chats that get truncated with the
"Continue generating" button**.

## The problem it solves

When a DeepSeek web response is long, the server ends the stream with status
`INCOMPLETE` (or `AUTO_CONTINUE`) instead of `FINISHED`. In the web UI that is the
"Continue generating" button. The gateway's built-in deepseek-web executor stops at
that point — the answer is silently cut off mid-sentence.

This bridge implements the web client's continue protocol: it captures the
`response_message_id` from the stream, and when the stream ends with
`INCOMPLETE`/`AUTO_CONTINUE` it calls `POST /api/v0/chat/continue` with
`{chat_session_id, message_id, fallback_to_resume: true}` and splices the
continuation stream onto the previous one — automatically, up to 8 rounds. The
client sees one seamless stream with the full answer.

## Files

| file | purpose |
| --- | --- |
| `bridge.mjs` | the bridge (node:http, zero npm deps) |
| `register-deepseek-web.mjs` | registers the `deepseek-web` provider node in the gateway DB (idempotent) |
| `deepseek-pow-solver.cjs` | pure-JS DeepSeekHashV1 PoW solver (copied from the omniroute package) |
| `start-bridge.cmd` | Windows launcher (Startup-folder friendly) |

## Run

```bash
node bridge.mjs        # listens on 127.0.0.1:20136
node register-deepseek-web.mjs   # once (or after `omniroute reset`)
```

On Android the kit's `start-omniroute.sh` starts and registers it automatically.
On Windows, `setup.ps1` installs it and `fix-model-cache.ps1` starts it.

## Auth (Cookie Pusher)

Sign in at chat.deepseek.com, then in the OmniRoute Cookie Pusher extension press
**Grab & push sessions**. The extension reads the `userToken` from DeepSeek's
localStorage and pushes it to the bridge's `POST /v1/cookies`, which writes
`~/.omniroute/deepseek-cookies.json`. Alternatively send it yourself:

```bash
curl -X POST http://127.0.0.1:20136/v1/cookies -H 'Content-Type: application/json' \
  -d '{"userToken":"<paste from DevTools -> Application -> Local Storage -> chat.deepseek.com -> userToken>"}'
```

## Endpoints

- `GET /v1/models` — the deepseek-web model list
- `POST /v1/chat/completions` — OpenAI-format chat (SSE streaming, auto-continue)
- `POST /v1/cookies` — store the userToken
- `GET /healthz`

## Notes

- Fresh upstream session per request (deleted afterwards) — same as the gateway's
  default behavior.
- The PoW challenge is solved per request in pure JS (~seconds at high difficulty)
  — no wasm, no native deps, works on Android/Termux.
- Auto-continue is bounded at 8 rounds (matches ds2api's default) so a runaway
  loop can't spin forever.
