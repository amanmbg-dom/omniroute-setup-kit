"""
Google Flow / Gemini-web image bridge — the "token method".

Turns the Google session pushed to OmniRoute by the Cookie Pusher
(__Secure-1PSID / __Secure-1PSIDTS from gemini.google.com) into a free
OpenAI-compatible image-generation endpoint, served ONLY on 127.0.0.1.

The engine is the reverse-engineered `gemini_webapi` package (the same web
backend the free Gemini app uses — Nano Banana, no API key, no billing).

Flow:
  POST /v1/images/generations  {"prompt": "...", "n": 1}
    1. runs sync-cookies.mjs (exports the gemini-web session from OmniRoute DB)
    2. initializes gemini_webapi with those cookies
    3. asks the Gemini web app to generate the image
    4. returns OpenAI-format {"created":..., "data": [{"b64_json": "..."}]}

Run:  .venv\\Scripts\\python bridge.py   (port 20133 by default)
"""

import asyncio
import base64
import json
import os
import subprocess
import sys
import tempfile
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

PORT = int(os.environ.get("BRIDGE_PORT", "20133"))
DATA_DIR = Path(os.environ.get("DATA_DIR", Path.home() / ".omniroute"))
COOKIES_FILE = Path(os.environ.get("GEMINI_COOKIES_FILE", DATA_DIR / "gemini-cookies.json"))
SYNC_SCRIPT = Path(
    os.environ.get("GEMINI_SYNC_SCRIPT", Path(__file__).resolve().parent / "sync-cookies.mjs")
)
LOG_FILE = DATA_DIR / "gemini-bridge.log"

try:
    from gemini_webapi import GeminiClient
except ImportError as e:  # pragma: no cover
    print(f"FATAL: gemini_webapi not importable: {e}", file=sys.stderr)
    print("Create the venv first:  python -m venv .venv && .venv\\Scripts\\pip install -r requirements.txt")
    sys.exit(1)


def log(msg: str):
    line = f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}"
    print(line, flush=True)
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except OSError:
        pass


def sync_cookies() -> dict:
    """Run sync-cookies.mjs and load the resulting cookies JSON."""
    if not SYNC_SCRIPT.exists():
        raise RuntimeError(f"sync-cookies.mjs not found at {SYNC_SCRIPT}")
    proc = subprocess.run(
        ["node", str(SYNC_SCRIPT)],
        capture_output=True,
        text=True,
        timeout=60,
    )
    if proc.returncode != 0:
        raise RuntimeError((proc.stderr or proc.stdout).strip() or "cookie sync failed")
    if not COOKIES_FILE.exists():
        raise RuntimeError(f"cookie file missing after sync: {COOKIES_FILE}")
    data = json.loads(COOKIES_FILE.read_text(encoding="utf-8"))
    if not data.get("__Secure1PSID"):
        raise RuntimeError("no __Secure-1PSID in synced cookies")
    return data


async def generate_image(prompt: str, n: int = 1) -> list[str]:
    """Generate n images; returns list of base64 PNG strings."""
    cookies = sync_cookies()
    client = GeminiClient(cookies["__Secure1PSID"], cookies.get("__Secure1PSIDTS") or "", proxy=None)
    await client.init(timeout=300, auto_close=True, close_delay=120, auto_refresh=False)
    try:
        resp = await client.generate_content(prompt)
        images = list(resp.images or [])
        if not images:
            snippet = (resp.text or "")[:300].replace("\n", " ")
            raise RuntimeError(
                f"Gemini returned no image (model said: {snippet or 'nothing'}). "
                "Make sure the prompt asks for an image and the account is signed in at gemini.google.com."
            )
        wanted = max(1, min(int(n), len(images)))
        results = []
        with tempfile.TemporaryDirectory(prefix="gflow-") as td:
            for img in images[:wanted]:
                saved = await img.save(path=td)
                b64 = base64.b64encode(Path(saved).read_bytes()).decode("ascii")
                results.append(b64)
        return results
    finally:
        await client.close()


def openai_error(status: int, message: str) -> bytes:
    body = json.dumps({"error": {"message": message, "type": "invalid_request_error", "code": None}}).encode()
    return body


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # silence default stderr noise
        pass

    def _send(self, status: int, body: bytes, ctype: str = "application/json"):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def do_GET(self):
        if self.path.startswith("/health"):
            ok = COOKIES_FILE.exists()
            self._send(200, json.dumps({"ok": True, "cookiesPresent": ok, "port": PORT}).encode())
            return
        self._send(
            200,
            (
                "gemini-bridge: POST /v1/images/generations with {\"prompt\": \"...\"}\n"
                "health: GET /health\n"
                f"cookies file: {COOKIES_FILE}\n"
                f"log: {LOG_FILE}\n"
            ).encode(),
            "text/plain",
        )

    def do_POST(self):
        if not self.path.startswith("/v1/images/generations"):
            self._send(404, openai_error(404, f"unknown route {self.path}"))
            return
        length = int(self.headers.get("Content-Length", 0) or 0)
        raw = self.rfile.read(length) if length else b"{}"
        try:
            body = json.loads(raw.decode("utf-8") or "{}")
        except json.JSONDecodeError:
            self._send(400, openai_error(400, "invalid JSON body"))
            return

        prompt = (body.get("prompt") or "").strip()
        n = int(body.get("n", 1) or 1)
        if not prompt:
            self._send(400, openai_error(400, "missing 'prompt'"))
            return

        started = time.time()
        log(f"request: n={n} prompt={prompt[:80]!r}")
        try:
            b64s = asyncio.run(generate_image(prompt, n))
            out = {"created": int(time.time()), "data": [{"b64_json": b} for b in b64s]}
            log(f"ok: {len(b64s)} image(s) in {time.time() - started:.1f}s")
            self._send(200, json.dumps(out).encode())
        except Exception as e:  # noqa: BLE001 — surface everything to the gateway
            log(f"ERROR after {time.time() - started:.1f}s: {e}")
            msg = str(e)
            status = 401 if ("cookie" in msg.lower() or "authenticated" in msg.lower() or "signed in" in msg.lower()) else 502
            self._send(status, openai_error(status, f"gemini-bridge: {msg}"))


def main():
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    log(f"gemini-bridge listening on http://127.0.0.1:{PORT} (cookies: {COOKIES_FILE})")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
