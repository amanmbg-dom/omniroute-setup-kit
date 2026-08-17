@echo off
rem OmniRoute gateway launcher - pins PORT because the package .env sets 58342
set PORT=20128
rem The gateway catalogs 2600+ routes and resolves 250-model combos; with the
rem default ~2-4GB Node heap it can stall (listening but not answering) under
rem memory pressure. Give it a comfortable heap on a 16GB machine.
set NODE_OPTIONS=--max-old-space-size=6144
set PATH=%APPDATA%\npm;%PATH%
rem --no-open: the gateway auto-opens the dashboard in a browser on EVERY
rem start/restart (incl. watchdog kills -> supervisor respawns), which pops
rem tabs all day. The dashboard is one click away at http://localhost:20128.
start "" /B node "%APPDATA%\npm\node_modules\omniroute\bin\omniroute.mjs" serve --no-open
