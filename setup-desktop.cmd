@echo off
rem ============================================================
rem  setup-desktop.cmd - install the OFFICIAL Claude Desktop app
rem  and point it at your free OmniRoute gateway. No extension.
rem
rem  What this does:
rem   1. checks your gateway is up (localhost:20128)
rem   2. downloads the official Claude Desktop installer (claude.ai)
rem   3. launches it for you to click through
rem   4. prints the 30-second guide
rem ============================================================
setlocal
cd /d "%~dp0"

echo.
echo [1/4] Checking the gateway...
curl -s -m 8 http://127.0.0.1:20128/v1/models >nul 2>&1
if errorlevel 1 (
  echo   Gateway is NOT responding. Start it first:
  echo     powershell -NoProfile -ExecutionPolicy Bypass -File setup.ps1
  pause
  exit /b 1
)
echo   Gateway is up on localhost:20128. Good.

echo.
echo [2/4] Checking for an existing Claude Desktop install...
set "DESKTOP_EXE="
if exist "%LOCALAPPDATA%\AnthropicClaude\claude.exe"  set "DESKTOP_EXE=%LOCALAPPDATA%\AnthropicClaude\claude.exe"
if exist "%LOCALAPPDATA%\Programs\claude\claude.exe"   set "DESKTOP_EXE=%LOCALAPPDATA%\Programs\claude\claude.exe"
if exist "%LOCALAPPDATA%\Programs\Claude\claude.exe"   set "DESKTOP_EXE=%LOCALAPPDATA%\Programs\Claude\claude.exe"
if defined DESKTOP_EXE (
  echo   Already installed: %DESKTOP_EXE%
  goto :guide
)

echo.
echo [3/4] Downloading the official Claude Desktop installer...
set "DL=%TEMP%\claude-desktop-setup.exe"
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://claude.ai/api/desktop/win32/x64/exe/latest/redirect' -OutFile '%DL%' -UseBasicParsing -TimeoutSec 180"
if errorlevel 1 (
  echo   Download failed. Grab the installer manually at:  https://claude.com/download
  pause
  exit /b 1
)
echo   Downloaded to %DL%
echo   Launching the installer - click through it (defaults are fine).
start "" "%DL%"

:guide
echo.
echo [4/4] After installing + signing in, do this ONCE (30 seconds):
echo.
echo   The Claude Desktop app has three tabs: Chat, Cowork, Code.
echo   The CODE tab is Claude Code in a GUI - and it reads the SAME
echo   ~/.claude/settings.json as your terminal, so it ALREADY points
echo   at your free gateway (http://localhost:20128). No extension.
echo.
echo   1. Open the app -^> sign in with any Claude account
echo   2. Click the CODE tab
echo   3. Choose Environment: Local, pick a project folder
echo   4. Type a message and press Enter - it routes through your gateway
echo      (model auto/coding:reliable - all 38 auto/ routes are in /model)
echo.
echo   NOTE: the app's model dropdown only shows Claude-family names, but
echo   ANTHROPIC_MODEL pins your combo regardless - that is expected.
echo   Switch models anytime with Ctrl+Shift+I (model menu) or /model.
echo.
echo   DEEP OPTION - route the app ITSELF through the gateway (Chat tab too):
echo     Settings -^> Developer -^> Inference provider = Gateway
echo     Gateway base URL: http://localhost:20128
echo     Auth scheme: bearer      API key: omniroute
echo     (Developer settings only appear in some builds - if missing, the
echo      Code tab route above is what you want.)
echo.
echo   VS Code extension users: you can now UNINSTALL the Claude Code
echo   extension - Desktop covers chat, coding and browser preview.
pause
endlocal
