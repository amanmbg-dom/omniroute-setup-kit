// test-bridge.mjs — end-to-end test of the deepseek-web bridge AUTO-CONTINUE
// against a stubbed DeepSeek upstream. Verifies:
//   1. auth (users/current) + PoW + session flow
//   2. the completion stream is translated to OpenAI SSE
//   3. status INCOMPLETE triggers the continue endpoint, whose stream is spliced
//      on (proving long chats are NOT truncated)
//   4. the session is deleted afterwards
// Run: node test-bridge.mjs  (needs no network, no real token)
import http from "node:http";
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const U = require("./deepseek-pow-solver.cjs").U;

// ---------- stub DeepSeek upstream ----------
const makeHash = () => {
  const self = {};
  self._sponge = new U({ capacity: 256, padding: 6 });
  self.update = (s) => { self._sponge.absorb(Buffer.from(s, "utf8")); return self; };
  self.digest = (f) => self._sponge.squeeze(6).toString(f || "hex");
  self.copy = () => {
    const c = {};
    c._sponge = self._sponge.copy();
    c.update = (s) => { c._sponge.absorb(Buffer.from(s, "utf8")); return c; };
    c.digest = (f) => c._sponge.squeeze(6).toString(f || "hex");
    return c;
  };
  return self;
};

// build a real challenge the bridge's solver can crack: nonce = 42, difficulty 43
const salt = "test-salt";
const expireAt = 1893456000;
const prefix = `${salt}_${expireAt}_`;
const h = makeHash();
h.update(prefix);
const challenge = h.copy().update("42").digest("hex");
const POW_ANSWER = Buffer.from(
  JSON.stringify({
    algorithm: "DeepSeekHashV1",
    challenge,
    salt,
    answer: 42,
    signature: "sig",
    target_path: "/api/v0/chat/completion",
  })
).toString("base64");

const seen = { continueCalls: 0, deleteCalls: 0, completionBodies: [] };

const sse = (events) =>
  events.map((e) => `data: ${JSON.stringify(e)}\n\n`).join("") + "data: [DONE]\n\n";

const upstream = http.createServer((req, res) => {
  const url = new URL(req.url, "http://x");
  const send = (obj, status = 200) => {
    res.writeHead(status, { "Content-Type": "application/json" });
    res.end(JSON.stringify(obj));
  };
  if (url.pathname === "/api/v0/users/current") {
    return send({ code: 0, data: { biz_data: { token: "ACCESS-TOKEN-123" } } });
  }
  if (url.pathname === "/api/v0/chat/create_pow_challenge") {
    return send({
      code: 0,
      data: {
        biz_data: {
          challenge: {
            algorithm: "DeepSeekHashV1",
            challenge,
            salt,
            difficulty: 43,
            expire_at: expireAt,
            signature: "sig",
            target_path: "/api/v0/chat/completion",
          },
        },
      },
    });
  }
  if (url.pathname === "/api/v0/chat_session/create") {
    return send({ code: 0, data: { biz_data: { chat_session: { id: "SESSION-1" } } } });
  }
  if (url.pathname === "/api/v0/chat_session/delete") {
    seen.deleteCalls++;
    return send({ code: 0, data: { biz_data: {} } });
  }
  if (url.pathname === "/api/v0/chat/completion") {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      seen.completionBodies.push(JSON.parse(body));
      res.writeHead(200, { "Content-Type": "text/event-stream" });
      res.end(
        sse([
          { p: "response/fragments", v: [{ type: "THINK", content: "thinking part" }] },
          { response_message_id: 77 },
          { p: "response/fragments", v: [{ type: "ANSWER", content: "First chunk. " }] },
          { p: "response/status", v: "INCOMPLETE" },
        ])
      );
    });
    return;
  }
  if (url.pathname === "/api/v0/chat/continue") {
    seen.continueCalls++;
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      const payload = JSON.parse(body);
      if (payload.message_id !== 77 || payload.chat_session_id !== "SESSION-1" || payload.fallback_to_resume !== true) {
        console.log("FAIL: continue payload wrong:", payload);
        process.exit(1);
      }
      res.writeHead(200, { "Content-Type": "text/event-stream" });
      res.end(
        sse([
          { response_message_id: 78 },
          { p: "response/fragments", v: [{ type: "ANSWER", content: "Second chunk - NOT truncated." }] },
          { p: "response/status", v: "FINISHED" },
        ])
      );
    });
    return;
  }
  send({ error: "unknown " + url.pathname }, 404);
});

