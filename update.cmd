@echo off
rem ============================================================
rem  OmniRoute Kit - update an existing machine in one action.
rem  Pulls the latest kit from git, refreshes the kit's skills
rem  (backing up any customized copies to <name>.bak-kit), and
rem  re-runs the full idempotent setup: extension + fresh token,
rem  slash commands, MCP servers, skills.sh, bridges, gateway
rem  wiring and auto-start.
rem
rem  Run from anywhere:  .\update.cmd   (or just double-click)
rem ============================================================
setlocal
cd /d "%~dp0"

where git >nul 2>&1
if errorlevel 1 (
  echo Git not found. Install it first:  winget install Git.Git
  pause
  exit /b 1
)

where node >nul 2>&1
if errorlevel 1 (
  echo Node.js not found. Install it first:  winget install OpenJS.NodeJS.LTS
  pause
  exit /b 1
)

echo Pulling the latest kit and refreshing everything (skills, extension,
echo commands, MCPs, gateway wiring). Idempotent - safe to re-run any time.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" -Pull -UpdateSkills

echo.
echo Update finished. If the Cookie Pusher extension changed, reload it in
echo edge://extensions (Developer mode -^> reload) so the browser picks it up.
pause
endlocal
