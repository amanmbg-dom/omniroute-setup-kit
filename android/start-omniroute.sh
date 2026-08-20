#!/data/data/com.termux/files/usr/bin/env bash
# =============================================================================
#  start-omniroute.sh - start the full OmniRoute stack on Android (Termux),
#  everyday-phone edition:
#    gateway (20128) + mimo-web bridge (20135) + meta-web bridge (20136) + deepseek-web bridge (20137) + gemini/gflow bridge (20133)
#    + flowui bridge (20134, needs chromium) + wake lock so the phone never
#    sleeps the stack.
#
#  Idempotent: already-running ports are detected and left alone, so this is
#  safe to run any time - at boot (Termux:Boot), from ~/.bashrc when Termux
#  opens, or manually. All processes run detached with logs under
#  ~/.omniroute/logs.
#
#  Usage: bash ~/omniroute-android/start-omniroute.sh
# =============================================================================
set -u
LOG_DIR=~/.omniroute/logs
mkdir -p "$LOG_DIR"

# Keep the CPU awake while the stack runs. Without this, Android Doze kills
# Termux in the background and the routes go dark until you reopen Termux.
# termux-wake-lock comes with the termux-api package; no-op if absent.
command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock

# Battery-saver mode (opt-in: POWER_SAVE=1 bash ~/omniroute-android/start-omniroute.sh):
# hold the wake lock while the screen is ON, release it while it is OFF so
# Android Doze can suspend the stack (the gateway pauses -> near-zero battery
# and data while you are not using the phone), and re-acquire it when the
# screen comes back. The watcher is a tiny detached loop; check
# ~/.omniroute/logs/power-save.log for its activity.
if [ "${POWER_SAVE:-0}" = "1" ] && command -v termux-wake-unlock >/dev/null 2>&1; then
  (
    while true; do
      state=$(dumpsys power 2>/dev/null | grep -m1 'mWakefulness=' | sed 's/.*mWakefulness=//')
      if [ "$state" = "Asleep" ]; then
        termux-wake-unlock >/dev/null 2>&1
      else
        termux-wake-lock >/dev/null 2>&1
      fi
      sleep 300
    done
  ) >>"$LOG_DIR/power-save.log" 2>&1 &
  echo "[power] battery-saver mode ON (wake lock held only while the screen is on)"
fi

# Load ~/.omniroute/.env (PORT/HOST/keys) if present - the gateway reads it too.
if [ -f ~/.omniroute/.env ]; then
  set -a; . ~/.omniroute/.env; set +a
fi
PORT="${PORT:-20128}"

# -- helper: is a port listening? --
port_up() { (echo >/dev/tcp/127.0.0.1/"$1") >/dev/null 2>&1; }

# =============================================================================
# 1. GATEWAY  (20128)
# =============================================================================
if port_up "$PORT"; then
  echo "[gateway] already running on $PORT - skipping"
else
  echo "[gateway] starting omniroute serve (port $PORT, bind 0.0.0.0)..."
  # Pin the port explicitly (the package's own .env sets 58342) and give Node
  # a comfortable heap. Node 24 has node:sqlite built in, so the gateway runs
  # with zero native compilation on Termux (better-sqlite3 optional -> falls
  # back to node:sqlite -> sql.js WASM).
  NODE_OPTIONS="--max-old-space-size=3072" \
  nohup omniroute serve --port "$PORT" --no-open \
    >"$LOG_DIR/gateway.log" 2>&1 &
  echo "[gateway] pid $! - log: $LOG_DIR/gateway.log"
fi

# =============================================================================
# 2. MIMO-WEB BRIDGE  (20135) - pure Node, no browser needed
# =============================================================================
if port_up 20135; then
  echo "[mimo-web] already running on 20135 - skipping"
else
  if [ -f ~/omniroute-android/bridge/mimo-web-bridge/bridge.mjs ]; then
    echo "[mimo-web] starting bridge (20135)..."
    nohup node ~/omniroute-android/bridge/mimo-web-bridge/bridge.mjs \
      >"$LOG_DIR/mimo-web.log" 2>&1 &
    echo "[mimo-web] pid $!"
  else
    echo "[mimo-web] bridge.mjs not found - skipping"
  fi
fi

# =============================================================================
# 2.1 META-WEB BRIDGE  (20136) - pure Node, no browser needed
# =============================================================================
if port_up 20136; then
  echo "[meta-web] already running on 20136 - skipping"
else
  if [ -f ~/omniroute-android/bridge/meta-web-bridge/bridge.mjs ]; then
    echo "[meta-web] starting bridge (20136)..."
    nohup node ~/omniroute-android/bridge/meta-web-bridge/bridge.mjs \
      >"$LOG_DIR/meta-web.log" 2>&1 &
    echo "[meta-web] pid $!"
  else
    echo "[meta-web] bridge.mjs not found - skipping"
  fi
fi

# =============================================================================
# 2.5 DEEPSEEK-WEB BRIDGE  (20137) - pure Node, no browser needed. Replaces the
#     gateway's built-in deepseek-web executor with one that AUTO-CONTINUES long
#     chats (DeepSeek's web API ends long responses with INCOMPLETE - the
#     "Continue generating" button - and the built-in executor truncates there).
# =============================================================================
if port_up 20137; then
  echo "[deepseek-web] already running on 20137 - skipping"
