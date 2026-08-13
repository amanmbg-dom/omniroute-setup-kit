@echo off
rem ============================================================
rem  OmniRoute Kit - one-click setup for a new Windows device.
rem  Works on a BRAND-NEW PC: installs prerequisites (Git, Node,
rem  Python, Chrome, gh) automatically via bootstrap.ps1, then
rem  configures everything (gateway, providers, image bridges,
rem  Claude Code wiring, Claude Desktop, MCPs, skills, auto-start).
rem
rem  For a truly empty PC: Download ZIP from the GitHub repo page
rem  (it is private - log in), extract, double-click this file.
rem ============================================================
setlocal
cd /d "%~dp0"

echo Checking/installing prerequisites (Git, Node.js, Python, Chrome, gh)...
echo This downloads installers via winget if they are missing. ~1-3 minutes.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0bootstrap.ps1" -PrereqsOnly
if errorlevel 1 (
  echo.
  echo Prerequisite setup failed - see the messages above.
  echo Tip: close and reopen this window, or open a NEW PowerShell window
  echo and run:  powershell -NoProfile -ExecutionPolicy Bypass -File bootstrap.ps1
  pause
  exit /b 1
)

echo.
echo Running setup.ps1 - this configures everything (gateway, providers,
echo flowui image bridge, Claude Code wiring, Claude Desktop, MCPs, skills,
echo auto-start). ~2-5 minutes.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" -Pull -UpdateSkills

echo.
echo Setup finished. Manual one-time steps:
echo   1. Load the Cookie Pusher extension: edge://extensions -^> Developer mode
echo      -^> Load unpacked -^> %USERPROFILE%\omniroute-cookie-pusher
echo      -^> click the extension -^> Grab ^& push sessions
echo   2. For AI images: run  bridge\flow-browser\re-sign-in.cmd  once and
echo      sign in to Google (Flow Automation profile).
echo   3. Claude Desktop: sign in with any Claude account, open the Code tab,
echo      start a Local session - it already routes through your gateway.
echo      (See setup-desktop.cmd if the app is not installed yet.)
pause
endlocal
