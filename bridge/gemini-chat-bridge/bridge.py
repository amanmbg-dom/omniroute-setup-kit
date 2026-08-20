#!/usr/bin/env python
"""
Gemini Chat Bridge — OpenAI-compatible local bridge for Google Gemini web chat
(authenticated via __Secure-1PSID / __Secure-1PSIDTS cookies).

Uses gemini_webapi (same library as the image bridge) for correct protobuf
encoding and response parsing.

Serves (OpenAI format, consumed by OmniRoute):
  GET  /v1/models              — Gemini model list
  POST /v1/chat/completions    — translated chat, SSE streamed
  POST /v1/cookies             — Cookie Pusher endpoint
  GET  /healthz                — liveness probe
"""

import asyncio
import json
import os
import sys
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Thread

PORT = int(os.environ.get("GEMINI_CHAT_PORT", "20138"))
HOST = os.environ.get("GEMINI_CHAT_HOST", "127.0.0.1")
DATA_DIR = Path(os.environ.get("DATA_DIR", Path.home() / ".omniroute"))
COOKIE_FILE = DATA_DIR / "gemini-cookies.json"
LOG_FILE = DATA_DIR / "gemini-chat-bridge.log"

try:
    from gemini_webapi import GeminiClient
except ImportError:
    print("FATAL: gemini_webapi not importable. Use the gemini-bridge venv.", file=sys.stderr)
    sys.exit(1)


def log(msg: str):
    line = f"[{time.strftime('%Y-%m-%dT%H:%M:%S')}] {msg}"
    print(line, flush=True)
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except OSError:
        pass


def load_cookies() -> dict:
    try:
        data = json.loads(COOKIE_FILE.read_text(encoding="utf-8"))
        psid = data.get("__Secure-1PSID") or data.get("__Secure1PSID") or ""
        psidts = data.get("__Secure-1PSIDTS") or data.get("__Secure1PSIDTS") or ""
        return {"psid": psid, "psidts": psidts}
    except Exception as e:
        return {"psid": "", "psidts": "", "error": str(e)}


def save_cookies(cookies: dict):
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    data = {}
    if cookies.get("psid"):
        data["__Secure-1PSID"] = cookies["psid"]
    if cookies.get("psidts"):
        data["__Secure-1PSIDTS"] = cookies["psidts"]
    data["syncedAt"] = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())
    COOKIE_FILE.write_text(json.dumps(data, indent=2), encoding="utf-8")
    log(f"Cookies saved to {COOKIE_FILE}")


def extract_messages_text(messages: list) -> str:
    """Convert OpenAI message list to a single prompt string."""
    parts = []
    for msg in messages:
        role = msg.get("role", "user")
        content = msg.get("content", "")
        if isinstance(content, list):
            # Handle multimodal content
            content = " ".join(
                block.get("text", "") for block in content if block.get("type") == "text"
            )
        parts.append(f"{role}: {content}")
    return "\n\n".join(parts)


def model_name_to_id(model: str) -> str:
    """Map OpenAI-style model names to Gemini names."""
    mapping = {
        "gemini-2.5-flash": "gemini-2.5-flash",
        "gemini-2.5-pro": "gemini-2.5-pro",
        "gemini-2.0-flash": "gemini-2.0-flash",
        "gemini-1.5-flash": "gemini-1.5-flash",
        "gemini-1.5-pro": "gemini-1.5-pro",
    }
    return mapping.get(model, model)


# ── Async helpers ────────────────────────────────────────────────────────

_loop = asyncio.new_event_loop()


def _run_async(coro):
    """Run an async coroutine in the background event loop."""
    future = asyncio.run_coroutine_threadsafe(coro, _loop)
    return future.result(timeout=180)


async def _init_client(psid: str, psidts: str):
    """Initialize and return a GeminiClient."""
    client = GeminiClient(psid, psidts, proxy=None)
    await client.init(timeout=300, auto_close=False, auto_refresh=False)
    return client


# ── Chat completion (non-streaming) ─────────────────────────────────────

