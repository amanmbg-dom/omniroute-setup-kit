# Bridge End-to-End Test Results

**Date:** August 20, 2026  
**Tester:** Buffy (Codebuff)

## Summary

| Bridge | Port | Health | Models | Chat/Image | Auth Status |
|--------|------|--------|--------|------------|-------------|
| **MiMo Web** | 20135 | ✅ OK | ✅ Working | ⚠️ No cookies | Needs session |
| **Meta Web** | 20136 | ✅ OK | ✅ Working | ⚠️ No cookies | Needs session |
| **DeepSeek Web** | 20137 | ✅ OK | ✅ Working | ⚠️ No cookies | Needs session |
| **Gemini Chat** | 20138 | ✅ OK | ✅ Working | ❌ API 404 | Endpoints need update |
| **Gemini Image** | 20133 | ✅ OK | N/A | ✅ Ready | Cookies present |
| **Flow Browser** | 20134 | ✅ OK | ✅ Working | ⚠️ Needs Chrome | Browser sign-in |

## Detailed Results

### ✅ Health Endpoints (All Passing)

All 6 bridges respond to health checks:

```bash
# MiMo Web (20135)
{"ok":true}

# Meta Web (20136) 
{"status":"ok","bridge":"meta-web","port":20136}

# DeepSeek Web (20137)
{"ok":true}

# Gemini Chat (20138)
{"ok":true,"status":"ok","bridge":"gemini-chat","port":20138}

# Gemini Image (20133)
{"ok": true, "cookiesPresent": true, "port": 20133}

# Flow Browser (20134)
{"status":"ok","launched":false,"connected":false,"needsLogin":false}
```

### ✅ Model Endpoints (All Working)

All chat bridges return valid model lists:

- **MiMo**: mimo-v2-flash, mimo-v2-pro, mimo-v2-omni
- **Meta**: meta/llama-3.3-70b, meta/llama-3.1-405b, etc.
- **DeepSeek**: deepseek-v4-pro, deepseek-v4-pro-think, etc.
- **Gemini Chat**: gemini-2.5-flash, gemini-2.5-pro, etc.

### ⚠️ Chat Completions (Need Cookies)

All chat bridges return authentication errors when cookies are missing:

```json
{
  "error": {
    "message": "No MiMo session cookie. Sign in at aistudio.xiaomimimo.com, then Cookie Pusher -> Grab & push sessions.",
    "type": "authentication_error"
  }
}
```

**Action Required:** Use Cookie Pusher to grab sessions from each service.

### ⚠️ Gemini Chat Bridge (API Endpoint Issue)

The Gemini Chat bridge returns a 404 error:

```json
{
  "error": {
    "message": "Gemini error (404): <html lang=\"en\" dir=\"ltr\">...",
    "type": "upstream_error"
  }
}
```

**Root Cause:** The Gemini web API endpoint (`/_/BardChatUi/data/...`) may have changed or is not publicly accessible.

**Fix Needed:** Research the current Gemini web API endpoints from the web app.

### ✅ Gemini Image Bridge (Ready)

The Python-based Gemini Image bridge is ready with valid cookies:

- Cookies file: `~/.omniroute/gemini-cookies.json`
- Status: Ready for image generation
- Usage: `POST /v1/images/generations`

### ⚠️ Flow Browser (Needs Chrome)

The Flow Browser bridge is healthy but requires:

1. Google Chrome installed
2. Playwright dependencies
3. One-time Google sign-in in the dedicated Chrome profile

## Authentication Status

### Cookie Files Present
```
~/.omniroute/
├── gemini-cookies.json    ✅ Valid (__Secure1PSID + __Secure1PSIDTS)
├── meta-cookies.json      ⚠️ Empty (needs session)
├── mimo-cookies.json      ⚠️ Missing
└── deepseek-cookies.json  ⚠️ Missing
```

### Required Actions

1. **MiMo Bridge**: Sign in at aistudio.xiaomimimo.com → Cookie Pusher → Grab & push
2. **Meta Bridge**: Sign in at meta.ai → Cookie Pusher → Grab & push
3. **DeepSeek Bridge**: Sign in at chat.deepseek.com → Cookie Pusher → Grab & push
4. **Gemini Chat Bridge**: API endpoints need research/update

## Next Steps

### Immediate
1. Use Cookie Pusher to populate all cookie files
2. Re-test chat completions after cookies are pushed
3. Research current Gemini web API endpoints

### Short-term
1. Fix Gemini Chat bridge API endpoints
2. Add automatic cookie refresh
3. Add retry logic for transient errors

### Long-term
1. Add rate limiting
2. Add request queuing
3. Add metrics/monitoring
4. Add auto-restart on failure

## Usage After Cookies Are Pushed

```powershell
# Start all bridges
.\manage-bridges.ps1 start

# Test a chat completion
curl -X POST http://127.0.0.1:20135/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mimo-v2-flash",
    "messages": [{"role": "user", "content": "Hello!"}],
    "stream": false
  }'

# Check status
.\manage-bridges.ps1 status
```

## Conclusion

**Infrastructure is solid** — all bridges start, respond to health checks, and expose valid model endpoints. The main blocker is **authentication** — each bridge needs valid session cookies from the respective web services.

Once cookies are pushed via Cookie Pusher, all bridges should work immediately for chat completions. The Gemini Chat bridge needs additional API endpoint research.
