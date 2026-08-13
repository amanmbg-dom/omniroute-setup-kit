#!/usr/bin/env bash
# signin.sh — interactive one-time sign-in for the VPS provider profile.
# Requires the VPS to have been installed with --with-gui (xvfb + x11vnc).
# Connect with any VNC client to <vps-ip>:5900 (or tunnel the port), sign in
# to each provider once, then kill this script. Sessions persist in the
# profile and are kept warm by refresh-sessions.sh / the keep-alive cron.
#
# Prefer the no-GUI path if you can: export cookies on your laptop (Cookie
# Pusher) and run: bash ~/.omniroute/import-cookies.sh cookies.json
set -euo pipefail

OMNI_HOME="${OMNI_HOME:-$HOME/.omniroute}"
PROFILE_DIR="$OMNI_HOME/browser-profile"
CHROME_BIN="$(command -v chromium || command -v chromium-browser || command -v google-chrome || true)"
VNC_PORT="${VNC_PORT:-5900}"

if [ -z "$CHROME_BIN" ]; then
  echo "Chromium not installed." >&2
  exit 1
fi
for bin in Xvfb x11vnc; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "missing: $bin (install with: sudo apt install xvfb x11vnc)" >&2
    exit 1
  fi
done

mkdir -p "$PROFILE_DIR"
echo "starting virtual display :99 ..."
Xvfb :99 -screen 0 1600x1000x24 >/dev/null 2>&1 &
XVFB_PID=$!
sleep 2

echo "starting Chromium on the provider profile ..."
DISPLAY=:99 "$CHROME_BIN" --no-sandbox --no-first-run --user-data-dir="$PROFILE_DIR" \
  https://chatgpt.com/ >/dev/null 2>&1 &
CHROME_PID=$!

echo "starting x11vnc on :$VNC_PORT ..."
x11vnc -display :99 -forever -nopw -rfbport "$VNC_PORT" >/dev/null 2>&1 &
VNC_PID=$!

echo ""
echo "=============================================================="
echo "  Connect a VNC client to <VPS-IP>:$VNC_PORT"
echo "  Sign in to each provider once, then press Ctrl+C here."
echo "  To tunnel it:  ssh -L 5900:localhost:5900 user@<vps-ip>"
echo "=============================================================="
echo ""
trap 'kill $CHROME_PID $XVFB_PID $VNC_PID 2>/dev/null || true' EXIT
wait
