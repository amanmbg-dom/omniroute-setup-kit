@echo off
rem ============================================================
rem  re-sign-in.cmd - one-click Google re-login for the flowui
rem  bridge. Use this when the bridge reports "needs sign-in"
rem  (Google sessions expire eventually, even in headless mode).
rem
rem  What it does:
rem    1. Stops the headless bridge (the node process on :20134)
rem    2. Stops the flow Chrome instance (identified by our
rem       profile dir / CDP port 9222 - NEVER your other Chrome)
rem    3. Opens a VISIBLE Chrome window with the same profile,
rem       on the Google Flow page - sign in there
rem    4. After you press a key, closes it and restarts the
rem       bridge headless. Your session is saved in the profile.
rem ============================================================
setlocal
set "ROOT=%~dp0"
set "PIDFILE=%USERPROFILE%\.flow-browser-chrome.pid"
set "PROFILE=%USERPROFILE%\.flow-browser-profile"
set "CHROME=%ProgramFiles%\Google\Chrome\Application\chrome.exe"
if not exist "%CHROME%" set "CHROME=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
if not exist "%CHROME%" set "CHROME=chrome"

echo == Stopping the headless flowui bridge...
for /f "tokens=5" %%p in ('netstat -ano ^| findstr ":20134" ^| findstr "LISTENING"') do taskkill /F /PID %%p >nul 2>&1

echo == Stopping the flow Chrome instance (profile-only, not your other Chrome)...
if exist "%PIDFILE%" (
  set /p CPID=<"%PIDFILE%"
  if defined CPID taskkill /F /PID %CPID% >nul 2>&1
)
for /f "tokens=5" %%p in ('netstat -ano ^| findstr ":9222" ^| findstr "LISTENING"') do taskkill /F /PID %%p >nul 2>&1
timeout /t 2 /nobreak >nul

echo == Opening Chrome so you can sign in to Google (visible window)...
start "" "%CHROME%" --user-data-dir="%PROFILE%" --no-first-run --no-default-browser-check --window-size=1400,900 "https://labs.google/fx/tools/flow"
echo.
echo Sign in to Google in the window that just opened (Flow Automation profile).
echo Complete the login and any consent prompts, then come back and press a key...
pause >nul

echo == Closing the sign-in window and restarting the bridge headless...
for /f "tokens=5" %%p in ('netstat -ano ^| findstr ":9222" ^| findstr "LISTENING"') do taskkill /F /PID %%p >nul 2>&1
timeout /t 1 /nobreak >nul

start "" /B cmd /c ""%ROOT%start-flow-browser.cmd""
timeout /t 6 /nobreak >nul
echo.
echo Done. The bridge is restarting headless - your Google session is saved in the profile.
echo Check it with:  curl -s http://127.0.0.1:20134/health
endlocal