else
  if [ -f ~/omniroute-android/bridge/deepseek-web-bridge/bridge.mjs ]; then
    echo "[deepseek-web] starting bridge (20137, auto-continue)..."
    nohup node ~/omniroute-android/bridge/deepseek-web-bridge/bridge.mjs \
      >"$LOG_DIR/deepseek-web.log" 2>&1 &
    echo "[deepseek-web] pid $!"
  else
    echo "[deepseek-web] bridge.mjs not found - skipping"
  fi
fi

# =============================================================================
# 3. GEMINI / GFLOW BRIDGE  (20133) - python + gemini_webapi
# =============================================================================
if port_up 20133; then
  echo "[gflow] already running on 20133 - skipping"
else
  if [ -f ~/omniroute-android/bridge/gemini-bridge/bridge.py ]; then
    # curl_cffi's android abi3 wheel hard-links libpython3.13.so; on Termux
    # with python 3.14 that lib does not exist, so dlopen fails. Provide a
    # symlink to the real lib (stable-ABI - safe) if python is 3.14.
    if [ -f "$PREFIX/lib/libpython3.14.so" ] && [ ! -e "$PREFIX/lib/libpython3.13.so" ]; then
      ln -sf "$PREFIX/lib/libpython3.14.so" "$PREFIX/lib/libpython3.13.so" 2>/dev/null \
        && echo "[gflow] libpython3.13.so -> libpython3.14.so symlink created (curl_cffi abi3 wheel)"
    fi
    echo "[gflow] starting gemini bridge (20133)..."
    nohup python ~/omniroute-android/bridge/gemini-bridge/bridge.py \
      >"$LOG_DIR/gemini.log" 2>&1 &
    echo "[gflow] pid $!"
  else
    echo "[gflow] bridge.py not found - skipping"
  fi
fi

# =============================================================================
# 4. FLOWUI BRIDGE  (20134) - needs chromium (installed via tur-repo)
# =============================================================================
if port_up 20134; then
  echo "[flowui] already running on 20134 - skipping"
else
  if [ -f ~/omniroute-android/bridge/flow-browser/flow-bridge.mjs ] && command -v chromium >/dev/null 2>&1; then
    echo "[flowui] starting flow bridge (20134, system chromium, headless)..."
    CHROME_PATH="$(command -v chromium)" \
    FLOW_HEADLESS=1 \
    nohup node ~/omniroute-android/bridge/flow-browser/flow-bridge.mjs \
      >"$LOG_DIR/flowui.log" 2>&1 &
    echo "[flowui] pid $!"
  else
    echo "[flowui] skipped (flow-bridge.mjs or chromium missing)"
  fi
fi

# =============================================================================
# 5.5 REGISTER BRIDGES IN THE GATEWAY - so the routes appear (mimo-web/*,
#     gflow/*, flowui/*). Self-contained scripts that write the gateway's
#     storage DB directly (~/.omniroute/storage.sqlite); idempotent and safe
#     every boot. The DB exists once the gateway has started once, so this
#     runs after the warm-up wait above.
# =============================================================================
if [ -f ~/.omniroute/storage.sqlite ]; then
  for reg in \
    ~/omniroute-android/bridge/mimo-web-bridge/register-mimo-web.mjs \
    ~/omniroute-android/bridge/meta-web-bridge/register-meta-web.mjs \
    ~/omniroute-android/bridge/deepseek-web-bridge/register-deepseek-web.mjs \
    ~/omniroute-android/bridge/gemini-bridge/register-gflow.mjs \
    ~/omniroute-android/bridge/flow-browser/register-flowui.mjs; do
    if [ -f "$reg" ]; then
      echo "[register] $(basename "$(dirname "$reg")")"
      ( cd "$(dirname "$reg")" && node "$(basename "$reg")" ) >>"$LOG_DIR/register.log" 2>&1 \
        || echo "    (registration failed - see $LOG_DIR/register.log)"
    fi
  done
else
  echo "[register] gateway DB not found yet - skipping (routes appear after next boot)"
fi

# =============================================================================
# 5. WARM-UP + STATUS
# =============================================================================
echo
echo "Waiting for the gateway to answer (up to 90s - it cold-starts slowly)..."
for _ in $(seq 1 90); do
  if curl -s -m 2 -o /dev/null "http://127.0.0.1:$PORT/v1/models"; then
    echo "[gateway] UP - $(curl -s -m 5 "http://127.0.0.1:$PORT/v1/models" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{try{console.log((JSON.parse(d).data||[]).length+' routes')}catch{console.log('(parsing)')}})" 2>/dev/null || echo "(counting)")"
    break
  fi
  sleep 1
done

# 5.5 PICKERS - mirror every gateway route into the Codex / Claude Code
#     pickers (catalog + cache seed + binary patch + combo/* routes).
#     Idempotent; skips cleanly if the CLIs aren't installed.
if [ -x ~/omniroute-android/fix-model-cache.sh ]; then
  echo "[pickers] syncing gateway routes into Codex / Claude Code pickers..."
  NO_INSTALL=1 bash ~/omniroute-android/fix-model-cache.sh >>"$LOG_DIR/pickers.log" 2>&1 \
    || echo "[pickers] sync failed - see $LOG_DIR/pickers.log (rerun: bash ~/omniroute-android/fix-model-cache.sh)"
else
  echo "[pickers] fix-model-cache.sh not present - skipping (installer payload is older)"
fi

echo
echo "Port status:"
for p in "$PORT" 20133 20134 20135 20136 20137; do
  port_up "$p" && echo "  $p : UP" || echo "  $p : down"
done
echo
echo "Push your web sessions in Kiwi Browser (Cookie Pusher -> Grab & push) to"
echo "unlock the cookie-backed providers (zai/qwen/deepseek/lmarena/mimo/gemini)."
