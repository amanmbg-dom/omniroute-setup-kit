@echo off
rem mimo-web-bridge launcher - free MiMo V2.5 chat via your aistudio.xiaomimimo.com session.
rem Needs: (1) node >= 20, (2) a pushed session - sign in at aistudio.xiaomimimo.com,
rem        then Cookie Pusher -> Grab & push sessions (the pusher stores it for the bridge).
setlocal
set "BRIDGE_DIR=%~dp0"
set "PATH=%APPDATA%\npm;%PATH%"
cd /d "%BRIDGE_DIR%"
node bridge.mjs
endlocal
