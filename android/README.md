# OmniRoute on Android — one-file, hands-free

Run the whole OmniRoute stack (gateway + all web-cookie bridges + Cookie
Pusher) on your **everyday phone**. One file, one command, set up once —
after that it auto-starts on every boot and never needs re-installing.

## Files in this folder

| File | What it is |
|---|---|
| **`install-omniroute.sh`** | **THE one file you need.** Self-contained installer: embeds all 3 bridges + the extension + start/boot scripts. Run it once. |
| `start-omniroute.sh` | Starts the stack (idempotent — safe any time). Also embedded in the installer. |
| `boot.sh` | Termux:Boot entry point (auto-start on phone boot). Also embedded. |
| `serve-installer.cmd` | Optional Windows helper: serves the folder so the phone can download the installer over Wi-Fi. |

## Complete walkthrough — beginning to end

**On the phone (one time, ~10 minutes):**

1. **Install from F-Droid** (not the Play Store — Play Store Termux is abandoned):
   - **Termux** (com.termux)
   - **Termux:Boot** (com.termux.boot)
   - Optional: **Termux:API** (wake lock), **Termux:Widget** (home-screen buttons)
   - **Kiwi Browser** (Play Store or F-Droid) — the only Android browser that
     loads unpacked extensions
2. **Get `install-omniroute.sh` onto the phone** — any of:
   - **Send Anywhere**: on the PC `sendanywhere send install-omniroute.sh`,
     enter the 6-digit key in the Send Anywhere app on the phone; or
   - **serve-installer.cmd** on the PC, then in Termux
     `curl -O http://<PC-IP>:8080/install-omniroute.sh`; or
   - copy it via USB / file manager / WhatsApp into `~/Downloads`.
3. **Open Termux** and run the installer:
   ```bash
   termux-setup-storage        # one-time storage grant (only if you copied via /sdcard)
   cd ~/Downloads && bash install-omniroute.sh
   ```
   (or `cd && mv ~/Downloads/install-omniroute.sh . && bash install-omniroute.sh`)
   It installs the **lean default (~1.5GB)** and **starts the stack** — wait
   for the port status table at the end (gateway + mimo-web UP; gflow/flowui
   report `down` until you opt in with `FULL=1`).
4. **One-time app setup (~2 minutes):**
   - Kiwi → `chrome://extensions` → Developer mode → **Load unpacked** →
     `/sdcard/omniroute-cookie-pusher`
   - Sign in on the sites you use (z.ai, chat.qwen.ai, deepseek.com,
     aistudio.xiaomimimo.com, arena.ai, gemini.google.com, …) → open the
     Cookie Pusher extension → **Grab & push sessions**
   - Open the **Termux:Boot** app once (arms boot autostart)
   - Settings → Apps → **Termux** and **Termux:Boot** → Battery →
     **Unrestricted**
5. **Verify:** dashboard at `http://127.0.0.1:20128`; from your PC on the same
   Wi-Fi, `http://<phone-ip>:20128` (phone IP in Wi-Fi settings or `ifconfig`).

**After this — nothing to redo, ever.** Phone reboot → Termux:Boot restarts
it; open Termux → the `~/.bashrc` hook restarts it; a provider expires your
session → Kiwi → Grab & push (30 seconds). Cutting the internet never breaks
anything.

## Quick start (one command)

1. Install **Termux** and **Termux:Boot** from **F-Droid** (not the Play Store).
2. Get `install-omniroute.sh` onto the phone:
   - Easiest: on your PC run `serve-installer.cmd`, then in Termux:
     ```bash
     curl -O http://<PC-IP>:8080/install-omniroute.sh
     bash install-omniroute.sh
     ```
   - Or copy the file via USB / file manager / WhatsApp → `~/Downloads`, then
     `bash ~/Downloads/install-omniroute.sh` (Termux reads `~/Downloads` after
     one `termux-setup-storage`).
3. When it finishes, the stack is **already running**. The script prints the
   one-time app steps: load the extension in Kiwi, push sessions, open
   Termux:Boot once, set Battery → Unrestricted.

That's it. The default install is already the **lean profile (~1.5GB)**: the
gateway, the mimo-web bridge and the Cookie Pusher extension — every chat
route (zai/qwen/deepseek/lmarena/mimo/gemini-web) works. The heavy extras are
opt-in:
- `FULL=1 bash install-omniroute.sh` — everything, **~5-6GB** (adds Chromium
  ~1GB for Google Flow images + the gemini bridge build ~1.5GB, then strips
  the rust/clang toolchains).
- `FLOW=1 bash install-omniroute.sh` — Chromium + Flow images only.
- `GEMINI=1 bash install-omniroute.sh` — the gemini bridge only.

## Everyday-phone answers

**How much storage does it take?**
The **lean default is ~1.5-2GB** (Termux + nodejs + the gateway + the
mimo-web bridge + the extension, with npm/pip/pkg caches purged at the end).
A **full install (`FULL=1`) is ~5-6GB**: Chromium from tur-repo brings ~1GB
of GTK deps, and the gemini bridge compiles pydantic-core/orjson with Rust
(~1.5GB while building — `SAVE_SPACE=1`, which `FULL=1` sets automatically,
removes the rust/clang/make toolchains afterwards). So: run the default, and
only add `FLOW=1`/`GEMINI=1` when you actually use Google Flow images or the
gemini bridge. Re-running the installer with the flags later adds just those
parts — nothing is reinstalled.

