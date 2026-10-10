# The topic tree format

`generate-xmind.js` reads **one JSON file** describing the mind map as a tree.
The tree is the single source of truth — the `.xmind`, the Mermaid `.mmd`, and
the Markdown outline are all derived from it.

## Canonical shape

```json
{
  "title": "Central Topic",
  "theme": "snowbrush",
  "layout": "multi",
  "children": [
    {
      "title": "A top-level branch",
      "children": [
        { "title": "A child" },
        { "title": "A parent", "children": [ { "title": "A grandchild" } ] }
      ]
    }
  ]
}
```

### Fields

| Field      | Where            | Meaning |
|------------|------------------|---------|
| `title`    | every node       | **Required.** The displayed text. Emoji are fine and render in XMind. |
| `url`      | any node         | Optional hyperlink. The node becomes a clickable link in the `.xmind` (and a Markdown link in the `.md` twin). Aliases: `href`, `link`. Ground it in a real source. |
| `children` | any node         | Optional array of child nodes. Omit for a leaf. Nesting depth is unlimited. |
| `theme`    | root only        | Optional. `snowbrush` (default), `robust`, or `business`. `--theme` overrides it. |
| `layout`   | root only        | Optional. `single`, `multi`, or `auto` (default). `--layout` overrides it. |
| `cli`      | any node         | Optional `true`. Styles the node as a **terminal**: black fill, green text, monospace font. Use for shell/CLI commands. In the `.md` twin the label is wrapped in backticks. |
| `bold`     | any node         | Optional `true`. Renders the node's text **bold** (a whole-node emphasis — mind-map nodes are short, so this is how you "bold a key word"). |
| `italic`   | any node         | Optional `true`. Renders the node's text *italic*. |
| `style`    | any node         | Optional object of raw XMind style properties, merged last (wins over the flags). Keys use XMind's vocabulary: `svg:fill`, `fo:color`, `fo:font-family`, `fo:font-weight`, `fo:font-style`, `fo:font-size`, `fo:text-decoration`, `border-line-color`, `line-color`, `shape-class`, … |
| `image`    | any node         | Optional path to a local **PNG** file, embedded as a picture on the topic. Path is resolved relative to the tree file's directory. The file is packed into the `.xmind` under `resources/` and referenced as `xap:resources/…`; identical paths are embedded once and shared. Display width is capped (~220px) with height kept proportional. |

### Node styling

`cli` / `bold` / `italic` are convenience flags; `style` is the escape hatch for any
XMind topic property. They apply to leaf and parent nodes alike, and in **multi-sheet**
mode a top-level branch's style is applied to both its Overview node and its detail-sheet
centre. The styling is real per-topic formatting written into the `.xmind` (it is patched
into `content.json` after generation, since the SDK has no topic style setter) — so it
survives editing in XMind. Note: static image renders (`.mmd` → SVG/PNG) do **not** carry
these node styles; only the `.xmind` and (for cli/bold/italic) the `.md` outline do.

```json
{ "title": "Install", "bold": true, "children": [
  { "title": "npm i -g @shopify/cli", "cli": true },
  { "title": "rustup target add wasm32-unknown-unknown", "cli": true }
] }
```

### Node images

`image` embeds a real picture on a topic — e.g. a screenshot of the website a node
links to. Capture the images however you like (a headless browser is handy for site
thumbnails) into a folder beside the tree, then point each node's `image` at it:

```json
{ "title": "Website: About Functions",
  "url": "https://shopify.dev/docs/apps/build/functions",
  "image": "screenshots/img-02.png" }
```

The picture is embedded in the `.xmind` (patched in after generation, since the SDK has
no image setter), so it travels with the file. As with node styling, the static SVG/PNG
renders do **not** carry embedded images — only the `.xmind` does.

> In **multi-sheet** mode a top-level branch's own node on the Overview is
> reserved for its cross-sheet navigation link, so a `url` on a *top-level*
> branch is ignored. Put source URLs on the child/leaf nodes (where they
> belong anyway).

`children` at the root may also be given under the key `tree`, and a **bare
JSON array** is accepted as the list of top-level branches (supply the central
title with `--title`).

## Single vs multi-sheet

- **single** — one sheet, the whole tree hanging off one central topic. Best for
  small maps (a single concept, a cheat sheet).
- **multi** — an **Overview** sheet whose nodes are the top-level branches, each
  **hyperlinked** to its own detail sheet; every detail sheet's root **back-links**
  to the Overview. Best for broad subjects with several big branches.
- **auto** (default) — multi when there is more than one top-level branch, else single.

## Authoring guidance

- Keep each node a **short label**, not a sentence — a mind map is a skeleton.
- One idea per node; push detail down into children rather than into long titles.
- Aim for a readable fan-out (≈3–7 children per node); very wide levels read poorly.
- Titles are used verbatim in the `.xmind`. For the Mermaid twin, the shape
  characters `()[]{}` are stripped from labels automatically.
