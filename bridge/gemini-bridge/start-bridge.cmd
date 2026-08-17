@echo off
rem gemini-bridge launcher - "token method" for Google Flow / free Nano Banana images.
rem Needs: (1) the venv built (setup.ps1 step 8 does it), (2) a pushed google.com
rem session in OmniRoute (Cookie Pusher -> Grab & push sessions with gemini.google.com signed in).
rem
rem Location-independent: when copied into the Startup folder (Gemini-Bridge.cmd),
rem %~dp0 is the Startup folder itself (no bridge.py there), so we fall back to the
rem installed kit copy at %USERPROFILE%\omniroute-setup-kit (setup.ps1 builds the
rem venv there).
setlocal
set "BRIDGE_DIR=%~dp0"
if not exist "%BRIDGE_DIR%bridge.py" set "BRIDGE_DIR=%USERPROFILE%\omniroute-setup-kit\bridge\gemini-bridge\"
if not exist "%BRIDGE_DIR%bridge.py" (
  echo gemini-bridge bridge.py not found - re-run setup.ps1 first.
  exit /b 1
)
set "PATH=%APPDATA%\npm;%PATH%"
cd /d "%BRIDGE_DIR%"
if not exist ".venv\Scripts\python.exe" (
  echo venv missing - run setup.ps1 first, step 8 builds it.
  exit /b 1
)
".venv\Scripts\python.exe" bridge.py
endlocal
