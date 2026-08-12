@echo off
rem ============================================================
rem  OmniRoute Kit - one-click setup for a new Windows device.
rem  Double-click this file (or run: install.cmd) after getting
rem  the kit onto the machine (git clone or copy).
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

echo Running setup.ps1 - this configures everything (gateway, providers,
echo flowui image bridge, Claude Code wiring, auto-start). ~2-5 minutes.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"

echo.
echo Setup finished. Two manual one-time steps:
echo   1. Load the Cookie Pusher extension: edge://extensions -^> Developer mode
echo      -^> Load unpacked -^> %USERPROFILE%\omniroute-cookie-pusher
echo      -^> click the extension -^> Grab ^& push sessions
echo   2. For AI images: run  bridge\flow-browser\re-sign-in.cmd  once and
echo      sign in to Google (Flow Automation profile).
pause
endlocal
