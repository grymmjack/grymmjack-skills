#!/usr/bin/env node
/**
 * generate-xmind.js — turn a hierarchical topic tree into a real .xmind file.
 *
 * Prior art: DRAW's DEV/generate-draw-mindmap.js and the `create-xmind` skill
 *   https://github.com/grymmjack/DRAW/blob/main/DEV/XMIND-GENERATOR.md
 *
 * Reads a JSON topic tree and writes:
 *   <name>.xmind   — the real XMind file (single- or multi-sheet)
 *   <name>.mmd     — a Mermaid `mindmap` twin (for render.sh → svg/png/pdf)
 *   <name>.md      — a nested-bullet outline twin (for markmap, or plain reading)
 *
 * Usage:
 *   node generate-xmind.js --tree topic.json [options]
 *
 * Options:
 *   --tree  <path>    JSON tree file (required). See reference/tree-format.md.
 *   --out   <dir>     Output directory (default: current directory).
 *   --name  <base>    Output basename, no extension (default: slug of the title).
 *   --title <str>     Central topic title (overrides the tree's own title).
 *   --theme <name>    snowbrush | robust | business (default: snowbrush).
 *   --layout <mode>   single | multi | auto (default: auto).
 *                     auto → multi when there is more than one top-level branch,
 *                     otherwise single.
 *   --no-companions   Skip the .mmd and .md twins; write only the .xmind.
 */

const fs = require('fs');
const path = require('path');
const { Workbook, Topic, Zipper } = require('xmind');
const { Theme } = require(require.resolve('xmind/dist/core/theme'));

// ---------- args ----------
function parseArgs(argv) {
  // NB: do not pre-default `theme`/`layout` here — a truthy default would shadow
  // the tree's own `theme`/`layout` in the `args.x || meta.x || fallback` chains
  // below (silently ignoring root-level tree settings). The fallbacks there
  // supply the defaults instead, so a CLI flag still wins over the tree.
  const args = { out: '.', companions: true };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const next = () => argv[++i];
    switch (a) {
      case '--tree': args.tree = next(); break;
      case '--out': args.out = next(); break;
      case '--name': args.name = next(); break;
      case '--title': args.title = next(); break;
      case '--theme': args.theme = next(); break;
      case '--layout': args.layout = next(); break;
      case '--no-companions': args.companions = false; break;
      case '-h': case '--help': args.help = true; break;
      default: throw new Error(`Unknown argument: ${a}`);
    }
  }
  return args;
}

const USAGE = `Usage: node generate-xmind.js --tree topic.json [--out dir] [--name base]
       [--title "Central Topic"] [--theme snowbrush|robust|business]
       [--layout single|multi|auto] [--no-companions]`;

// ---------- tree loading / normalization ----------
function slugify(s) {
  return String(s).toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, '-')
    .replace(/^-+|-+$/g, '') || 'mindmap';
}

function normalizeTree(raw, cliTitle) {
  let root;
  if (Array.isArray(raw)) {
    root = { title: cliTitle || 'Mind Map', children: raw };
  } else if (raw && typeof raw === 'object') {
    // Accept { title, children } or a wrapper { title, theme, layout, tree|children }
    const children = raw.children || raw.tree || [];
    root = { title: cliTitle || raw.title || 'Mind Map', children };
  } else {
    throw new Error('Tree must be a JSON array of nodes or an object with a `children` array.');
  }
  if (!Array.isArray(root.children)) root.children = [];
  return { root, meta: (raw && !Array.isArray(raw)) ? raw : {} };
}

function countNodes(node) {
  let n = 1;
  for (const c of node.children || []) n += countNodes(c);
  return n;
}

// ---------- xmind building ----------
// A node may carry a `url` (alias `href`/`link`) → attach it as a topic hyperlink.
function nodeUrl(node) {
  const u = node.url || node.href || node.link;
  return (typeof u === 'string' && u.trim()) ? u.trim() : null;
}

// ----- per-node styling -----
// The high-level SDK exposes no style setter, so styles are collected here keyed
// by the topic's uuid and patched into content.json after save (see applyStyles).
// "Terminal" look for CLI-command nodes: black fill, green monospace text.
const TERMINAL_STYLE = {
  'svg:fill': '#000000',
  'fo:color': '#33FF33',
  'fo:font-family': 'Menlo',
};

