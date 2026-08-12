---
description: Switch to the fastest models for simple tasks — no thinking, no dead-model waits. Use for quick edits, short answers, or anything that "takes too long".
argument-hint: [task description]
---

You are now in **FAST MODE** — the user wants speed, not deliberation.

**Before doing anything, apply these speed settings:**

1. **Model** — this session is running on the fast track. If you have a way to select the model (e.g. the `claude` CLI's `/model` command or the extension's model picker), switch to:
   - Main: `auto/best-fast` (latency-first routing — never waits on dead NIM models)
   - If `auto/best-fast` is unavailable, use `auto/coding:fast`, then `auto/coding:reliable` as fallback.
2. **Behavior rules:**
   - Answer directly. No preamble, no "sure, here's how", no summarizing what you did unless asked.
   - Make the fewest edits that satisfy the request. Do not refactor, do not "improve" unrelated code.
   - Skip optional verification steps (no full typecheck/build/test runs unless the change could break something).
   - No parallel agent spawning, no elaborate multi-step plans.
   - If the task is a question, answer it in 2-4 sentences max.
3. **If a request fails with a dead/provider error (400/429/503/timeout):** do NOT retry the same model. Immediately re-issue the request or tell the user to retry — the gateway's auto-routing will pick a healthy model.

This mode ends when the user asks a non-trivial question or gives a large task — then return to normal operation.
