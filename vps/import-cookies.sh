#!/usr/bin/env bash
# import-cookies.sh <cookie-json-file> [more files...]
# Imports cookie JSON exports (the exact format the Cookie Pusher extension
# grabs from Chrome) into the VPS headless Chromium profile, so sessions live
# server-side without needing your browser. Uses Chrome DevTools Protocol.
#
# Where to get the JSON: on your laptop, use the Cookie Pusher extension's
# "export" (or your browser's cookie export) and scp the files here, e.g.
#   scp cookies-chatgpt.json user@vps:~/
#   bash ~/.omniroute/import-cookies.sh ~/cookies-chatgpt.json
set -euo pipefail

OMNI_HOME="${OMNI_HOME:-$HOME/.omniroute}"
PROFILE_DIR="$OMNI_HOME/browser-profile"
PORT="${CDP_PORT:-9333}"
CHROME_BIN="$(command -v chromium || command -v chromium-browser || command -v google-chrome || true)"

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <cookie-json-file> [more...]" >&2
  exit 1
fi
if [ -z "$CHROME_BIN" ]; then
  echo "Chromium not installed - install it first (sudo apt install chromium)" >&2
  exit 1
fi
for f in "$@"; do
  [ -f "$f" ] || { echo "not found: $f" >&2; exit 1; }
done

mkdir -p "$PROFILE_DIR"
# boot headless Chromium on the profile with a CDP port
"$CHROME_BIN" --headless=new --no-sandbox --no-first-run --disable-gpu \
  --remote-debugging-port="$PORT" --user-data-dir="$PROFILE_DIR" \
  about:blank >/dev/null 2>&1 &
CHROME_PID=$!
trap 'kill $CHROME_PID 2>/dev/null || true' EXIT

echo "waiting for Chromium CDP on :$PORT ..."
for i in $(seq 1 20); do
  curl -sf "http://127.0.0.1:$PORT/json/version" >/dev/null 2>&1 && break
  sleep 1
done

node "$OMNI_HOME/import-cookies.mjs" "http://127.0.0.1:$PORT" "$@"

echo "cookies imported into $PROFILE_DIR (profile stays signed in server-side)"