async def _chat_completion(messages, model, max_tokens=None, temperature=None):
    cookies = load_cookies()
    if not cookies["psid"]:
        return {
            "error": {
                "message": "No Gemini session. Sign in at gemini.google.com, then Cookie Pusher → Grab & push sessions.",
                "type": "authentication_error",
            }
        }
    try:
        client = await _init_client(cookies["psid"], cookies["psidts"])
    except Exception as e:
        return {
            "error": {
                "message": f"Failed to initialize Gemini client: {e}",
                "type": "upstream_error",
            }
        }
    try:
        prompt = extract_messages_text(messages)
        gemini_model = model_name_to_id(model)
        resp = await client.generate_content(
            prompt=prompt,
            model=gemini_model,
            temporary=True,
        )
        content = resp.text or ""
        return {
            "id": f"chatcmpl-{uuid.uuid4()}",
            "object": "chat.completion",
            "created": int(time.time()),
            "model": model,
            "choices": [
                {
                    "index": 0,
                    "message": {"role": "assistant", "content": content},
                    "finish_reason": "stop",
                }
            ],
            "usage": {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0},
        }
    except Exception as e:
        return {
            "error": {
                "message": f"Gemini error: {e}",
                "type": "upstream_error",
            }
        }
    finally:
        try:
            await client.close()
        except Exception:
            pass


# ── Chat completion (streaming) ─────────────────────────────────────────

def _swrite(resp_writer, text):
    """Write a string as bytes to the wfile."""
    resp_writer.write(text.encode("utf-8"))
    resp_writer.flush()


async def _chat_completion_stream(messages, model, resp_writer):
    cookies = load_cookies()
    if not cookies["psid"]:
        error = {
            "error": {
                "message": "No Gemini session. Sign in at gemini.google.com, then Cookie Pusher → Grab & push sessions.",
                "type": "authentication_error",
            }
        }
        _swrite(resp_writer, f"data: {json.dumps(error)}\n\n")
        _swrite(resp_writer, "data: [DONE]\n\n")
        return
    try:
        client = await _init_client(cookies["psid"], cookies["psidts"])
    except Exception as e:
        error = {"error": {"message": f"Failed to init: {e}", "type": "upstream_error"}}
        _swrite(resp_writer, f"data: {json.dumps(error)}\n\n")
        _swrite(resp_writer, "data: [DONE]\n\n")
        return
    try:
        prompt = extract_messages_text(messages)
        gemini_model = model_name_to_id(model)
        msg_id = f"chatcmpl-{uuid.uuid4()}"
        base = {
            "id": msg_id,
            "object": "chat.completion.chunk",
            "created": int(time.time()),
            "model": model,
        }
        sent_role = False
        chunk_count = 0
        try:
            async for chunk in client.generate_content_stream(
                prompt=prompt, model=gemini_model, temporary=True
            ):
                delta_text = getattr(chunk, "text_delta", None) or ""
                if not sent_role:
                    role_chunk = {
                        **base,
                        "choices": [{"index": 0, "delta": {"role": "assistant"}, "finish_reason": None}],
                    }
                    _swrite(resp_writer, f"data: {json.dumps(role_chunk)}\n\n")
                    sent_role = True
                if delta_text:
                    chunk_count += 1
                    text_chunk = {
                        **base,
                        "choices": [{"index": 0, "delta": {"content": delta_text}, "finish_reason": None}],
                    }
                    _swrite(resp_writer, f"data: {json.dumps(text_chunk)}\n\n")
        except Exception as e:
            log(f"Stream generator error: {e}")
            if not sent_role:
                error = {"error": {"message": f"Gemini stream error: {e}", "type": "upstream_error"}}
                _swrite(resp_writer, f"data: {json.dumps(error)}\n\n")
        stop_chunk = {
            **base,
            "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}],
        }
        _swrite(resp_writer, f"data: {json.dumps(stop_chunk)}\n\n")
        _swrite(resp_writer, "data: [DONE]\n\n")
        log(f"Stream complete: {chunk_count} chunks")
    except Exception as e:
        error = {"error": {"message": f"Gemini stream error: {e}", "type": "upstream_error"}}
        _swrite(resp_writer, f"data: {json.dumps(error)}\n\n")
        _swrite(resp_writer, "data: [DONE]\n\n")
    finally:
        try:
            await client.close()
        except Exception:
            pass


