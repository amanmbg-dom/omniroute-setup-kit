# OmniRoute Tools — Unified Bridge Layer

## What is this?

A unified layer that wraps all OmniRoute bridges and provides a single entry point for Claude Code and other tools. No more scanning the entire codebase — one MCP server gives you access to everything.

## Components

### 1. Omniroute Tools MCP Server (`omniroute-tools.mjs`)

A Model Context Protocol (MCP) server that provides these tools:

| Tool | Description |
|---|---|
| `omniroute_chat` | Chat with any provider (auto/best-coding, combo/qwen, etc.) |
| `omniroute_image` | Generate images (Gemini Flow, Nano Banana, Imagen 4) |
| `omniroute_search` | Web search via DeepSeek/Qwen |
| `omniroute_health` | Check all provider health |
| `omniroute_bridge_status` | Check all bridge status |
| `omniroute_model_list` | List all available models |

**Install in Claude Code:**
```json
// ~/.claude/settings.json → mcpServers
{
  "omniroute-tools": {
    "command": "node",
    "args": ["C:/Users/Work/omniroute-setup-kit/tools/omniroute-tools.mjs"]
  }
}
```

### 2. Bridge Plugin System (`bridge-plugin-system.mjs`)

Add new bridges by editing `~/.omniroute/bridges.json` — no code changes needed.

```bash
# List all bridges
node tools/bridge-plugin-system.mjs list

# Check status
node tools/bridge-plugin-system.mjs status

# Add a new bridge
node tools/bridge-plugin-system.mjs add '{"name":"my-bridge","port":20137,...}'

# Register with gateway
node tools/bridge-plugin-system.mjs register my-bridge
```

### 3. Meta Web Bridge (`bridge/meta-web-bridge/`)

New bridge for Meta AI (Llama models) via meta.ai web chat.

**Setup:**
1. Sign in at meta.ai in your browser
2. Cookie Pusher → Grab & push sessions
3. Bridge starts automatically with the gateway

## Adding a New Bridge

1. **Create the bridge** (copy mimo-web-bridge as template)
2. **Add to bridges.json:**
   ```json
   {
     "name": "my-bridge",
     "type": "node",
     "port": 20137,
     "dir": "bridge/my-bridge",
     "script": "bridge.mjs",
     "healthPath": "/healthz",
     "cookiesNeeded": true,
     "cookieFile": "my-cookies.json",
     "registerWithGateway": true,
     "gatewayConnection": {
       "name": "My Bridge (auto)",
       "type": "openai-compatible",
       "baseUrl": "http://127.0.0.1:20137",
       "authType": "none"
     }
   }
   ```
3. **Register:** `node tools/bridge-plugin-system.mjs register my-bridge`
4. **Restart gateway:** `fix-model-cache.ps1`

## Port Allocation

| Port | Bridge |
|---|---|
| 20133 | Gemini Bridge (images) |
| 20134 | FlowUI (images) |
| 20135 | MiMo Web Bridge |
| 20136 | Meta Web Bridge (NEW) |
| 20137 | DeepSeek Web Bridge |
| 20140 | Omniroute Tools MCP |

## Architecture

```
Claude Code / Other Tools
         │
         ▼
┌─────────────────────────┐
│  Omniroute Tools MCP    │  ← Single entry point
│  (omniroute-tools.mjs)  │
└────────────┬────────────┘
             │
    ┌────────┼────────┐
    ▼        ▼        ▼
┌───────┐ ┌───────┐ ┌───────┐
│ Gemini│ │ MiMo  │ │ Meta  │  ← Bridges
│ Bridge│ │ Web   │ │ Web   │
└───┬───┘ └───┬───┘ └───┬───┘
    │         │         │
    ▼         ▼         ▼
┌─────────────────────────┐
│   OmniRoute Gateway     │  ← /v1/chat/completions
│   (localhost:20128)     │
└─────────────────────────┘
```

## Benefits

1. **No codebase scanning** — Claude Code gets tools via MCP, not by reading files
2. **Unified interface** — One tool for chat, images, search, health
3. **Easy extension** — Add bridges via JSON config, no code changes
4. **Failure isolation** — One bridge down doesn't affect others
5. **Future-proof** — New bridges auto-register with the gateway
