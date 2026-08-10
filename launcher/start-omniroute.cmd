@echo off
rem OmniRoute gateway launcher - pins PORT because the package .env sets 58342
set PORT=20128
set PATH=%APPDATA%\npm;%PATH%
start "" /B node "%APPDATA%\npm\node_modules\omniroute\bin\omniroute.mjs" serve
