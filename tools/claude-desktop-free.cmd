@echo off
setlocal

set PROXY_PORT=10150
set PROXY_URL=http://127.0.0.1:%PROXY_PORT%

rem === Start proxy if not running ===
curl -s %PROXY_URL%/healthz >nul 2>&1
if errorlevel 1 (
  echo Starting proxy on port %PROXY_PORT%...
  start "" /b node "%~dp0claude-desktop-proxy.mjs"
  timeout /t 3 >nul
)

rem === Verify both services ===
curl -s %PROXY_URL%/healthz >nul 2>&1
if errorlevel 1 (
  echo ERROR: Proxy failed to start
  exit /b 1
)
curl -s http://127.0.0.1:20128/healthz >nul 2>&1
if errorlevel 1 (
  echo ERROR: OmniRoute not running - start it first
  exit /b 1
)

echo.
echo   Proxy:     %PROXY_URL%
echo   OmniRoute: http://127.0.0.1:20128
echo   Models:    Free (DeepSeek, MiMo, Gemini, Mistral...)
echo.

rem === Set env vars for Claude Desktop ===
set ANTHROPIC_BASE_URL=%PROXY_URL%
set ANTHROPIC_AUTH_TOKEN=omniroute

rem === Launch Claude Desktop ===
start "" "%LOCALAPPDATA%\AnthropicClaude\claude.exe"

endlocal
