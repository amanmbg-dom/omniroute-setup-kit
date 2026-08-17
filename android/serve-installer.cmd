@echo off
rem ===========================================================================
rem  serve-installer.cmd - serve the android\ folder so the phone can fetch
rem  the one-file installer. Run this on the PC, then in Termux on the phone:
rem
rem     curl -O http://<PC-IP>:8080/install-omniroute.sh
rem     bash install-omniroute.sh
rem
rem  Stop it with Ctrl+C when done (or leave it running - harmless).
rem ===========================================================================
cd /d "%~dp0"
for /f "tokens=2 delims=:" %%i in ('ipconfig ^| findstr /i "IPv4"') do set "IP=%%i"
set "IP=%IP: =%"
echo.
echo PC LAN IP: %IP%
echo On the phone (Termux) run:
echo   curl -O http://%IP%:8080/install-omniroute.sh ^&^& bash install-omniroute.sh
echo.
echo Serving android\ on http://0.0.0.0:8080 ...  (Ctrl+C to stop)
python -m http.server 8080 --bind 0.0.0.0
