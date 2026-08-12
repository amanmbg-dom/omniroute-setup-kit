---
description: Generate the full site's image batch in the background (anonymous hosting) and report the hosted URLs
---

Generate the image batch for the current single-page site using the background pipeline, then report the hosted links.

1. **Spec.** If `site-images.json` is not next to the working files, build it: one `slot` per image the site needs, each with a `key`, a `prompt` filled from the standardized art-direction template (subject / setting / composition / lighting / palette tied to the site's accent), and the right `size` per use case: `1792x1024` hero/wide, `1536x1024` landscape, `1024x1024` square, `1024x1536` portrait, `1024x1792` tall. Use real prompts derived from the site being built — never placeholders.

2. **Launch detached** (anonymous hosting — catbox auto-upload, no account, no client URLs):
   ```
   powershell -NoProfile -Command "Start-Process -FilePath node -ArgumentList 'site-images.mjs','site-images.json','--out','images','--upload' -WindowStyle Hidden"
   ```
   The pipeline script is `site-images.mjs` in the `single-page-site` skill folder (`~/.claude/skills/single-page-site/site-images.mjs`). Run it from the folder containing your spec, or pass the full script path as the first argument. If the bridge is down the script starts it; if it reports a sign-in is needed, tell the user to run `bridge\flow-browser\re-sign-in.cmd`.

3. **Wait and integrate.** Poll `images/images-manifest.json` every 20–30 seconds (each slot takes ~30–60s) until `done: true`. If the site page already exists, wire each `slots[key].url` into the matching `<img src>` (match by `data-slot`), scan for leftover empty srcs, and finish.

4. **Report.** Summarize: manifest path, per-slot status (`ok`/`error`), and every hosted URL. Flag any error slots and what was done about them (SVG fallback / retry).
