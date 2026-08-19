@echo off
rem Start Meta Web Bridge (hidden) — port 20136
rem The bridge translates Meta AI's web chat into OpenAI-compatible format.
rem Sign in at meta.ai, then Cookie Pusher → Grab & push sessions.

set META_BRIDGE_PORT=20136
set META_BRIDGE_HOST=127.0.0.1

rem Resolve the bridge path relative to this script's location
set BRIDGE_DIR=%~dp0

rem Start hidden (no console window)
start "" /B node "%BRIDGE_DIR%bridge.mjs"
