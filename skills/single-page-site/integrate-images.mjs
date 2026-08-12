#!/usr/bin/env node
// integrate-images.mjs — wires hosted image URLs from images-manifest.json into
// the built single-page site (the "auto-add images" step of the skill).
//
// The agent writes the page with placeholders while images generate:
//   <img src="" data-slot="hero" alt="...">
// Then this script fills every placeholder from the manifest and removes the
// data-slot markers:
//   <img src="https://files.catbox.moe/abc123.jpg" alt="...">
//
// Usage:
//   node integrate-images.mjs page.html images/images-manifest.json [--out final.html]
//     (default: rewrite page.html in place)
//
// Exit code:
//   0  all image placeholders resolved
//   1  some placeholders could not be resolved (see report — agent handles them,
//      e.g. with an inline SVG fallback)

import fs from 'node:fs';

function usage() {
  console.error('usage: node integrate-images.mjs page.html images/images-manifest.json [--out final.html]');
  process.exit(2);
}

const [htmlPath, manifestPath] = process.argv.slice(2);
if (!htmlPath || !manifestPath) usage();

let outPath = htmlPath;
const outIdx = process.argv.indexOf('--out');
if (outIdx > -1) outPath = process.argv[outIdx + 1];

const html = fs.readFileSync(htmlPath, 'utf8');
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const slots = manifest.slots || {};

const IMG_RE = /<img\b[^>]*>/gi;
const ATTR = (tag, name) => {
  const m = tag.match(new RegExp(`\\s${name}=["']([^"']*)["']`, 'i'));
  return m ? m[1] : null;
};

let resolved = 0;
const unresolved = [];

const out = html.replace(IMG_RE, tag => {
  const slot = ATTR(tag, 'data-slot');
  const src = ATTR(tag, 'src') || '';
  if (!slot) return tag; // not a pipeline placeholder

  const entry = slots[slot];
  if (entry && entry.status === 'ok' && entry.url) {
    resolved++;
    return tag
      .replace(/\s+data-slot=["'][^"']*["']/i, '')
      .replace(/\ssrc=["'][^"']*["']/i, ` src="${entry.url}"`);
  }
  unresolved.push({ slot, reason: entry ? entry.error || `status: ${entry.status}` : 'slot missing from manifest' });
  return tag;
});

fs.writeFileSync(outPath, out, 'utf8');

console.log(`integrated ${resolved} image(s) from ${manifestPath}`);
if (unresolved.length > 0) {
  console.log('UNRESOLVED:');
  for (const u of unresolved) console.log(`  - ${u.slot}: ${u.reason}`);
  process.exit(1);
}
console.log(`no empty image srcs remain in ${outPath}`);
