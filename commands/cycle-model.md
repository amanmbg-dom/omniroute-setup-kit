---
description: Cycle the Claude Code model through your free pool — reliable → best-coding → best-fast — and show how to apply it to this session
argument-hint: [reliable | coding | fast]
---

Cycle the model for the user.

1. **Run the cycle script** (pick the first path that exists):
   - `powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.omniroute\cycle-model.ps1"` — plus `-To <slot>` if the user passed an argument (reliable | coding | fast).
   - Fallback if that file is missing: look for `cycle-model.ps1` next to this kit (`~\omniroute-setup-kit\cycle-model.ps1`) and run it there.

2. **Read the script output.** It printed:
   - the previous model,
   - the new default model (written to `~/.claude/settings.json` → `env.ANTHROPIC_MODEL`),
   - the exact `/model` value to apply **right now**.

3. **Tell the user, in order:**
   - The new default model and what it's good for:
     - `auto/coding:reliable` — health-scored coding, auto-falls back off dead providers (default)
     - `auto/best-coding` — best coding model available across all providers
     - `auto/best-fast` — latency-first, for quick edits and simple tasks
   - That it now applies to **new** sessions/conversations.
   - To apply to **this** session: run `/model` and pick the printed value (one keystroke).
   - If they pass an argument next time (e.g. `/cycle-model fast`), it jumps straight there.

Keep the reply to a few lines — this is a quick switch, not a report.
