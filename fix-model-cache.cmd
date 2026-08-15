@echo off
rem Picker self-heal (runs at logon, 120s delay).
rem Re-applies the Claude Code native-binary patch (auto-updates revert it),
rem re-ensures the gateway model discovery env vars, re-registers the mimo-web
rem bridge node, and re-seeds the model cache - so the /model picker always
rem shows the full gateway catalog. If the binary is locked by a running
rem Claude Code session, it retries on the next logon (or run
rem fix-model-cache.ps1 manually after closing Claude Code).
setlocal
ping -n 121 127.0.0.1 >nul
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0fix-model-cache.ps1" >> "%USERPROFILE%\.omniroute\fix-model-cache.log" 2>&1
endlocal
