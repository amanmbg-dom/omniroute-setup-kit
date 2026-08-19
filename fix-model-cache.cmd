@echo off
rem Picker self-heal (runs at logon, 120s delay).
rem Re-applies the Claude Code native-binary patch (auto-updates revert it),
rem re-ensures the gateway model discovery env vars, re-registers the mimo-web
rem bridge node, re-seeds the model cache, and re-applies the zai captcha
rem headless patch - so the /model picker always shows the full gateway catalog
rem and the browsers stay invisible. If the binary is locked by a running
rem Claude Code session, it retries on the next logon (or run
rem fix-model-cache.ps1 manually after closing Claude Code).
setlocal
ping -n 121 127.0.0.1 >nul

rem Rotate the log when it outgrows 1MB (keep the previous run in .old).
set "FIX_LOG=%USERPROFILE%\.omniroute\fix-model-cache.log"
if exist "%FIX_LOG%" (
  for %%A in ("%FIX_LOG%") do if %%~zA GTR 1048576 (
    del "%FIX_LOG%.old" 2>nul
    ren "%FIX_LOG%" fix-model-cache.log.old
  )
)

rem The ps1 may live next to this cmd (kit root / Startup copy) OR in the stable
rem deployed dir ~\.omniroute (setup.ps1 copies it there). Resolve both ways.
set "FIX_PS1=%~dp0fix-model-cache.ps1"
if not exist "%FIX_PS1%" set "FIX_PS1=%USERPROFILE%\.omniroute\fix-model-cache.ps1"
if not exist "%FIX_PS1%" (
  echo fix-model-cache.ps1 not found - re-run setup.ps1 first. >> "%USERPROFILE%\.omniroute\fix-model-cache.log"
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%FIX_PS1%" >> "%USERPROFILE%\.omniroute\fix-model-cache.log" 2>&1
endlocal