**Will cutting the internet affect it?**
No. Everything runs locally on the phone. Cutting Wi-Fi/data does not stop the
gateway or bridges, and does not break the install. Cookie-backed routes
(zai/qwen/deepseek/lmarena/mimo/gemini) simply fail while offline and work
again the moment the connection returns. No re-setup, ever.

**Will I have to do steps again and again?**
No. After the one-time run:
- **Phone reboot** → Termux:Boot starts the whole stack automatically (you
  opened the Termux:Boot app once to arm it).
- **Termux opened** → a `~/.bashrc` hook starts the stack if it isn't running
  (no-op when it is).
- **Battery/Doze** → the installer takes a wake lock and requests the
  background whitelist; set **Settings → Apps → Termux + Termux:Boot →
  Battery → Unrestricted** once so Android never kills it.
- The installer itself is **idempotent**: re-running it never wipes or
  duplicates anything (it even keeps your existing `.env`). Worst case in the
  world: reinstall Termux → run the same one file again.

**Anything else to know?**
- **Provider sessions expire on their own** (zai challenges, arena/logged-in
  sessions). When a route goes 403/405, open Kiwi → Cookie Pusher → **Grab &
  push sessions** — 30 seconds, not a re-setup. Internet drops don't cause
  this by themselves.
- **Battery drain is small** while idle, but the gateway does poll providers;
  on metered mobile data that's background data. Wi-Fi for heavy use.
- **LAN security**: the gateway binds `0.0.0.0`, so any device on the same
  Wi-Fi can reach it at `http://<phone-ip>:20128`. That's how you use it from
  your PC/other devices. Keep the phone on trusted networks; to restrict to
  the phone itself, change `HOST=127.0.0.1` in `~/.omniroute/.env` (and the
  `--port` line in `start-omniroute.sh` keeps working).   - **Status check**: `bash ~/omniroute-android/start-omniroute.sh` any time —
     it reports which ports are up and starts anything missing. Or use the
     home-screen widget: install **Termux:Widget**, long-press the home screen
     → Widgets → Termux:Widget → pick `omniroute-status` (ports) or
     `omniroute-restart` (restart stack).
   - **Battery-saver polling**: to suspend the stack while the screen is off
     (near-zero battery/data when idle) and wake it with the screen, start it
     with `POWER_SAVE=1 bash ~/omniroute-android/start-omniroute.sh`. The
     installer's default keeps the wake lock always on (snappier, slightly
     more battery).

## One-time app setup (printed by the installer too)

1. **Kiwi Browser** (only Android browser that loads unpacked extensions):
   `chrome://extensions` → enable Developer mode → **Load unpacked** →
   `/sdcard/omniroute-cookie-pusher` (the installer copies it there).
2. Sign in on the sites you use (z.ai, chat.qwen.ai, deepseek.com,
   aistudio.xiaomimimo.com, arena.ai, gemini.google.com, …), then open the
   Cookie Pusher extension → **Grab & push sessions**.
3. Open the **Termux:Boot** app once (arms boot autostart).
4. Settings → Apps → Termux + Termux:Boot → Battery → **Unrestricted**.
5. Optional: install **Termux:API** from F-Droid for `termux-wake-lock`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Routes fail after phone slept a while | Battery → Unrestricted for Termux; open Termux (the bashrc hook restarts the stack) |
| Nothing answers after reboot | Termux:Boot wasn't armed → open it once; or run `bash ~/omniroute-android/start-omniroute.sh` |
| One provider 403/405 | Session expired → Kiwi → Cookie Pusher → Grab & push (that provider only) |
| Terminal shows `omniroute: command not found` | `pkg install nodejs-lts` then `npm install -g omniroute@latest`, or re-run the installer |
| Reinstalled Termux / new phone | Copy the same one file again → `bash install-omniroute.sh` |

## Moving everything from the PC to the phone (sessions + kit + Claude persona)

The PC's pushed web sessions, combos, routes, the full kit, and your Claude
Code skills/agents/commands can all move to the phone in ONE file:

**On the PC (Git Bash):**
```bash
bash ~/omniroute-setup-kit/android/make-transfer.sh
# -> ~/omniroute-setup-kit/omniroute-transfer.tar.gz (14MB)
```
It snapshots the gateway DB (WAL-safe `VACUUM INTO` — safe while the gateway
runs) + `~/.omniroute/.env` (the encryption key that unlocks the sessions),
packs the kit, and your `~/.claude` persona.

**Send that one file to the phone** (WhatsApp), then in Termux:
```bash
cd ~/storage/downloads
tar xzf omniroute-transfer.tar.gz import-transfer.sh
bash import-transfer.sh omniroute-transfer.tar.gz
```
The importer stops the stack, backs up the phone's state, merges the PC
encryption key into `~/.omniroute/.env` (keeps the phone's PORT/HOST/
ZAI_CAPTCHA_WORKER), swaps in the imported session DB, installs the kit +
refreshes the launcher scripts, imports the Claude persona (Windows-only
hooks are skipped so tools never get blocked), then restarts + syncs pickers.

## How it works on Android (no native builds)

- **SQLite**: the gateway falls back `better-sqlite3` → `node:sqlite` (built
  into Node 24) → `sql.js` (WASM) — zero compilation on Termux.
- **Browsers**: no Playwright download needed; the flowui bridge uses system
  Chromium via `CHROME_PATH` (`pkg install chromium`).
- **zai captcha**: the worker ships inside the npm package; `.env` points at it
  and it stays headed (a real browser is required by zai's anti-bot).
- **Autostart**: Termux:Boot (boot) + `~/.bashrc` hook (Termux open) + wake
  lock (battery).
