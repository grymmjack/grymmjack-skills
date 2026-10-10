#!/usr/bin/env bash
#
# render.sh — render a Mermaid `mindmap` (.mmd) to SVG / PNG / PDF.
#
# The .xmind file itself is the primary deliverable; this turns the .mmd twin
# that generate-xmind.js writes alongside it into shareable static images.
# Rendering uses Mermaid CLI (mmdc) driving a headless Chromium.
#
# Usage:
#   ./render.sh <input.mmd> [format] [output-basename]
#
#   format: svg | png | pdf | html | all   (default: svg)
#     html → an interactive, collapsible, clickable mindmap via markmap, built
#            from the sibling <base>.md outline (Mermaid's radial layout gets
#            unreadable past ~50 nodes; markmap stays navigable and keeps links).
#   output-basename: defaults to the input name without extension
#
# Examples:
#   ./render.sh photosynthesis.mmd png
#   ./render.sh photosynthesis.mmd html            # interactive markmap
#   ./render.sh photosynthesis.mmd all diagrams/photosynthesis
#
set -euo pipefail

IN="${1:?usage: render.sh <input.mmd> [svg|png|pdf|all] [out-basename]}"
FMT="${2:-svg}"
OUTBASE="${3:-${IN%.*}}"

if [[ ! -f "$IN" ]]; then
  echo "render.sh: input not found: $IN" >&2
  exit 1
fi

# Mermaid emits no hyperlinks, so an SVG loses the tree's per-node `url`s. If we
# can find the source tree — $TREE_JSON, else a sibling <base>.tree.json — run
# link-svg.js after each SVG render to wrap linked nodes in clickable <a>s.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TREE="${TREE_JSON:-${IN%.*}.tree.json}"
link_svg() {
  local svg="$1"
  [[ -f "$TREE" && -f "$HERE/link-svg.js" ]] || return 0
  node "$HERE/link-svg.js" --tree "$TREE" --svg "$svg" || true
}

# Prefer a pre-installed Chromium (e.g. the Playwright browser this environment
# ships) so mmdc does not try to download one. Fall back to mmdc's default.
PPTR_CFG=""
CHROME="$(ls /opt/pw-browsers/chromium*/chrome-linux/chrome 2>/dev/null | head -1 || true)"
if [[ -n "$CHROME" ]]; then
  PPTR_CFG="$(mktemp --suffix=.json)"
  cat > "$PPTR_CFG" <<JSON
{ "executablePath": "$CHROME", "args": ["--no-sandbox"] }
JSON
  trap 'rm -f "$PPTR_CFG"' EXIT
fi

render_one() {
  local fmt="$1" out="$OUTBASE.$1"
  mkdir -p "$(dirname "$out")"
  local -a cmd=(npx -y @mermaid-js/mermaid-cli -i "$IN" -o "$out")
  [[ -n "$PPTR_CFG" ]] && cmd+=(-p "$PPTR_CFG")
  echo "rendering $out ..."
  "${cmd[@]}"
  [[ "$fmt" == svg ]] && link_svg "$out"
  echo "  -> $out"
}

# Interactive markmap from the sibling .md outline. markmap reads YAML frontmatter
# for view defaults, so we prepend a small block (start collapsed to the branch
# level → digestible; stable per-branch colors; wrap long labels) to a temp copy.
render_markmap() {
  local md="${IN%.*}.md" out="$OUTBASE.html"
  if [[ ! -f "$md" ]]; then
    echo "render.sh: markmap needs the .md twin next to the .mmd: $md" >&2
    return 1
  fi
  mkdir -p "$(dirname "$out")"
  local tmpdir; tmpdir="$(mktemp -d)"
  {
    printf '%s\n' '---' 'markmap:' '  initialExpandLevel: 3' \
      '  colorFreezeLevel: 2' '  maxWidth: 320' '  spacingVertical: 8' '---' ''
    cat "$md"
  } > "$tmpdir/map.md"
  echo "rendering $out (markmap) ..."
  npx -y markmap-cli --no-open --offline -o "$out" "$tmpdir/map.md"
  rm -rf "$tmpdir"
  echo "  -> $out"
}

case "$FMT" in
  svg|png|pdf) render_one "$FMT" ;;
  html|markmap) render_markmap ;;
  all) render_one svg; render_one png; render_one pdf ;;
  *) echo "render.sh: unknown format '$FMT' (svg|png|pdf|html|all)" >&2; exit 1 ;;
esac
