@echo off
rem meta-web-bridge launcher - free Meta AI (Llama) chat via your meta.ai session.
rem Needs: (1) node >= 20, (2) a pushed session - sign in at meta.ai,
rem        then Cookie Pusher -> Grab & push sessions (the pusher stores it for the bridge).
rem
rem Location-independent: when copied into the Startup folder, %~dp0 is the
rem Startup folder itself (no bridge.mjs there), so we fall back to the stable
rem deployed copy at %USERPROFILE%\.omniroute\bridge\meta-web-bridge (setup.ps1
rem keeps that in sync).
setlocal
set "BRIDGE_DIR=%~dp0"
if not exist "%BRIDGE_DIR%bridge.mjs" set "BRIDGE_DIR=%USERPROFILE%\.omniroute\bridge\meta-web-bridge\"
if not exist "%BRIDGE_DIR%bridge.mjs" (
  echo meta-web bridge.mjs not found - re-run setup.ps1 first.
  exit /b 1
)
set "PATH=%APPDATA%\npm;%PATH%"
cd /d "%BRIDGE_DIR%"
node bridge.mjs
endlocal
