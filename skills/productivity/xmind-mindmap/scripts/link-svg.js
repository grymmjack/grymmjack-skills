#!/usr/bin/env node
/**
 * link-svg.js — make a Mermaid-rendered mind-map SVG's nodes clickable.
 *
 * Mermaid's `mindmap` renderer emits no hyperlinks, so a rendered .svg loses the
 * per-node `url`s carried in the topic tree. This post-processor reads the tree
 * (the source of truth), builds a label→url map, and wraps every matching node
 * group (`<g class="node mindmap-node …">`) in an SVG `<a>` so it opens the URL
 * in a new tab. Runs in place; safe to re-run (skips already-wrapped nodes).
 *
 * Usage:
 *   node link-svg.js --tree topic.json --svg map.svg [--out map.svg]
 *
 * Label matching mirrors the generator's Mermaid sanitizer (strip ()[]{},
 * collapse whitespace) and decodes the HTML entities Mermaid writes into the
 * SVG, so titles containing &, <, > etc. still match.
 */

const fs = require('fs');

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i++) {
    const next = () => argv[++i];
    switch (argv[i]) {
      case '--tree': args.tree = next(); break;
      case '--svg': args.svg = next(); break;
      case '--out': args.out = next(); break;
      case '-h': case '--help': args.help = true; break;
      default: throw new Error(`Unknown argument: ${argv[i]}`);
    }
  }
  return args;
}

const USAGE = 'Usage: node link-svg.js --tree topic.json --svg map.svg [--out map.svg]';

// Same normalization the generator applies when emitting the Mermaid label.
function normalize(s) {
  return String(s).replace(/[()\[\]{}]/g, '').replace(/\s+/g, ' ').trim();
}

function decodeEntities(s) {
  return String(s)
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"').replace(/&#39;/g, "'")
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)))
    .replace(/&amp;/g, '&'); // last, so &amp;lt; → &lt; not <
}

function nodeUrl(node) {
  const u = node.url || node.href || node.link;
  return (typeof u === 'string' && u.trim()) ? u.trim() : null;
}

// Build normalized-label → url. Records collisions (same label, different urls)
// so we can skip them rather than link ambiguously.
function buildLinkMap(root) {
  const map = new Map();
  const ambiguous = new Set();
  const walk = (nodes) => {
    for (const n of nodes || []) {
      const url = nodeUrl(n);
      if (url) {
        const key = normalize(n.title);
        if (map.has(key) && map.get(key) !== url) ambiguous.add(key);
        else map.set(key, url);
      }
      if (n.children) walk(n.children);
    }
  };
  const top = Array.isArray(root) ? root : (root.children || root.tree || []);
  walk(top);
  for (const k of ambiguous) map.delete(k);
  return { map, ambiguous };
}

// Extract the visible label text from a node group's substring.
function labelOf(groupHtml) {
  const m = groupHtml.match(/<span class="nodeLabel[^"]*">([\s\S]*?)<\/span>/);
  if (!m) return null;
  const text = m[1].replace(/<[^>]+>/g, ''); // strip inner <p>, etc.
  return normalize(decodeEntities(text));
}

// From the '<' that opens a node group, return the index just past its matching
// </g>, balancing nested <g> (the label lives in a child <g>).
function groupEnd(svg, openLt) {
  const openTagEnd = svg.indexOf('>', openLt) + 1;
  const re = /<g[\s>]|<\/g>/g;
  re.lastIndex = openTagEnd;
  let depth = 1, m;
  while ((m = re.exec(svg))) {
    depth += m[0] === '</g>' ? -1 : 1;
    if (depth === 0) return m.index + m[0].length;
  }
  return -1;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help || !args.tree || !args.svg) {
    console.log(USAGE);
    process.exit(args.help ? 0 : 1);
  }

  const tree = JSON.parse(fs.readFileSync(args.tree, 'utf8'));
  const { map } = buildLinkMap(tree);
  let svg = fs.readFileSync(args.svg, 'utf8');

  // Collect (start, end, url) for every node group with a known label.
  const marker = '<g class="node mindmap-node';
  const ranges = [];
  let matched = 0;
  for (let i = svg.indexOf(marker); i !== -1; i = svg.indexOf(marker, i + 1)) {
    // Skip if already wrapped by a prior run: preceding non-space char is '>' of an <a>.
    const before = svg.lastIndexOf('<a ', i);
    const end = groupEnd(svg, i);
    if (end === -1) continue;
    const label = labelOf(svg.slice(i, end));
    if (!label || !map.has(label)) continue;
    if (before !== -1 && svg.slice(before, i).match(/^<a [^>]*>\s*$/)) continue; // already linked
    ranges.push({ start: i, end, url: map.get(label) });
    matched++;
  }

  // Splice from the end so earlier indices stay valid.
  ranges.sort((a, b) => b.start - a.start);
  for (const r of ranges) {
    const group = svg.slice(r.start, r.end);
    const esc = r.url.replace(/&/g, '&amp;').replace(/"/g, '&quot;');
    const open = `<a xlink:href="${esc}" href="${esc}" target="_blank" rel="noopener noreferrer" class="mm-link">`;
    svg = svg.slice(0, r.start) + open + group + '</a>' + svg.slice(r.end);
  }

  // A little affordance: linked nodes get a pointer cursor + underline on hover.
  if (matched && !svg.includes('.mm-link')) {
    svg = svg.replace(/<style>/, '<style>a.mm-link{cursor:pointer;}a.mm-link:hover .nodeLabel{text-decoration:underline;}');
  }

  fs.writeFileSync(args.out || args.svg, svg);
  console.log(`linked ${matched} node(s) in ${args.out || args.svg}  (${map.size} url labels in tree)`);
}

try { main(); } catch (e) { console.error('ERROR: ' + e.message); process.exit(1); }