# ── HTTP Server ─────────────────────────────────────────────────────────

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass

    def _send(self, status, body, ctype="application/json"):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def do_GET(self):
        if self.path == "/healthz":
            data = load_cookies()
            self._send(200, json.dumps({
                "ok": True,
                "status": "ok",
                "bridge": "gemini-chat",
                "port": PORT,
                "cookiesPresent": bool(data["psid"]),
            }).encode())
            return
        if self.path == "/v1/models":
            self._send(200, json.dumps({
                "object": "list",
                "data": [
                    {"id": "gemini-2.5-flash", "object": "model"},
                    {"id": "gemini-2.5-pro", "object": "model"},
                    {"id": "gemini-2.0-flash", "object": "model"},
                    {"id": "gemini-1.5-flash", "object": "model"},
                    {"id": "gemini-1.5-pro", "object": "model"},
                ],
            }).encode())
            return
        self._send(200, b"gemini-chat-bridge: POST /v1/chat/completions\n", "text/plain")

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0) or 0)
        raw = self.rfile.read(length) if length else b"{}"
        try:
            body = json.loads(raw.decode("utf-8") or "{}")
        except json.JSONDecodeError:
            self._send(400, json.dumps({"error": {"message": "invalid JSON", "type": "invalid_request_error"}}).encode())
            return

        if self.path == "/v1/cookies":
            cookies = body.get("cookies", body)
            # Normalize key names
            psid = cookies.get("__Secure-1PSID") or cookies.get("__Secure1PSID") or cookies.get("psid", "")
            psidts = cookies.get("__Secure-1PSIDTS") or cookies.get("__Secure1PSIDTS") or cookies.get("psidts", "")
            if not psid:
                self._send(400, json.dumps({"error": "no __Secure-1PSID cookie in payload"}).encode())
                return
            save_cookies({"psid": psid, "psidts": psidts})
            self._send(200, json.dumps({"ok": True}).encode())
            return

        if self.path == "/v1/chat/completions":
            messages = body.get("messages", [])
            model = body.get("model", "gemini-2.5-flash")
            stream = body.get("stream", False)
            max_tokens = body.get("max_tokens")
            temperature = body.get("temperature")

            if not messages:
                self._send(400, json.dumps({"error": {"message": "no messages", "type": "invalid_request_error"}}).encode())
                return

            log(f"Chat: model={model} stream={stream} messages={len(messages)}")

            if stream:
                # Streaming response
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.send_header("Cache-Control", "no-cache")
                self.send_header("Connection", "keep-alive")
                self.send_header("X-Accel-Buffering", "no")
                self.end_headers()

                async def _stream():
                    await _chat_completion_stream(messages, model, self.wfile)

                _run_async(_stream())
            else:
                # Non-streaming
                result = _run_async(_chat_completion(messages, model, max_tokens, temperature))
                if "error" in result:
                    self._send(502, json.dumps(result).encode())
                else:
                    self._send(200, json.dumps(result).encode())
            return

        self._send(404, json.dumps({"error": {"message": f"unknown route {self.path}", "type": "invalid_request_error"}}).encode())


def main():
    # Start the asyncio event loop in a background thread
    def _run_loop():
        asyncio.set_event_loop(_loop)
        _loop.run_forever()

    t = Thread(target=_run_loop, daemon=True)
    t.start()

    server = ThreadingHTTPServer((HOST, PORT), Handler)
    log(f"gemini-chat-bridge listening on http://{HOST}:{PORT}")
    log(f"Cookie file: {COOKIE_FILE}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log("Shutting down")
        server.shutdown()


if __name__ == "__main__":
    main()