// Map a node's convenience flags (cli/bold/italic) + raw `style` override to a
// flat XMind style-properties object, or null when the node needs no styling.
function styleFor(node) {
  let p = null;
  if (node.cli) p = Object.assign({}, TERMINAL_STYLE);
  if (node.bold) { p = p || {}; p['fo:font-weight'] = 'bold'; }
  if (node.italic) { p = p || {}; p['fo:font-style'] = 'italic'; }
  if (node.style && typeof node.style === 'object' && !Array.isArray(node.style)) {
    p = p || {}; Object.assign(p, node.style);   // explicit override wins
  }
  return p && Object.keys(p).length ? p : null;
}

// Decorate a title for the Markdown outline twin so cli/bold/italic survive there too.
function decorateLabel(node) {
  let t = String(node.title);
  if (node.cli) t = '`' + t + '`';
  if (node.bold) t = '**' + t + '**';
  if (node.italic) t = '*' + t + '*';
  return t;
}

// ----- per-node images -----
// A node may carry `image: "path.png"` → embedded on the topic. The path is
// pre-resolved to an absolute path against the tree-file dir (see resolveImages).
function nodeImage(node) {
  return (typeof node.__imageAbs === 'string' && node.__imageAbs) ? node.__imageAbs : null;
}

// Combined per-node patch (style and/or image), collected by uuid and applied to
// content.json after save. Returns null when the node needs neither.
function patchFor(node) {
  const style = styleFor(node);
  const image = nodeImage(node);
  if (!style && !image) return null;
  const p = {};
  if (style) p.style = style;
  if (image) p.image = image;
  return p;
}

// Walk the tree and resolve every `image` to an absolute path against baseDir,
// stashing it on `__imageAbs`. Warns (and drops) images that don't exist.
function resolveImages(node, baseDir) {
  if (node && typeof node.image === 'string' && node.image.trim()) {
    const abs = path.resolve(baseDir, node.image.trim());
    if (fs.existsSync(abs)) node.__imageAbs = abs;
    else console.warn(`WARN: image not found, skipping: ${node.image}`);
  }
  for (const c of node.children || []) resolveImages(c, baseDir);
}

// Attach `children` under a Topic. parentUUID null → attach to the sheet root.
// `sheet` is needed to resolve the raw topic component when a node has a url.
function addChildren(topic, parentUUID, children, sheet, patchById) {
  for (const child of children || []) {
    if (parentUUID) topic.on(parentUUID); else topic.on();
    topic.add({ title: String(child.title) });
    const uuid = topic.cid();
    const url = nodeUrl(child);
    if (url && sheet) {
      const comp = sheet.findComponentById(uuid);
      if (comp && comp.addHref) comp.addHref(url);
    }
    if (patchById) { const p = patchFor(child); if (p) patchById[uuid] = p; }
    if (child.children && child.children.length) addChildren(topic, uuid, child.children, sheet, patchById);
  }
}

function applyTheme(wb, sheetId, themeName) {
  const sheet = wb.getSheet(sheetId);
  if (sheet && sheet.changeTheme) {
    sheet.changeTheme(new Theme({ themeName }).data);
  }
}

function buildSingleSheet(root, themeName) {
  const wb = new Workbook();
  const created = wb.createSheets([{ s: root.title, t: root.title }]);
  const sheetId = created[0].id;
  const sheet = wb.getSheet(sheetId);
  const topic = new Topic({ sheet });
  const patchById = {};
  addChildren(topic, null, root.children, sheet, patchById);
  applyTheme(wb, sheetId, themeName);
  return { wb, patchById };
}

