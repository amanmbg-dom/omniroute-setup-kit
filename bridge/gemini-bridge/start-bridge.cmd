@echo off
rem gemini-bridge launcher - "token method" for Google Flow / free Nano Banana images.
rem Needs: (1) the venv built (setup.ps1 step 8 does it), (2) a pushed google.com
rem session in OmniRoute (Cookie Pusher -> Grab & push sessions with gemini.google.com signed in).
setlocal
set "BRIDGE_DIR=%~dp0"
set "PATH=%APPDATA%\npm;%PATH%"
cd /d "%BRIDGE_DIR%"
if not exist ".venv\Scripts\python.exe" (
  echo venv missing - run setup.ps1 or:  python -m venv .venv ^&^& .venv\Scripts\pip install -r requirements.txt
  exit /b 1
)
".venv\Scripts\python.exe" bridge.py
endlocal
