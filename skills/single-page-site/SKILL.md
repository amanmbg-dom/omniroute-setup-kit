---
name: single-page-site
description: Builds an "Ultimate Single Pager" — one self-contained HTML file (all CSS/JS inline, zero external libraries/fonts/embeds) with full local-SEO (title/meta/OG/Twitter/JSON-LD), AI-generated images through the local Google Flow engine, and the MBG Card copyright footer. Images are generated in the background while the page is built, then wired in as HOSTED LINKS (client hosting, a provided base URL, or an auto-uploaded free host). You give ONLY the client's business information; the skill writes the entire site structure, copy, and SEO blueprint itself. Use when the user asks for a single-page site, landing page, one-file website, business website, one-pager, pure HTML page, or any site that must be a single .html file with no external libraries, fonts, CDNs, embeds, or build step.
---

# Ultimate Single-Pager Studio (Zero-Dependency + AI Images + Local SEO)

## Mission

One short prompt (just the client's business info) → **ONE `.html` file** that is a genuine piece of art: premium, unique, authentic, mobile-first, with the full local-SEO stack baked in, all CSS/JS inline, zero external libraries/fonts/embeds — and images generated in the background **in parallel** with the build, then wired in as **HOSTED LINKS** (never local files, never data URIs). The HTML renders from a double-click; the images come from wherever they're hosted (client's folder, a provided base URL, or an auto-uploaded free host).

The skill does the thinking: you never write the site structure, the copy, the SEO, or the design brief. You supply only what only you know — the client's business facts.

## Workflow at a glance

1. **Phase 1 — Intake:** collect ONLY the client's business information (one compact list).
2. **Phase 2 — Content + SEO engine:** the skill writes the full 8-section outline, every word of copy (1,500+ words), the primary keyword, and the complete head/JSON-LD SEO blueprint.
3. **Phase 3 — Build:** design direction from the reference sites + competitor research, AI images via the `generate_image` MCP tool with a fixed prompt discipline, hand-coded HTML/CSS/JS, then the mandatory SEO self-check and delivery.

---

## Phase 1 — Client intake (the ONLY thing you ask the user)

If the user's prompt already contains these, use them. Otherwise ask for the essentials in ONE compact list — never interrogate, never repeat:

1. **Business name** (and logo file if they have one)
2. **Industry / business type** — e.g. café, jeweller, tuition centre, automobile dealer
3. **City** + the localities/areas they serve (service areas)
4. **What they do** — one sentence
5. **Products / services to feature** — names, one line each
6. **Contact** — phone, email, address, WhatsApp, socials (whatever exists)
7. **Anything that must appear** — tagline, offers, pricing, specific colours, things to avoid
8. **Image hosting** — does the client have hosting/a domain for images? If yes, the base URL (e.g. `https://client.com/images/`). If no: default to auto-hosting (free direct links via catbox) or the `images/` folder they upload to their host. The user may also just say "you decide".

If the user says "you decide" or leaves a field blank, fill it with judgment and note it in the summary. Never invent contact details that will embarrass them — use real ones; if unknown, use tasteful placeholders they can swap.

**Do NOT ask** for the site structure, the sections, the copy, the SEO, or the design. That is the skill's job — that's the point of the workflow.

---

## Phase 2 — Content & SEO engine (skill writes this, never asks)

### 2.1 Primary keyword

Derive ONE primary keyword: `<core service> in <City>` — e.g. "home tuition in Jaipur", "café in Chakala", "gold jewellery in Alwar", "bike service in Dehradun". Pick the single most valuable search phrase for this business. Everything below hangs off it.

### 2.2 The 8-section outline — write real copy for each

1. **Home (hero)** — brand name (loudest text), one-line promise, primary CTA (call / WhatsApp / visit), one dominant visual
2. **About Us** — the story, the people, the place; specific and human, not generic
3. **Services** — every product/service the client listed, each with a real description
4. **Why Choose Us** — 4–6 concrete differentiators (experience, quality, price, service, warranty, local presence)
5. **FAQ** — 6–8 real questions customers actually ask, each with a genuine answer (this section MUST exist and match the FAQPage JSON-LD)
6. **Testimonials** — 3–5 believable reviews with names; use realistic local names (never "John Doe"), no invented URLs, no star-count inflation
7. **Gallery** — 6–8 images (AI-generated or client photos)
8. **Map & Contact** — a **hand-drawn inline SVG map / directions card** (NO iframe, NO Google Maps embed — zero-dependency rule) plus full contact block and a contact form stub if appropriate

Plus a **Service Areas** band (local-SEO signal): the localities list — folded into "Why Choose Us" or its own strip.

### 2.3 Copy rules

- **1,500+ words minimum** across the page — thin pages don't rank. Write specific, local copy.
- **Keyword discipline:** repeat the exact primary keyword phrase throughout; put it in **≥ 2 H2/H3 headings**; aim for **≥ 1.5% keyword density**; name the **city repeatedly** in the copy.
- No lorem ipsum, no filler, no clichés ("elevate", "seamless", "unleash", "next-gen"). Write like a good local business talks.
- One copy register across the page — consistent voice.

### 2.4 SEO blueprint (baked into the `<head>`)

| Item | Requirement (exact) |
|---|---|
| **Title** | `Best <primary keyword> | <Brand>` — keyword-first (e.g. `Best Home Tuition in Jaipur | Shiksha Tutors`) |
| **Meta description** | 50–320 chars, the keyword in the first 160 |
| **Robots** | `<meta name="robots" content="index, follow, max-snippet:-1, max-image-preview:large, max-video-preview:-1">` — verbatim |
| **Canonical** | `<link rel="canonical" href="https://<client-domain>/">` (use the real domain if provided, else a placeholder `.in` domain they can swap) |
| **Open Graph** | ≥ 6 tags: `og:title`, `og:description`, `og:type`, `og:url`, `og:locale`, `og:site_name` (+ `og:image` as a data URI or generated image) |
| **Twitter card** | `twitter:card` = `summary_large_image`, `twitter:title`, `twitter:description`, `twitter:image` |
| **H1** | EXACTLY one, mirroring the title: `Best <keyword> in <City>` (not a slogan) |
| **JSON-LD Business** | correct `@type` for the industry (LocalBusiness, Restaurant, JewelryStore, AutoRepair, HomeAndConstructionBusiness, …) with name, address, geo, phone, hours, image, url |
| **JSON-LD FAQPage** | must match the on-page FAQ verbatim |
| **JSON-LD BreadcrumbList** | 2–3 items (Home → Services) |
| **Images** | every `<img>`: descriptive `alt`, explicit `width`/`height`, `loading="lazy"` (except hero) |

### 2.5 Image plan

Before building, assign each visual slot an aspect from the ratio table (§3.3) and a one-line art direction (subject + setting + palette, filled into the prompt template). This becomes the `site-images.json` spec the background pipeline runs (§3.3).

---

## Phase 3 — Build

### 3.1 Design direction (premium, unique, authentic — the "Ultimate Single Pager" bar)

Follow the `frontend-design` skill's principles: one signature element the page is remembered by, one accent color, max two typefaces (system stacks), editorial spacing, strong type hierarchy, real imagery, restrained motion (a load sequence, scroll reveals, hover micro-interactions). The business name is the loudest text in the hero.

**Reference sites — study them when online, then design ORIGINAL, not copies:**
- https://wellnesssupermarket.in/
- https://blackbullcafechakala.com/
- https://aravalijewellers.com/
- https://mahadevautomobiles.com/
- https://arnikacollection.in/
- https://valoraappliance.com/

Extract what makes them work: photography-led heroes, editorial type, authentic local copy, one confident brand colour, real products in frame, calm whitespace. Then make something that stands beside them, not behind them.

**Competitor research:** when online, find 3–5 direct competitors of the client, note the winning pattern in each (hero, proof, layout, tone), and deliberately design **better** on at least three of those dimensions. When offline, skip gracefully — never block the build.

**Anti-slop rules (hard):** no AI-purple gradients or generic SaaS card grids; no beige-cream + serif + terracotta default unless the brand genuinely is that; no near-black + acid accent default; no glossy glassmorphism everywhere; no em-dashes in copy; no "Trusted by / 100+ happy customers" fake-proof strips unless real; no fake-precision numbers; no generic names. If a choice reads like what any AI would do for any business, change it.

### 3.2 Hard constraints (non-negotiable)

- Exactly ONE `.html` file. No separate `.css` or `.js` files, no build step.
- **Images are HOSTED and referenced by URL** — never data URIs, never local folder paths in the final file (that's the client's workflow). The URLs come from the `images/` folder convention, a provided base URL, or an auto-uploaded free host (§3.3).
- Everything else is zero-external: **no external JS libraries, no Google Fonts, no CDNs, no iframes, no favicon fetches.**
- **No external links or embeds:** no Google Maps iframe (draw the map as inline SVG), no YouTube embeds, no outbound `<a href>` to other sites. Contact links (`tel:`, `mailto:`, `https://wa.me/`) are the only allowed anchors. JSON-LD `url`/`sameAs` metadata is fine — it's metadata, not an embed.
- Fonts from system font stacks only. Inline `<svg>` is allowed for icons, the logo mark, and the map.
- **Deliverable = the `.html` file + an `images/` folder** (the files the URLs point at) + `images-manifest.json` (which URL goes where).
- Responsive (mobile-first), semantic HTML, valid CSS, keyboard-accessible, visible focus, `prefers-reduced-motion` respected.
- **Footer — exact line** (compute the year with one inline JS line, e.g. `<span id="yr"></span>` set to `new Date().getFullYear()`):
  `© Copyright {current year} | All Rights Reserved | Powered by MBG Card Pvt. Ltd.`

### 3.3 Images — background pipeline + HOSTED links (this is the workflow)

The image engine, model (Nano Banana 2), and ratio mapping are FIXED (same bridge, same Chrome session), so quality is identical no matter who runs it. The skill's prompt discipline controls the rest. **Images are generated IN PARALLEL with the build** and wired in as hosted URLs afterwards — never data URIs, never local paths in the final file.

#### 3.3.1 Kick off the background pipeline (do this FIRST, before writing any HTML)

1. Write `site-images.json` next to your working files:
```json
{
  "slots": [
    { "key": "hero",  "prompt": "<template-filled>", "size": "1792x1024" },
    { "key": "about", "prompt": "<template-filled>", "size": "1024x1024" },
    { "key": "gallery-1", "prompt": "<template-filled>", "size": "1024x1024" }
  ]
}
```
2. Start the pipeline DETACHED so it keeps running while you build (the script is `site-images.mjs`, shipped next to this SKILL.md):
```
# real links immediately (auto-uploads each image to catbox.moe — free, anonymous, direct hotlink URLs)
powershell -NoProfile -Command "Start-Process -FilePath node -ArgumentList 'site-images.mjs','site-images.json','--out','images','--upload' -WindowStyle Hidden"

# OR the client has hosting: bake their base URL in (no upload needed)
powershell -NoProfile -Command "Start-Process -FilePath node -ArgumentList 'site-images.mjs','site-images.json','--out','images','--base-url','https://client.com/images/' -WindowStyle Hidden"

# OR plain folder mode: URLs stay /images/<key>-1.jpg and the client uploads the folder
powershell -NoProfile -Command "Start-Process -FilePath node -ArgumentList 'site-images.mjs','site-images.json','--out','images' -WindowStyle Hidden"
```
The pipeline: generates each slot through the bridge (one job ≈ 4 candidates), saves them to `images/`, optionally uploads, and rewrites **`images/images-manifest.json` after every slot** (`{done, slots: {key: {status, file, url}}}`). The bridge serializes generations (one Chrome tab), so the pipeline runs them back-to-back — that's fine, it's in the background.

#### 3.3.2 Build the site while the images generate (parallel)

Write the full HTML/CSS/copy (§2.3, §3.1, §3.2) **while Chrome churns through the slots**. When the page structure is done, read `images/images-manifest.json`:
- **Done** (`done: true`) → wire every `slots[key].url` into the matching `<img src>`.
- **Not done** → poll: `sleep` in 20–30s steps (each slot ≈ 30–60s) and re-read until done.
- **Slot error** (`status: "error"`) → hand-craft an inline SVG in the page palette for that slot and note it in the summary.
- If `url` is a relative `/images/<key>-1.jpg` path, that's the folder mode — the images/ folder ships with the page.

#### 3.3.3 Standardized prompt template (fill in, keep the structure)
```
Professional {photography|editorial} photograph of {SUBJECT}.
{SETTING — where/when, mood}. {COMPOSITION — e.g. subject right, clean negative space left}.
{Lighting: soft window light / warm golden hour / moody studio}.
Colour palette: {PALETTE tied to the site's accent + neutrals}.
Premium commercial quality, high detail, shallow depth of field. No text, no watermarks, no logos.
```

**Aspect per use case** (pass as `size`):

| Use case | size | Flow ratio |
|---|---|---|
| Hero / wide band | `1792x1024` | 16:9 |
| Landscape section image | `1536x1024` | 4:3 |
| Square (gallery, about, product) | `1024x1024` | 1:1 |
| Portrait (product, mobile-first cards) | `1024x1536` | 3:4 |
| Tall (hero on mobile, stories) | `1024x1792` | 9:16 |

#### 3.3.4 On-demand single image (one-off, not the full site)

For a single image (logo variant, social post, ad) use the `generate_image` MCP tool (`flowui` server) — same engine, same template, same quality — and it returns a viewable image block plus a saved file. The pipeline is for full-site batches.

#### 3.3.5 If the bridge is unavailable

Fallback order if `flowui/*` fails: `gflow/nano-banana-2` (session-token bridge, hits Google's daily quota), `antigravity/gemini-3.1-flash-image` (needs Antigravity OAuth + projectId), `lmarena/qwen-image-2.0` (needs a fresh arena.ai session + reCAPTCHA). If ALL image paths fail: **Mode A fallback** — hand-crafted inline SVG art in the page palette, and state in the summary that AI generation was unavailable and why. **Bridge sign-in / down errors:** "needs a one-time sign-in" → run `bridge\flow-browser\re-sign-in.cmd` and sign in, then retry. "Connection refused" → `bridge\flow-browser\start-flow-browser.cmd`.

### 3.4 Mandatory self-check before delivery (the SEO audit)

Run EVERY row before handing over — this is the client's audit, baked in:

**Head & Meta**
- [ ] Title = `Best <keyword> in <City> | <Brand>` (keyword-first)
- [ ] Meta description present, 50–320 chars, keyword in first 160
- [ ] Robots tag verbatim: `index, follow, max-snippet:-1, max-image-preview:large, max-video-preview:-1`
- [ ] Canonical link present
- [ ] Open Graph ≥ 6 tags (title, description, type, url, locale, site_name + image)
- [ ] Twitter card tags (card, title, description, image)

**Headings & Structure**
- [ ] Exactly one `<h1>`
- [ ] `<h1>` mirrors the title (`Best <keyword> in <City>`)

**Schema (JSON-LD)**
- [ ] Business block with the correct `@type` (LocalBusiness, Restaurant, …)
- [ ] FAQPage JSON-LD + matching on-page FAQ section
- [ ] BreadcrumbList JSON-LD

**Images**
- [ ] Every image hosted + referenced by URL (client folder, provided base URL, or catbox link) — never a data URI, never a local path
- [ ] Every image: descriptive alt, width/height attrs, lazy loading (hero excepted)

**Content & Keyword**
- [ ] 1,500+ words, specific local copy
- [ ] Service-areas section listing the localities served
- [ ] Focused, repeated target keyword (≥ 1.5% density)
- [ ] Keyword used in ≥ 2 H2/H3 headings
- [ ] City/location named repeatedly in the copy

**Zero-dependency & footer**
- [ ] No external links, no embeds, no iframes, no CDN JS, no external fonts — images may be hosted URLs (that's the workflow by design)
- [ ] `images/` folder + `images-manifest.json` delivered alongside, URLs match the manifest
- [ ] Footer exact line with live year: `© Copyright {year} | All Rights Reserved | Powered by MBG Card Pvt. Ltd.`

### 3.5 Delivery

Hand over:
1. The complete `.html` file (saved to a sensible location, named `<business>-<city>-single-page.html`)
2. The **`images/` folder** (the files behind the URLs) + `images-manifest.json`
3. **Hosting instructions** — where each URL points and how to get the images live: upload the `images/` folder to the client host (folder mode), or the links are already live (catbox / base-URL mode)
4. A one-paragraph summary: what was built, the primary keyword used, which image path (pipeline / MCP / SVG fallback), the hosting mode, and how to regenerate images
5. A mini SEO scorecard — the checklist above with passes highlighted (so the client sees the audit is green before they even run it)

---

## One-shot behavior

Given a thin prompt: run Phase 1 intake once (only the compact list), then Phase 2 + 3 immediately with judgment for anything left blank. In Phase 3, start the background image pipeline (§3.3.1) BEFORE writing HTML, build the site in parallel, integrate the manifest URLs, then deliver the file + images/ folder + hosting instructions + summary + scorecard in one turn.