function buildMultiSheet(root, themeName) {
  // One Overview sheet + one sheet per top-level branch.
  const OVERVIEW = 'Overview';
  const sheetDefs = [{ s: OVERVIEW, t: root.title }];
  for (const branch of root.children) sheetDefs.push({ s: branch.title, t: branch.title });

  const wb = new Workbook();
  const created = wb.createSheets(sheetDefs);

  // createSheets can de-dupe / reorder — map by title, then fall back by index.
  const sheetIds = {};
  created.forEach((c, i) => { sheetIds[c.title] = c.id; sheetIds['#' + i] = c.id; });
  const overviewId = sheetIds[OVERVIEW] || sheetIds['#0'];
  const overviewSheet = wb.getSheet(overviewId);

  // Cross-sheet links must target a topic ID, not a sheet ID.
  const branchTopicId = {};
  root.children.forEach((branch, i) => {
    const sid = sheetIds[branch.title] || sheetIds['#' + (i + 1)];
    branchTopicId[i] = wb.getSheet(sid).getRootTopic().getId();
  });

  // Per-node patches (style + image) collected across all sheets, applied later.
  const patchById = {};

  // Overview: one child per branch, hyperlinked to that branch's sub-sheet root.
  const overviewTopic = new Topic({ sheet: overviewSheet });
  root.children.forEach((branch, i) => {
    overviewTopic.on().add({ title: String(branch.title) });
    const uuid = overviewTopic.cid();
    const comp = overviewSheet.findComponentById(uuid);
    if (comp && comp.addHref) comp.addHref('xmind:#' + branchTopicId[i]);
    const p = patchFor(branch); if (p) patchById[uuid] = p;
  });

  // Sub-sheets: back-link the root to Overview, then attach the full subtree.
  const overviewRootId = overviewSheet.getRootTopic().getId();
  root.children.forEach((branch, i) => {
    const sid = sheetIds[branch.title] || sheetIds['#' + (i + 1)];
    const sheet = wb.getSheet(sid);
    const rootId = sheet.getRootTopic().getId();
    sheet.getRootTopic().addHref('xmind:#' + overviewRootId);
    const p = patchFor(branch); if (p) patchById[rootId] = p;   // patch the detail-sheet centre too
    const topic = new Topic({ sheet });
    addChildren(topic, null, branch.children || [], sheet, patchById);
  });

  // Theme every sheet.
  applyTheme(wb, overviewId, themeName);
  root.children.forEach((branch, i) => {
    const sid = sheetIds[branch.title] || sheetIds['#' + (i + 1)];
    applyTheme(wb, sid, themeName);
  });

  return { wb, patchById };
}

// ---------- companions ----------
function sanitizeMermaid(s) {
  // Mermaid mindmap treats ()[]{} as shape delimiters; strip them from labels.
  return String(s).replace(/[()\[\]{}]/g, '').replace(/\s+/g, ' ').trim();
}

function toMermaid(root) {
  const lines = ['mindmap', `  root((${sanitizeMermaid(root.title)}))`];
  const walk = (nodes, depth) => {
    for (const n of nodes || []) {
      lines.push('  '.repeat(depth) + sanitizeMermaid(n.title));
      if (n.children && n.children.length) walk(n.children, depth + 1);
    }
  };
  walk(root.children, 2);
  return lines.join('\n') + '\n';
}

function toMarkdownOutline(root) {
  const lines = ['# ' + String(root.title), ''];
  const walk = (nodes, depth) => {
    for (const n of nodes || []) {
      const url = nodeUrl(n);
      const text = decorateLabel(n);
      const label = url ? `[${text}](${url})` : text;
      lines.push('  '.repeat(depth) + '- ' + label);
      if (n.children && n.children.length) walk(n.children, depth + 1);
    }
  };
  walk(root.children, 0);
  return lines.join('\n') + '\n';
}

// ---------- style + image patching ----------
// Read a PNG's pixel dimensions from its IHDR (width @16, height @20, big-endian).
function pngSize(buf) {
  if (buf.length >= 24 && buf.toString('ascii', 1, 4) === 'PNG') {
    return { w: buf.readUInt32BE(16), h: buf.readUInt32BE(20) };
  }
  return { w: 0, h: 0 };
}

