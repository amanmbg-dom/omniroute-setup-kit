@echo off
rem ============================================================
rem  flowui bridge launcher - Google Flow via real Chrome session
rem
rem  HEADLESS by default (no window). Your signed-in Flow profile
rem  (~/.flow-browser-profile) is shared with the visible mode, so
rem  the login persists. If a session expires, run:
rem      re-sign-in.cmd      (opens Chrome so you can sign in again)
rem
rem  The bridge auto-starts at login via the Startup folder entry
rem  created by setup.ps1 (FlowUI-Bridge.cmd). This launcher is
rem  location-independent: when copied into the Startup folder,
rem  %~dp0 is the Startup folder itself, so we fall back to the
rem  real bridge directory under the kit.
rem ============================================================
setlocal
set "PATH=%APPDATA%\npm;%PATH%"

rem --- 0. locate the real bridge dir (works from the Startup copy too) ---
set "ROOT=%~dp0"
if exist "%ROOT%flow-bridge.mjs" goto root_ok
set "ROOT=%USERPROFILE%\omniroute-setup-kit\bridge\flow-browser\"
if not exist "%ROOT%flow-bridge.mjs" (
  echo FlowUI bridge not found - re-run setup.ps1 first.
  exit /b 1
)
:root_ok
cd /d "%ROOT%"

rem --- 1. headless by default (FLOW_HEADLESS=0 brings the window back) ---
if not defined FLOW_HEADLESS set "FLOW_HEADLESS=1"

rem --- 2. make sure dependencies are installed (one-time) ---
if not exist "node_modules\playwright" (
  echo Installing dependencies - one-time download...
  call npm install --omit=dev
  if errorlevel 1 (
    echo npm install failed - is Node.js installed?
    exit /b 1
  )
)

rem --- 3. wait for the OmniRoute gateway (the bridge registers into it) ---
set "GW_OK="
for /l %%i in (1,1,40) do (
  %SystemRoot%\System32\curl.exe -s -m 2 -o nul http://127.0.0.1:20128/v1/models >nul 2>&1
  if not errorlevel 1 ( set "GW_OK=1" & goto gw_up )
  %SystemRoot%\System32\timeout.exe /t 2 /nobreak >nul
)
:gw_up
if not defined GW_OK (
  echo Warning: OmniRoute gateway not reachable yet - bridge will start anyway.
)

rem --- 4. register the flowui provider in OmniRoute (idempotent) ---
node register-flowui.mjs

rem --- 5. start the bridge ---
echo Starting flowui bridge on http://127.0.0.1:20134 (headless=%FLOW_HEADLESS%)...
node flow-bridge.mjs
endlocal
