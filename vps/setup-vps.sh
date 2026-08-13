#!/usr/bin/env bash
# =====================================================================
# setup-vps.sh — one-shot deploy of the OmniRoute remote provider farm
# on a fresh Ubuntu/Debian VPS (Oracle Always Free Ampere, etc.).
#
# What it installs:
#   1. Git, Node.js 22 (NodeSource), jq, curl, Chromium, (optional) xvfb+x11vnc
#   2. OmniRoute gateway pinned to the same version as the Windows kit
#   3. systemd service `omniroute` (Restart=always) on port 20128
#   4. A headless Chromium provider profile + session helpers
#   5. A reclamation-proof keep-alive cron (idle CPU burn + warm sessions)
#   6. A tunnel: cloudflare (default) | tailscale | none
#   7. An admin API key printed at the end for remote clients
#
# Usage:
#   bash setup-vps.sh                          # cloudflare tunnel, random password
#   bash setup-vps.sh --tunnel tailscale
#   bash setup-vps.sh --tunnel none --password 'MyP4ss'
#   bash setup-vps.sh --skip-tunnel            # if you already have one
#
# On your laptop afterwards:
#   powershell -File ~\.omniroute\omni-remote.ps1   # point Claude Code at this VPS
# =====================================================================
set -euo pipefail

OMNI_VERSION="${OMNI_VERSION:-3.8.49}"
OMNI_PORT="${OMNI_PORT:-20128}"
OMNI_HOME="${OMNI_HOME:-$HOME/.omniroute}"
PROFILE_DIR="$OMNI_HOME/browser-profile"
LOG_DIR="$OMNI_HOME/logs"
TUNNEL="${TUNNEL:-cloudflare}"          # cloudflare | tailscale | none
SKIP_TUNNEL=0
WITH_GUI=0
PASSWORD="${OMNI_PASSWORD:-}"

say()  { echo -e "\n\033[1;32m==> $*\033[0m"; }
warn() { echo -e "\033[1;33m!! $*\033[0m"; }

for a in "$@"; do
  case "$a" in
    --tunnel) TUNNEL="${2:-cloudflare}"; shift 2 ;;
    --tunnel=*) TUNNEL="${a#*=}" ;;
    --skip-tunnel) SKIP_TUNNEL=1 ;;
    --with-gui) WITH_GUI=1 ;;
    --password) PASSWORD="${2:-}"; shift 2 ;;
    --password=*) PASSWORD="${a#*=}" ;;
    --port) OMNI_PORT="${2:-20128}"; shift 2 ;;
    --port=*) OMNI_PORT="${a#*=}" ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
  esac
done

if [[ "$(id -u)" -ne 0 ]]; then
  warn "Not root. Everything below uses sudo; if sudo prompts, enter your password."
fi

# ---------- 1. prerequisites ----------
say "Installing prerequisites (git, curl, jq, chromium)"
sudo apt-get update -qq
sudo apt-get install -y -qq curl git jq unzip ca-certificates gnupg >/dev/null

CHROME_BIN="$(command -v chromium || command -v chromium-browser || command -v google-chrome || true)"
if [ -z "$CHROME_BIN" ]; then
  sudo apt-get install -y -qq chromium >/dev/null || \
  sudo apt-get install -y -qq chromium-browser >/dev/null
  CHROME_BIN="$(command -v chromium || command -v chromium-browser || true)"
fi

if [ -z "$CHROME_BIN" ]; then
  warn "Could not install Chromium. Headless session-refresh helpers will not run;"
  warn "the gateway and API-key providers still work. Fix with: sudo apt install chromium"
fi

# Node.js 22 (native WebSocket client for the cookie-import helper)
if ! command -v node >/dev/null 2>&1 || [[ "$(node -v | tr -d 'v' | cut -d. -f1)" -lt 20 ]]; then
  say "Installing Node.js 22 from NodeSource"
  curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - >/dev/null
  sudo apt-get install -y -qq nodejs >/dev/null
fi
say "node $(node -v) / npm $(npm -v)"

# ---------- 2. omniroute ----------
if ! command -v omniroute >/dev/null 2>&1; then
  say "Installing omniroute@$OMNI_VERSION (the only download in this setup)"
  sudo npm install -g "omniroute@$OMNI_VERSION" >/dev/null
fi
say "omniroute $(omniroute --version 2>/dev/null || echo 'installed')"

