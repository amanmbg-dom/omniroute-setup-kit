@echo off
rem ===========================================================================
rem  freebuff-gateway.cmd - launch Freebuff Desktop routed through the local
rem  OmniRoute gateway (the free-model pool) instead of a paid API key.
rem
rem  Usage:
rem    freebuff-gateway.cmd                       (gateway on localhost:20128)
rem    freebuff-gateway.cmd http://192.168.x.x:20128   (gateway on another
rem                                                    device, e.g. the phone)
rem    freebuff-gateway.cmd http://192.168.x.x:20128 "C:\path\to\Freebuff.exe"
rem
rem  What it does:
rem    * reads the admin API key from the Cookie Pusher extension config
rem      (%USERPROFILE%\omniroute-cookie-pusher\config.js) - the same key the
rem      gateway dashboard uses
rem    * sets the standard env vars any Anthropic/OpenAI-compatible client
rem      honors: ANTHROPIC_BASE_URL / ANTHROPIC_AUTH_TOKEN /
rem      ANTHROPIC_API_KEY / OPENAI_BASE_URL / OPENAI_API_KEY
rem    * starts Freebuff Desktop with those env vars, so its model calls land
rem      on the gateway (auto/coding:reliable, combo/qwen, mimo-web/*, ...)
rem
rem  In Freebuff's model picker, use routes like: auto/coding:reliable,
rem  combo/qwen, combo/deepseek, mimo-web/mimo-v2.5-pro (same ids as Claude
rem  Code / Codex - the gateway catalog is now the curated free list).
rem ===========================================================================
setlocal EnableExtensions

set "GW=%~1"
if "%GW%"=="" set "GW=http://localhost:20128"

set "APP=%~2"
if "%APP%"=="" (
  for %%p in (
    "%LOCALAPPDATA%\Programs\Freebuff\Freebuff.exe"
    "%LOCALAPPDATA%\Programs\@codebufffreebuff-desktop\Freebuff.exe"
    "%ProgramFiles%\Freebuff\Freebuff.exe"
  ) do if exist "%%p" set "APP=%%p"
)
if "%APP%"=="" (
  echo Freebuff.exe not found in the usual places.
  echo Pass the path as the 2nd argument, e.g.:
  echo   %~nx0 http://localhost:20128 "C:\path\to\Freebuff.exe"
  exit /b 1
)

rem ---- read the admin key from the Cookie Pusher config ----
set "KEY="
if exist "%USERPROFILE%\omniroute-cookie-pusher\config.js" (
  for /f "usebackq tokens=2 delims='" %%k in (
    `findstr /C:"DEFAULT_API_KEY" "%USERPROFILE%\omniroute-cookie-pusher\config.js"`
  ) do set "KEY=%%k"
)
if "%KEY%"=="" set "KEY=omniroute"

echo Gateway: %GW%
echo Key:     %KEY%
echo App:     %APP%
echo.
echo Setting provider env vars and launching Freebuff...

set "ANTHROPIC_BASE_URL=%GW%"
set "ANTHROPIC_AUTH_TOKEN=%KEY%"
set "ANTHROPIC_API_KEY=%KEY%"
set "OPENAI_BASE_URL=%GW%/v1"
set "OPENAI_API_KEY=%KEY%"
set "CLAUDE_CODE_USE_GATEWAY=true"

start "" "%APP%"
echo Launched. In Freebuff's model picker choose e.g. auto/coding:reliable or combo/qwen.
