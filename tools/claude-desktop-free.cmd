@echo off
REM claude-desktop-free.cmd — Launch Claude Desktop with free OmniRoute models
REM
REM Usage: Double-click this file, or run from command prompt.
REM Starts: proxy (port 20228) + Claude Desktop with env vars

setlocal

set ANTHROPIC_BASE_URL=http://127.0.0.1:20228
set ANTHROPIC_AUTH_TOKEN=omniroute
set CLAUDE_CODE_USE_GATEWAY=true

echo Starting Claude Desktop with free OmniRoute models...
echo.

REM Check if proxy is already running
netstat -ano | findstr "20228" | findstr "LISTENING" >nul 2>&1
if %errorlevel% neq 0 (
    echo Starting proxy on port 20228...
    start /B "" node "%~dp0claude-desktop-proxy.mjs"
    timeout /t 5 /nobreak >nul
) else (
    echo Proxy already running on port 20228.
)

REM Launch Claude Desktop
for /f "delims=" %%i in ('dir /b /ad /o-n "%LOCALAPPDATA%\AnthropicClaude\app-*"') do (
    set "CLAUDE_EXE=%LOCALAPPDATA%\AnthropicClaude\%%i\claude.exe"
    goto found
)
:found

if exist "%CLAUDE_EXE%" (
    echo Launching Claude Desktop...
    start "" "%CLAUDE_EXE%"
    echo Done! Claude Desktop is running with free models.
    echo.
    echo Gateway: http://localhost:20228
    echo API Key: omniroute
) else (
    echo Claude Desktop not found. Install from claude.com/download
    pause
)

endlocal