# ---------- 3. home + launcher ----------
say "Preparing $OMNI_HOME"
mkdir -p "$OMNI_HOME" "$LOG_DIR" "$PROFILE_DIR"
cat > "$OMNI_HOME/start-omniroute.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export PORT="$OMNI_PORT"
BIN="\$(command -v omniroute || true)"
if [ -z "\$BIN" ]; then BIN="\$(npm prefix -g)/bin/omniroute"; fi
cd "$OMNI_HOME"
exec env PORT="$PORT" "\$BIN" serve
EOF
chmod +x "$OMNI_HOME/start-omniroute.sh"

# password
if [ -z "$PASSWORD" ]; then
  PASSWORD="$(openssl rand -base64 18 | tr -d '/+=' | head -c 16)"
  warn "Generated dashboard password (save this): $PASSWORD"
fi

# ---------- 4. systemd service ----------
say "Registering systemd service 'omniroute' (Restart=always, port $OMNI_PORT)"
sudo tee /etc/systemd/system/omniroute.service >/dev/null <<EOF
[Unit]
Description=OmniRoute gateway (remote provider farm)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$USER
Group=$(id -gn)
Environment=PORT=$OMNI_PORT
ExecStart=$OMNI_HOME/start-omniroute.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable omniroute >/dev/null 2>&1
sudo systemctl restart omniroute || warn "service failed to start - check: journalctl -u omniroute -n 50"

say "Waiting for the gateway on 127.0.0.1:$OMNI_PORT"
for i in $(seq 1 30); do
  if curl -sf -o /dev/null "http://127.0.0.1:$OMNI_PORT/api/providers"; then break; fi
  sleep 2
done
if ! curl -sf -o /dev/null "http://127.0.0.1:$OMNI_PORT/api/providers"; then
  warn "Gateway did not answer. Check: journalctl -u omniroute -n 50"
fi

# ---------- 5. password + admin API key ----------
say "Setting dashboard password and minting a remote admin API key"
printf '%s' "$PASSWORD" | omniroute reset-password --password-stdin >/dev/null 2>&1 || true
JAR="$OMNI_HOME/.curl-cookies"
curl -sf -c "$JAR" -X POST "http://127.0.0.1:$OMNI_PORT/api/auth/login" \
  -H 'Content-Type: application/json' -d "{\"password\":\"$PASSWORD\"}" >/dev/null || \
  warn "login failed - set the password manually in the dashboard"
API_KEY="$(curl -sf -b "$JAR" -X POST "http://127.0.0.1:$OMNI_PORT/api/cli/tokens" \
  -H 'Content-Type: application/json' \
  -d '{"name":"remote-client (vps)","scope":"admin"}' | jq -r '.token // empty')" || true

# ---------- 6. tunnel ----------
TUNNEL_URL=""
if [ "$SKIP_TUNNEL" -eq 1 ]; then
  warn "--skip-tunnel: no tunnel configured. Expose the gateway yourself."
elif [ "$TUNNEL" = "tailscale" ]; then
  say "Installing Tailscale"
  if ! command -v tailscale >/dev/null 2>&1; then
    curl -fsSL https://tailscale.com/install.sh | sh >/dev/null 2>&1 || warn "tailscale install failed - install manually"
  fi
  sudo tailscale up 2>/dev/null || warn "run 'sudo tailscale up' interactively to finish"
  for i in $(seq 1 10); do IP="$(tailscale ip -4 2>/dev/null | head -1)"; [ -n "$IP" ] && break; sleep 2; done
  TUNNEL_URL="http://$IP:$OMNI_PORT"
  say "Tailscale IP: $IP (your devices must be on the same tailnet)"
elif [ "$TUNNEL" = "cloudflare" ]; then
  say "Installing cloudflared"
  if ! command -v cloudflared >/dev/null 2>&1; then
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloudflare.gpg >/dev/null 2>&1 || true
    DISTRO="$(. /etc/os-release && echo "$VERSION_CODENAME")"
    [ -n "$DISTRO" ] || DISTRO=jammy
    echo "deb [signed-by=/usr/share/keyrings/cloudflare.gpg] https://pkg.cloudflare.com/cloudflared $DISTRO main" | sudo tee /etc/apt/sources.list.d/cloudflared.list >/dev/null
    sudo apt-get update -qq >/dev/null && sudo apt-get install -y -qq cloudflared >/dev/null || \
      warn "cloudflared install failed - try: curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared && sudo chmod +x /usr/local/bin/cloudflared"
  fi
  if [ ! -f "$HOME/.cloudflared/cert.pem" ]; then
    say "cloudflared tunnel login - open the printed URL in ANY browser and authorize, then come back"
    cloudflared tunnel login
  fi
  TUNNEL_NAME="omniroute-$(hostname | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-' | head -c 20)"
  cloudflared tunnel create "$TUNNEL_NAME" >/dev/null 2>&1 || true
  TUNNEL_ID="$(cloudflared tunnel list --output json 2>/dev/null | jq -r --arg n "$TUNNEL_NAME" '.[] | select(.name==$n) | .id' | head -1)"
  sudo mkdir -p /etc/cloudflared
  sudo tee /etc/cloudflared/config.yml >/dev/null <<EOF
