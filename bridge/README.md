# OmniRoute Bridges

Bridges translate free AI web services into OpenAI-compatible endpoints that OmniRoute can consume. Each bridge runs locally on `127.0.0.1` and handles authentication via session cookies.

## Quick Start

```powershell
# Start all bridges
.\manage-bridges.ps1 start

# Check status
.\manage-bridges.ps1 status

# Stop all bridges
.\manage-bridges.ps1 stop

# Start a specific bridge
.\manage-bridges.ps1 start meta

# Restart specific bridges
.\manage-bridges.ps1 restart deepseek mimo
```

## Bridge Overview

| Bridge | Port | Type | Models | Auth Method |
|--------|------|------|--------|-------------|
| **Meta Web** | 20136 | Chat | Llama 4 Maverick/Scout, Llama 3.3 70B | Meta AI session cookies |
| **DeepSeek Web** | 20137 | Chat | DeepSeek V4 Pro/Flash, R1, V3.2 | User token + PoW |
| **MiMo Web** | 20135 | Chat | MiMo V2.5 | Session cookie |
| **Gemini Image** | 20133 | Image | Nano Banana | Google session cookies |
| **Gemini Chat** | 20138 | Chat | Gemini 2.5 Flash/Pro | Google session cookies |
| **Flow Browser** | 20134 | Image | Nano Banana 2/Pro, Imagen 4 | Chrome profile login |

## Setup Requirements

### All Node.js Bridges
- Node.js >= 20
- No npm install required (pure Node.js)

### Gemini Image Bridge (Python)
```powershell
cd bridge\gemini-bridge
python -m venv .venv
.venv\Scripts\pip install -r requirements.txt
```

### Flow Browser Bridge
- Google Chrome installed
- Playwright: `npm install playwright`
- First run opens Chrome window for Google sign-in

## Authentication (Cookie Pusher)

All bridges use the same authentication flow:

1. **Sign in** to the service in your browser
2. **Open Cookie Pusher** extension
3. **Grab & Push Sessions** — this stores cookies in `~/.omniroute/`
4. **Start the bridge** — it reads cookies from the shared location

### Cookie Files
```
~/.omniroute/
├── meta-cookies.json      # Meta AI (c_user, xs, datr)
├── deepseek-cookies.json  # DeepSeek (userToken)
├── mimo-cookies.json      # MiMo (session cookie)
├── gemini-cookies.json    # Google (__Secure-1PSID, __Secure-1PSIDTS)
```

## API Endpoints

Each bridge exposes a standard OpenAI-compatible API:

### Chat Bridges (Meta, DeepSeek, MiMo, Gemini Chat)
```bash
# List models
curl http://127.0.0.1:PORT/v1/models

# Chat completion
curl -X POST http://127.0.0.1:PORT/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "model-id",
    "messages": [{"role": "user", "content": "Hello"}],
    "stream": true
  }'

# Health check
curl http://127.0.0.1:PORT/healthz

# Update cookies
curl -X POST http://127.0.0.1:PORT/v1/cookies \
  -H "Content-Type: application/json" \
  -d '{"cookies": {"key": "value"}}'
```

### Image Bridges (Gemini Image, Flow Browser)
```bash
# Generate image
curl -X POST http://127.0.0.1:PORT/v1/images/generations \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "A sunset over mountains",
    "n": 1
  }'
```

## Model Selection

### DeepSeek Web
- `deepseek-v4-pro` — Pro model
- `deepseek-v4-pro-think` — Pro with thinking
- `deepseek-v4-pro-search` — Pro with web search
- `deepseek-v4-flash` — Fast model
- `deepseek-chat` — Standard chat
- `deepseek-reasoner` — Reasoning model

### MiMo Web
- `mimo-v2.5` — Latest MiMo model (thinking enabled by default)

### Meta Web
- `meta/llama-4-maverick` — Llama 4 Maverick
- `meta/llama-4-scout` — Llama 4 Scout
- `meta/llama-3.3-70b` — Llama 3.3 70B

### Gemini Chat
- `gemini-2.5-flash` — Fast, capable
- `gemini-2.5-pro` — Most capable
- `gemini-2.0-flash` — Balanced
- `gemini-1.5-pro` — Previous gen pro
- `gemini-1.5-flash` — Previous gen fast

## Integration with OmniRoute

Bridges register automatically with the local OmniRoute gateway. To connect manually:

```powershell
# Register a bridge
node bridge\meta-web-bridge\register-meta-web.mjs
node bridge\deepseek-web-bridge\register-deepseek-web.mjs
node bridge\mimo-web-bridge\register-mimo-web.mjs
node bridge\gemini-chat-bridge\register-gemini-chat.mjs
```

## Troubleshooting

### Bridge won't start
- Check if port is already in use: `netstat -an | findstr PORT`
- Verify Node.js is installed: `node --version`
- Check logs: `~/.omniroute/bridge-name.log`

### Authentication errors
- Ensure you're signed in to the service
- Re-run Cookie Pusher to refresh tokens
- Check cookie file exists in `~/.omniroute/`

### Meta bridge returns errors
- The GraphQL doc_id may need updating
- Check logs for the actual doc_id being used
- Meta AI updates their web app frequently

### DeepSeek PoW fails
- Verify `deepseek-pow-solver.cjs` exists in the bridge directory
- Check if DeepSeek changed their PoW algorithm

## Development

### Adding a new bridge
1. Create directory: `bridge/your-bridge/`
2. Implement `bridge.mjs` with OpenAI-compatible endpoints
3. Add to `manage-bridges.ps1` bridge definitions
4. Create `start-bridge.cmd` and `register-*.mjs`
5. Update this README

### Testing
```bash
# Test health endpoint
curl http://127.0.0.1:PORT/healthz

# Test with simple chat
curl -X POST http://127.0.0.1:PORT/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"default","messages":[{"role":"user","content":"Hi"}]}'
```