// The SDK has no per-topic style/image setter, so after the .xmind (a ZIP) is
// written we open it and merge collected style properties + embed images into
// each topic by id. Images are added under resources/ and referenced as
// xap:resources/… (XMind's scheme), with a manifest entry. Uses jszip (a dep of `xmind`).
async function applyPatches(xmindPath, patchById) {
  const JSZip = require('jszip');
  const zip = await JSZip.loadAsync(fs.readFileSync(xmindPath));
  const cEntry = zip.file('content.json');
  if (!cEntry) throw new Error('content.json not found inside the .xmind');
  const content = JSON.parse(await cEntry.async('string'));

  let manifest = { 'file-entries': {} };
  const mEntry = zip.file('manifest.json');
  if (mEntry) { try { manifest = JSON.parse(await mEntry.async('string')); } catch (e) { /* keep default */ } }
  manifest['file-entries'] = manifest['file-entries'] || {};

  const MAX_DISPLAY_W = 220;      // cap on-node image width so the map stays navigable
  const fileToRes = {};           // abs image path -> { res, buf } (dedupe shared images)
  let resSeq = 0, styled = 0, imaged = 0;

  const embedImage = (absPath) => {
    if (fileToRes[absPath]) return fileToRes[absPath];
    const buf = fs.readFileSync(absPath);
    const res = `resources/img-${++resSeq}.png`;
    zip.file(res, buf);
    manifest['file-entries'][res] = { 'media-type': 'image/png' };
    fileToRes[absPath] = { res, buf };
    return fileToRes[absPath];
  };

  const walk = (t) => {
    if (!t) return;
    const patch = t.id && patchById[t.id];
    if (patch) {
      if (patch.style) {
        t.style = t.style || {};
        t.style.properties = Object.assign({}, t.style.properties || {}, patch.style);
        styled++;
      }
      if (patch.image) {
        const { res, buf } = embedImage(patch.image);
        const { w, h } = pngSize(buf);
        const dispW = w ? Math.min(w, MAX_DISPLAY_W) : MAX_DISPLAY_W;
        const dispH = w ? Math.round(h * dispW / w) : MAX_DISPLAY_W;
        t.image = { src: 'xap:' + res, width: dispW, height: dispH };
        imaged++;
      }
    }
    const attached = t.children && t.children.attached;
    if (Array.isArray(attached)) attached.forEach(walk);
  };
  (Array.isArray(content) ? content : [content]).forEach((sheet) => walk(sheet.rootTopic));

  zip.file('content.json', JSON.stringify(content));
  zip.file('manifest.json', JSON.stringify(manifest));
  const out = await zip.generateAsync({ type: 'nodebuffer', compression: 'DEFLATE' });
  fs.writeFileSync(xmindPath, out);
  return { styled, imaged };
}

// ---------- main ----------
async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help || !args.tree) {
    console.log(USAGE);
    process.exit(args.help ? 0 : 1);
  }

  const raw = JSON.parse(fs.readFileSync(args.tree, 'utf8'));
  const { root, meta } = normalizeTree(raw, args.title);

  // Resolve any node `image` paths (relative to the tree file) to absolute paths.
  resolveImages(root, path.dirname(path.resolve(args.tree)));

  const themeName = args.theme || meta.theme || 'snowbrush';
  const allowed = ['snowbrush', 'robust', 'business'];
  if (!allowed.includes(themeName)) {
    throw new Error(`Theme "${themeName}" not allowed. Use one of: ${allowed.join(', ')}`);
  }

  let layout = args.layout || meta.layout || 'auto';
  if (layout === 'auto') layout = root.children.length > 1 ? 'multi' : 'single';
  if (!['single', 'multi'].includes(layout)) {
    throw new Error(`Layout "${layout}" invalid. Use single, multi, or auto.`);
  }

  const total = countNodes(root);
  const { wb, patchById } = layout === 'multi' ? buildMultiSheet(root, themeName)
                                              : buildSingleSheet(root, themeName);

  const outDir = path.resolve(args.out);
  fs.mkdirSync(outDir, { recursive: true });
  const base = args.name || slugify(root.title);

  const zipper = new Zipper({ path: outDir, workbook: wb, filename: base });
  const ok = await zipper.save();
  if (!ok) throw new Error('Zipper.save() returned false — the .xmind was not written.');

  const xmindPath = path.join(outDir, base + '.xmind');

  // Patch per-node styles (cli/bold/italic/style) + embed images into the saved .xmind.
  let styled = 0, imaged = 0;
  if (Object.keys(patchById).length) ({ styled, imaged } = await applyPatches(xmindPath, patchById));

  const sheetCount = layout === 'multi' ? root.children.length + 1 : 1;
  console.log(`nodes: ${total}  sheets: ${sheetCount}  layout: ${layout}  theme: ${themeName}  styled: ${styled}  images: ${imaged}`);
  console.log('xmind: ' + xmindPath);

  if (args.companions) {
    const mmd = path.join(outDir, base + '.mmd');
    const md = path.join(outDir, base + '.md');
    fs.writeFileSync(mmd, toMermaid(root));
    fs.writeFileSync(md, toMarkdownOutline(root));
    console.log('mermaid: ' + mmd);
    console.log('outline: ' + md);
  }
}

main().catch((err) => {
  console.error('ERROR: ' + err.message);
  process.exit(1);
});