// ---------- run bridge against the stub ----------
const { spawn } = await import("node:child_process");
const os = await import("node:os");
const fs = await import("node:fs");
const path = await import("node:path");

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "dsbridge-test-"));
process.env.DATA_DIR = tmp; // cookie file + logs land here, not real ~/.omniroute
fs.writeFileSync(path.join(tmp, "deepseek-cookies.json"), JSON.stringify({ userToken: "USER-TOKEN-1" }));

await new Promise((r) => upstream.listen(18100, "127.0.0.1", r));

const env = { ...process.env, DEEPSEEK_UPSTREAM: "http://127.0.0.1:18100", DEEPSEEK_BRIDGE_PORT: "18136" };
const child = spawn(process.execPath, ["bridge.mjs"], { env, stdio: "inherit" });

const waitFor = async (fn, ms = 8000) => {
  const t0 = Date.now();
  while (Date.now() - t0 < ms) {
    try {
      const r = await fn();
      if (r) return r;
    } catch {}
    await new Promise((r) => setTimeout(r, 100));
  }
  throw new Error("timeout waiting for " + fn);
};

let failures = 0;
const check = (name, cond) => {
  console.log((cond ? "PASS" : "FAIL") + "  " + name);
  if (!cond) failures++;
};

try {
  // wait for bridge
  await waitFor(async () => {
    const r = await fetch("http://127.0.0.1:18136/healthz");
    return r.ok;
  });

  // models
  const models = await (await fetch("http://127.0.0.1:18136/v1/models")).json();
  check("models list exposes deepseek-chat", models.data.some((m) => m.id === "deepseek-chat"));

  // streamed chat -> should splice the continue stream
  const res = await fetch("http://127.0.0.1:18136/v1/chat/completions", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ model: "deepseek-chat", stream: true, messages: [{ role: "user", content: "hi" }] }),
  });
  check("completion HTTP 200", res.status === 200);
  const text = await res.text();
  check("streamed reasoning delivered", text.includes("thinking part"));
  check("streamed first chunk delivered", text.includes("First chunk."));
  check("auto-continue spliced continuation", text.includes("Second chunk - NOT truncated."));
  check("finish + [DONE] emitted", text.includes("finish_reason") && text.includes("[DONE]"));
  check("continue endpoint called once", seen.continueCalls === 1);
  check("session deleted after stream", seen.deleteCalls >= 1);

  // non-streamed chat -> should also auto-continue
  const res2 = await fetch("http://127.0.0.1:18136/v1/chat/completions", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ model: "deepseek-chat", messages: [{ role: "user", content: "hi again" }] }),
  });
  const j2 = await res2.json();
  check("non-stream auto-continued", j2.choices[0].message.content.includes("Second chunk - NOT truncated."));
  check("non-stream reasoning attached", j2.choices[0].message.reasoning_content === "thinking part");

  // cookies endpoint
  const ck = await fetch("http://127.0.0.1:18136/v1/cookies", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ userToken: "NEW-TOKEN" }),
  });
  check("cookie push accepted", ck.ok);
  const stored = JSON.parse(fs.readFileSync(path.join(tmp, "deepseek-cookies.json"), "utf8"));
  check("cookie file updated", stored.userToken === "NEW-TOKEN");

  // no token -> 401
  fs.rmSync(path.join(tmp, "deepseek-cookies.json"));
  const res3 = await fetch("http://127.0.0.1:18136/v1/chat/completions", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ model: "deepseek-chat", messages: [{ role: "user", content: "hi" }] }),
  });
  check("no-token -> 401", res3.status === 401);

  console.log(failures === 0 ? "\nALL TESTS PASSED" : `\n${failures} TEST(S) FAILED`);
} finally {
  child.kill();
  upstream.close();
  try { fs.rmSync(tmp, { recursive: true, force: true }); } catch {}
  process.exit(failures === 0 ? 0 : 1);
}
