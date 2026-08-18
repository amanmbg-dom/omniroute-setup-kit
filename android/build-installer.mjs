#!/usr/bin/env node
// build-installer.mjs — regenerate the embedded payload inside
// install-omniroute.sh so fresh installs carry the CURRENT scripts/bridges.
//
// The installer self-contains a base64 tar.gz (PAYLOAD_B64) of the files the
// phone needs: the android launcher scripts + the bridges + the Cookie Pusher
// extension. Edit a file, then run:
//   node android/build-installer.mjs
// and re-serve android/ (serve-installer.cmd) to the phone.
//
// Payload layout (relative to the tar root, matching the original build):
//   start-omniroute.sh boot.sh fix-model-cache.sh import-transfer.sh   (from android/)
//   bridge/ extension/                                                 (from kit root)
// The installer itself, serve/build/transfer helpers and setup-termux.sh
// are NOT part of the payload.
import { readFileSync, writeFileSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

// GNU tar (git-bash) wants POSIX paths; Windows drive paths look like remote
// hosts to it ("Cannot connect to C:"). Convert C:\x -> /c/x and run via bash.
const posix = (p) => p.replace(/\\/g, "/").replace(/^([A-Za-z]):/, "/$1");

const ANDROID = dirname(fileURLToPath(import.meta.url)); // .../omniroute-setup-kit/android
const ROOT = dirname(ANDROID); // .../omniroute-setup-kit
const INSTALLER = join(ANDROID, "install-omniroute.sh");

const FROM_ANDROID = ["start-omniroute.sh", "boot.sh", "fix-model-cache.sh", "import-transfer.sh"];
const FROM_ROOT = ["bridge", "extension"];

const stage = mkdtempSync(join(tmpdir(), "omniroute-installer-"));
try {
  const tgz = join(stage, "payload.tgz");
  // tar -C android <scripts> -C root bridge extension
  let cmd = `tar czf "${posix(tgz)}"`;
  for (const p of FROM_ANDROID) cmd += ` -C "${posix(ANDROID)}" ${p}`;
  cmd += ` -C "${posix(ROOT)}"`;
  for (const p of FROM_ROOT) cmd += ` ${p}`;
  execFileSync("bash", ["-c", cmd]);
  const b64 = readFileSync(tgz).toString("base64");
  const installer = readFileSync(INSTALLER, "utf8");
  if (!/PAYLOAD_B64="[A-Za-z0-9+/=]+"/.test(installer)) {
    console.error("PAYLOAD_B64 anchor not found in install-omniroute.sh - aborting");
    process.exit(1);
  }
  const updated = installer.replace(/PAYLOAD_B64="[A-Za-z0-9+/=]+"/, `PAYLOAD_B64="${b64}"`);
  writeFileSync(INSTALLER, updated);
  console.log(`install-omniroute.sh rebuilt: payload ${(b64.length / 1024).toFixed(0)} KB base64`);
} finally {
  rmSync(stage, { recursive: true, force: true });
}
