@echo off
rem Gemini Chat Bridge launcher — free Gemini chat via your gemini.google.com session.
rem Needs: (1) python venv from gemini-bridge (shared), (2) pushed cookies.
rem Port 20138 by default.

setlocal
set GEMINI_CHAT_PORT=20138

rem Use the gemini-bridge's Python venv (has gemini_webapi + curl_cffi)
set PYTHON=%~dp0..\gemini-bridge\.venv\Scripts\python.exe

if not exist "%PYTHON%" (
  echo ERROR: Python venv not found at %~dp0..\gemini-bridge\.venv
  echo Create it first: cd ..\gemini-bridge && python -m venv .venv ^&^& .venv\Scripts\pip install -r requirements.txt
  exit /b 1
)

echo Starting Gemini Chat Bridge on port %GEMINI_CHAT_PORT%...
"%PYTHON%" "%~dp0bridge.py"
