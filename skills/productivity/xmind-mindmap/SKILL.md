---
name: xmind-mindmap
description: "Turn any topic into a real .xmind mind map — build a hierarchical topic tree and generate a genuine XMind file (single- or multi-sheet, hyperlinked, themed, with optional per-node screenshots/images, clickable links, and styling), plus optional SVG/PNG/PDF or interactive-HTML (markmap) renders. Use when the user wants a mind map, an .xmind file, to visualise/map/diagram a subject, to embed screenshots in a map, or to render a teach / learn-anything topic as a mind map."
argument-hint: "What topic should the mind map cover?"
---

# XMind mind map

Turn a topic into a **real `.xmind` file** — not a picture of a mind map, the
actual XMind document you can open and keep editing — plus optional static
renders (SVG / PNG / PDF) for sharing.

The whole map derives from **one hierarchical topic tree** (a JSON file). You
build the tree; a bundled Node generator turns it into the `.xmind`, and a
render script turns its Mermaid twin into images. This is the reusable,
any-subject version of the [`create-xmind`](https://github.com/grymmjack/DRAW/blob/main/.claude/skills/create-xmind/SKILL.md)
workflow proven in DRAW's [`DEV/XMIND-GENERATOR.md`](https://github.com/grymmjack/DRAW/blob/main/DEV/XMIND-GENERATOR.md).

## Prerequisites

The generator needs its npm dependency (`xmind`) installed **once**, inside
this skill's own folder:

```bash
cd <this-skill-dir> && npm install
```

Rendering to SVG/PNG/PDF uses Mermaid CLI (fetched on demand via `npx`) driving
a headless Chromium. `render.sh` auto-detects a pre-installed Chromium (e.g.
`/opt/pw-browsers/`) so nothing extra is downloaded; if none is present, mmdc
falls back to its own. The `.xmind` output needs **no** browser — only the
image renders do.

## The loop

1. **Pin the subject & shape.** Get the topic (the argument), and decide roughly
   how big it is — one concept (→ single sheet) or a broad subject with several
   major branches (→ multi-sheet overview + detail sheets). When in doubt, leave
   `layout` on `auto`.
2. **Build the topic tree.** Write a JSON tree — a central `title` and nested
   `children`. This is the real work; the file format is in
   [`reference/tree-format.md`](./reference/tree-format.md). Ground the content
   in trusted sources, not parametric guesswork — same discipline as `teach` /
   `learn-anything`. Keep nodes to short labels, one idea each, ~3–7 per parent.
3. **Generate the `.xmind`.**
   ```bash
   node scripts/generate-xmind.js --tree topic.json --out . --theme snowbrush
   ```
   This writes `<name>.xmind` plus two twins used for rendering and quick
   reading: `<name>.mmd` (Mermaid) and `<name>.md` (outline).
4. **Optionally render images.**
   ```bash
   ./scripts/render.sh <name>.mmd all       # → .svg, .png, .pdf
   ./scripts/render.sh <name>.mmd png        # just one format
   ./scripts/render.sh <name>.mmd html       # interactive markmap (best for big maps)
   ```
   Mermaid's radial `mindmap` layout gets unreadable past ~50 nodes. For a large
   tree, prefer **`html`** — it builds a collapsible, pan/zoom, clickable
   [markmap](https://markmap.js.org/) from the `.md` outline (keeps the tree's
   `url`s as anchors, starts collapsed to the branch level). The SVG render is
   also made clickable automatically when the source `<base>.tree.json` sits
   beside the `.mmd` (or via `TREE_JSON=<path>`).
5. **Hand back the files** and, if you can, open the `.xmind` for the user.

## Generator options

`node scripts/generate-xmind.js --tree <file.json>` accepts:

| Flag | Default | Meaning |
|------|---------|---------|
| `--tree <path>` | — | **Required.** The JSON topic tree. |
| `--out <dir>` | `.` | Output directory. |
| `--name <base>` | slug of the title | Output filename (no extension). |
| `--title <str>` | tree's own title | Override the central topic. |
| `--theme <name>` | `snowbrush` | `snowbrush`, `robust`, or `business`. |
| `--layout <mode>` | `auto` | `single`, `multi`, or `auto`. |
| `--no-companions` | — | Write only the `.xmind` (skip `.mmd`/`.md`). |

**Multi-sheet** output is an Overview sheet whose branches are **hyperlinked**
to per-branch detail sheets, each of which **back-links** to the Overview — the
same structure as DRAW's 20-sheet feature map. **Single-sheet** hangs the whole
tree off one central topic.

## Building the tree from a teach / learn-anything topic

This skill composes with [`teach`](../teach/SKILL.md) and
[`learn-anything`](../learn-anything/SKILL.md): when the user wants a topic
mapped, turn the workspace into a tree.

- **From `learn-anything`** — the framework *is* a mind map. Map its parts to
  branches: **5 Ws** (from `TOPIC.md`), **Resources** (`RESOURCES.md`),
  **Critical Observations** (similar / unique / connected, from
  `OBSERVATIONS.md`), **Applied Learning** (`GLOSSARY.md`), **In Practice**, and
  **Mastery**. Drop the resulting `.xmind` and renders into the topic
  workspace's `./reference/` so they sit alongside the other cards.
- **From `teach`** — branch by mission area: the `MISSION.md` framing at the
  centre, lessons and reference cards as branches, the glossary as its own
  branch. Save into the teaching workspace's `./reference/`.
- **Ad-hoc** — for a bare `/xmind-mindmap {topic}` with no workspace, research
  the subject into a sensible tree and write both the `topic.json` and the
  outputs wherever the user is working.

## Verify

`generate-xmind.js` prints node/sheet counts and the output paths. To inspect
the internal structure of the `.xmind` (it is a ZIP), see the verification
snippet and the SDK gotchas in [`reference/sdk-notes.md`](./reference/sdk-notes.md).

## Files

- `scripts/generate-xmind.js` — topic tree → `.xmind` (+ `.mmd`, `.md` twins).
- `scripts/render.sh` — Mermaid `.mmd` → SVG / PNG / PDF.
- `reference/tree-format.md` — the topic-tree JSON schema and authoring rules.
- `reference/sdk-notes.md` — XMind SDK quirks and how to verify output.
- `examples/photosynthesis.tree.json` — a worked multi-sheet example.
