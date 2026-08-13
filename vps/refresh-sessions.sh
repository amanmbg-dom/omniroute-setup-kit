#!/usr/bin/env bash
# refresh-sessions.sh — keeps provider sessions alive server-side.
# Opens each provider in the headless profile so cookies refresh instead of
# expiring while your laptop is off. Runs from the keep-alive cron too.
set -euo pipefail

OMNI_HOME="${OMNI_HOME:-$HOME/.omniroute}"
PROFILE_DIR="$OMNI_HOME/browser-profile"
CHROME_BIN="$(command -v chromium || command -v chromium-browser || command -v google-chrome || true)"

# Add any provider you signed in to. Homepages are enough to re-arm most
# session rotators; add specific app URLs if a provider needs more.
PROVIDER_URLS=(
  "https://chatgpt.com/"
  "https://chat.deepseek.com/"
  "https://gemini.google.com/"
  "https://claude.ai/"
  "https://www.google.com/"
)

if [ -z "$CHROME_BIN" ]; then
  echo "Chromium not installed - skipping session refresh" >&2
  exit 0
fi

mkdir -p "$PROFILE_DIR"
for url in "${PROVIDER_URLS[@]}"; do
  echo "refreshing $url"
  "$CHROME_BIN" --headless=new --no-sandbox --no-first-run --disable-gpu \
    --user-data-dir="$PROFILE_DIR" --virtual-time-budget=8000 \
    "$url" >/dev/null 2>&1 || true
  sleep 3
done
echo "session refresh complete"
