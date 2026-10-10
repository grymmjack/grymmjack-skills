#!/usr/bin/env bash
# build-docs.sh — render the workspace .md docs to styled .html (keeps the .md as source).
# Uses pandoc + assets/lesson.css so the docs match the lessons/reference cards.
# Re-run after editing any .md:   bash build-docs.sh
set -eu
# Workspace root = the directory this script lives in (portable across workspaces).
WS="$(cd "$(dirname "$0")" && pwd)"
command -v pandoc >/dev/null 2>&1 || { echo "ERROR: pandoc not found (brew install pandoc)"; exit 1; }

render() {          # render <md> <out.html> <css-prefix> <home-href>
  md="$1"; out="$2"; css="$3"; home="$4"
  base="$(basename "$md")"
  {
    printf '<!doctype html>\n<html lang="en"><head>\n'
    printf '<meta charset="utf-8">\n<meta name="viewport" content="width=device-width, initial-scale=1">\n'
    printf '<title>%s</title>\n' "$base"
    printf '<link rel="stylesheet" href="%sassets/lesson.css">\n' "$css"
    printf '</head><body>\n'
    printf '<!-- GENERATED from %s by build-docs.sh — edit the .md and re-run, do not hand-edit this .html -->\n' "$base"
    printf '<article class="lesson wide">\n'
    printf '<p class="eyebrow"><a href="%s">&larr; Course home</a> &middot; workspace doc (rendered from %s)</p>\n' "$home" "$base"
    pandoc "$md" -f gfm -t html
    printf '</article>\n<script src="%sassets/doc.js" defer></script>\n</body></html>\n' "$css"
  } > "$out"
  echo "  rendered $(basename "$md") -> $(basename "$out")"
}

echo "top-level docs:"
for name in TOPIC GLOSSARY RESOURCES OBSERVATIONS NOTES; do
  [ -f "$WS/$name.md" ] && render "$WS/$name.md" "$WS/$name.html" "" "index.html"
done

# Glossary: split each "**Term**: definition" paragraph into a prominent term line
# + its own definition block, so it reads as a spaced list (source GLOSSARY.md is untouched).
if [ -f "$WS/GLOSSARY.html" ]; then
  # handles both "**Term**: def" and "**Term** (qualifier): def" (colon outside the bold)
  perl -0777 -i -pe 's{<p><strong>(.*?)</strong>([^:<]*):\s*(.*?)</p>}{<p class="gterm"><strong>$1</strong>$2</p>\n<p class="gdef">$3</p>}gs' "$WS/GLOSSARY.html"
  echo "  post-processed GLOSSARY.html (term/definition split)"
fi

echo "learning records:"
for md in "$WS"/learning-records/*.md; do
  [ -e "$md" ] || continue
  render "$md" "${md%.md}.html" "../" "../index.html"
done
echo "done."