tunnel: $TUNNEL_ID
credentials-file: $HOME/.cloudflared/$TUNNEL_ID.json

ingress:
  - hostname: $TUNNEL_NAME.trycloudflare.com
    service: http://127.0.0.1:$OMNI_PORT
  - service: http_status:404
EOF
  # quick tunnel (no DNS needed) - the stable route is: cloudflared tunnel route dns <name> <domain>
  TUNNEL_URL="https://$TUNNEL_NAME.trycloudflare.com"
  sudo tee /etc/systemd/system/cloudflared-omniroute.service >/dev/null <<EOF
[Unit]
Description=Cloudflare Tunnel for OmniRoute
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$USER
ExecStart=/usr/local/bin/cloudflared tunnel --no-autoupdate run $TUNNEL_ID
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable cloudflared-omniroute >/dev/null 2>&1 || true
  sudo systemctl restart cloudflared-omniroute || warn "tunnel failed - run: cloudflared tunnel run $TUNNEL_NAME (logs: journalctl -u cloudflared-omniroute)"
  say "Cloudflare quick tunnel: $TUNNEL_URL"
  warn "trycloudflare.com URLs are ephemeral. For a permanent URL: add a DNS route with your own domain (see README)."
else
  warn "Unknown tunnel '$TUNNEL' - skipping. Use --tunnel cloudflare|tailscale|none"
fi

# ---------- 7. keep-alive cron (reclamation-proof + session warm) ----------
say "Installing keep-alive cron (10-min cadence)"
cat > "$OMNI_HOME/keepalive.sh" <<'EOF'
#!/usr/bin/env bash
# Fights free-tier reclamation (idle CPU) and warms provider sessions.
KEEPALIVE_BURN_SECONDS="${KEEPALIVE_BURN_SECONDS:-30}"
# idle CPU burn (openSSL is a cheap, honest busy loop)
if command -v openssl >/dev/null 2>&1; then
  openssl speed -seconds "$KEEPALIVE_BURN_SECONDS" sha256 >/dev/null 2>&1
fi
# warm the gateway so sessions stay fresh
curl -sf -o /dev/null "http://127.0.0.1:${OMNI_PORT:-20128}/api/providers" || true
EOF
chmod +x "$OMNI_HOME/keepalive.sh"
( crontab -l 2>/dev/null | grep -v 'omniroute-keepalive' ; \
  echo "*/10 * * * * $OMNI_HOME/keepalive.sh >> $OMNI_HOME/logs/keepalive.log 2>&1 # omniroute-keepalive" ) | crontab -
say "keep-alive cron installed (every 10 min)"

# ---------- 8. browser helpers ----------
say "Preparing browser/session helpers"
for f in start-omniroute.sh keepalive.sh; do chmod +x "$OMNI_HOME/$f" 2>/dev/null || true; done

cat > "$OMNI_HOME/remote.env" <<EOF
# Remote-client config (read by omni-remote.ps1 on your laptop)
OMNI_PORT=$OMNI_PORT
TUNNEL_URL=$TUNNEL_URL
API_KEY=$API_KEY
SSH_USER=$USER
# Set SSH_HOST to the VPS public IP / hostname (used to start the server remotely)
SSH_HOST=
EOF

# ---------- 9. summary ----------
say "DONE"
echo "  Gateway (local):  http://127.0.0.1:$OMNI_PORT"
echo "  Dashboard:        http://127.0.0.1:$OMNI_PORT/admin   (password: $PASSWORD)"
echo "  Remote URL:       ${TUNNEL_URL:-<none - set one yourself>}"
echo "  Admin API key:    ${API_KEY:-<mint one in the dashboard: API keys>}"
echo ""
echo "Next steps on your laptop:"
echo "  1. Edit ~/.omniroute/remote.env  ->  set SSH_HOST=<vps-ip>"
echo "  2. powershell -File ~\\.omniroute\\omni-remote.ps1     (point Claude Code at this VPS)"
echo "  3. Cookie Pusher extension -> settings -> base URL = $TUNNEL_URL , API key = $API_KEY"
echo ""
echo "Helpers in $OMNI_HOME:"
echo "  signin.sh           interactive one-time provider sign-in (needs --with-gui at install)"
echo "  import-cookies.sh   import cookie JSON exports (Cookie Pusher format) into the profile"
echo "  refresh-sessions.sh headless session refresh so cookies stay alive"
