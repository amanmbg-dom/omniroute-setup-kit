# flowui — Google Flow images through your real Chrome session

The most direct route to free Nano Banana images: drives the **actual Google Flow
web app** (`labs.google/fx/tools/flow`) in a **dedicated Chrome profile** using
your own signed-in Google account. No cookies, no tokens, no captcha
extraction, no API key.

```
OmniRoute / Claude Code  ->  POST /v1/images/generations  {"model":"flowui/nano-banana-2"}
        ->  flow-bridge.mjs (127.0.0.1:20134)
        ->  Chrome ("Flow Automation" profile at ~/.flow-browser-profile, CDP 9222)
        ->  Google Flow UI: prompt -> Generate -> download image
        ->  base64 image(s) back to the caller
```

## Headless by default

The bridge runs **real Chrome invisibly** (`--headless=new`) with your
signed-in profile — no window on your desktop. Verified generating images
end-to-end in headless mode. If a headless request ever fails with a Google
anti-bot block, flip it back to visible:

- `set FLOW_HEADLESS=0` before `start-flow-browser.cmd`, or
- edit `config/flow.config.json` → `"headless": false`

The login lives in `%USERPROFILE%\.flow-browser-profile` either way.

## One-time setup (only once, ~1 minute)

1. Run `start-flow-browser.cmd` (setup.ps1 step 8c installs everything).
2. First run with a fresh profile needs a **visible** sign-in. Run
   `re-sign-in.cmd` — it stops the headless bridge, opens Chrome so you can
   sign in to Google (Flow Automation profile), and restarts headless when
   you press a key. The login then persists forever.
3. The bridge registers itself in OmniRoute as the `flowui` provider:
   - `flowui/nano-banana-2` (default), `flowui/nano-banana-pro`, `flowui/imagen-4`

## Use it three ways — same engine, same quality

| Way | When | How |
|---|---|---|
| **MCP tool** (recommended) | Any Claude Code session | `generate_image` tool from the `flowui` MCP server (`flowui-mcp.mjs`). Registered by setup.ps1: `claude mcp add -s user flowui -- node flowui-mcp.mjs` |
| **Skill** | Single-page sites | the `single-page-site` skill calls `generate_image` with the standardized prompt template |
| **HTTP** | Scripts / curl | see below |

Because every path hits the **same bridge → same Chrome session → same model
(Nano Banana 2) → same ratio mapping**, image quality is identical no matter
who asks. The only variable is the prompt, which the skill's template controls.

## HTTP usage

```bash
# Direct to the bridge
curl -s -X POST http://127.0.0.1:20134/v1/images/generations \
  -H "Content-Type: application/json" \
  -d '{"model":"flowui/nano-banana-2","prompt":"a red sports car, studio lighting","size":"1536x1024","n":4}'

# Or through the OmniRoute gateway
curl -s -X POST http://127.0.0.1:20128/v1/images/generations \
  -H "Authorization: Bearer omniroute" -H "Content-Type: application/json" \
  -d '{"model":"flowui/nano-banana-2","prompt":"a red sports car","size":"1536x1024","n":4}'
```

- `size` maps to Flow ratios: `1792x1024`→16:9, `1536x1024`→4:3,
  `1024x1024`→1:1, `1024x1536`→3:4, `1024x1792`→9:16 (default 1:1).
- `n` returns the newest `n` of Flow's ~4 candidates (default: all).
- Health: `GET http://127.0.0.1:20134/health` (reports `needsLogin`, `busy`).

## Files

| File | Purpose |
|---|---|
| `flow-bridge.mjs` | HTTP bridge (port 20134), launches/talks to Chrome over CDP |
| `flowui-mcp.mjs` | MCP stdio server — exposes `generate_image` + `image_status`, auto-starts the bridge if down |
| `start-flow-browser.cmd` | Launcher — headless default, waits for OmniRoute, registers provider, starts bridge |
| `re-sign-in.cmd` | One-click Google re-login (stops bridge → visible Chrome → restart headless) |
| `register-flowui.mjs` | Idempotent OmniRoute provider registration |
| `src/` | Upstream automation engine (google-flow-browser-mcp), with fixes for Flow 2.0 |

## Autostart

`setup.ps1` step 10 copies `FlowUI-Bridge.cmd` into the Windows Startup folder,
so the bridge (and its OmniRoute registration) comes up at login — headless.
The MCP server's `generate_image` will also auto-start the bridge on demand if
it isn't running.

## Notes / caveats

- **One generation at a time** — the bridge serializes (single-tab automation).
  Concurrent calls get `429`.
- **Model note.** The model actually used is whichever is selected in the Flow
  UI toolbar (Nano Banana 2 by default); the `model` field validates/labels the
  request.
- **Flow credits.** Google Flow gives free daily image credits per account. On
  exhaustion, Google shows a credit dialog in the Flow window — switch Google
  account (in that profile) or wait for the daily reset.
- **Session expiry.** Google sessions expire eventually. The bridge reports
  `needsLogin: true`; run `re-sign-in.cmd` to log back in (headless can't show
  the login page).
- **`config/flow.config.json`** is machine-specific and git-ignored.
  `flow.config.example.json` is the tracked Windows/English/headless template
  that fresh installs copy.
- Reuses the automation engine of
  [google-flow-browser-mcp](https://github.com/TMSSS05/google-flow-browser-mcp)
  (`src/`), patched for Flow 2.0: fresh-session reset, contenteditable
  clearing, agent Q&A safety net, stale-image snapshot, dual URL-format
  detection, project reuse.
