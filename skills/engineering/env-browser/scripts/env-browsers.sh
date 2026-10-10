#!/usr/bin/env bash
# env-browsers — fuzzy package-environment browsers for node/rust/go/ruby.
# Companion to pybrowse.sh (Python). Source both from your shell rc:
#   for f in /path/to/scripts/*.sh; do source "$f"; done
#   nodebrowse [-g]   # ./node_modules or global npm
#   rustbrowse        # the Cargo project in $PWD
#   gobrowse          # the Go module in $PWD
#   gembrowse         # installed Ruby gems
# Requires: fzf, jq, and the relevant toolchain (npm/cargo/go/gem).
# Optional: bat/batcat for the source preview. See SKILL.md for keys.

# ─────────────────────────────────────────────────────────────────────────
# Package-environment browsers — nodebrowse / rustbrowse / gobrowse / gembrowse.
#
# The pip-focused `pybrowse` (above) generalised to four more ecosystems. They
# all share one two-level fzf engine (_pkgbrowse_engine): level 1 is the
# installed-package list ("<name> <version> <description>"), with a preview
# pane of full metadata (summary, registry + docs links, requires, required-by,
# install location); level 2 (ENTER) drills into that package's own source
# tree with a bat preview. ESC pops level 2 back, ESC on the list quits.
#
# Per-ecosystem differences live only in a small backend script (written to
# /tmp) exposing five sub-commands: list | show <name> | files <name> |
# url <mode> <name> | help <name>. The engine reads the active backend from
# $PKGBROWSE_BACKEND, so adding an ecosystem is just another backend + a
# three-line public function.
#
# Keys (Alt-chords, so fzf's type-to-filter keeps every letter):
#   ENTER  drill into the package's source files
#   Alt-W  open the registry page (npmjs / crates.io / pkg.go.dev / rubygems)
#   Alt-D  open the documentation / homepage
#   Alt-H  help — README / `go doc` / crate docs — paged through $PAGER
#
#   nodebrowse [-g]   ./node_modules (default) or global (-g)
#   rustbrowse        the Cargo project in $PWD (cargo metadata)
#   gobrowse          the Go module in $PWD (go list -m all)
#   gembrowse         installed Ruby gems (global)
# ─────────────────────────────────────────────────────────────────────────

# Syntax-highlighting pager for the level-2 source preview.
_pkgbrowse_batcmd() {
  if command -v bat >/dev/null 2>&1; then
    echo 'bat --color=always --style=numbers --paging=never'
  elif command -v batcat >/dev/null 2>&1; then
    echo 'batcat --color=always --style=numbers --paging=never'
  else
    echo 'cat'
  fi
}

# URL opener, detached so it survives fzf's execute-silent teardown. Resolves
# the URL through the active backend ($PKGBROWSE_BACKEND, inherited from env).
_pkgbrowse_ensure_open() {
  cat >/tmp/pkgbrowse-open.sh <<'HELPER'
#!/usr/bin/env bash
mode="$1"; shift
name=$(printf '%s' "$*" | sed 's/\x1b\[[0-9;]*m//g' | awk '{print $1}')
[ -z "$name" ] && exit 0
url=$(bash "$PKGBROWSE_BACKEND" url "$mode" "$name" 2>/dev/null)
[ -z "$url" ] && exit 0
if [ "$(uname)" = "Darwin" ]; then opener=open; else opener=xdg-open; fi
nohup "$opener" "$url" >/dev/null 2>&1 &
HELPER
  chmod +x /tmp/pkgbrowse-open.sh
}

# Level 2: browse one package's source files with a bat preview. Rows are
# "<display-path>\t<absolute-path>"; the list shows only the short field.
_pkgbrowse_ensure_outline() {
  cat >/tmp/pkgbrowse-outline.sh <<'OUTLINE'
#!/usr/bin/env bash
# pkgbrowse outline — a navigable symbol picker for one source file.
# Extracts classes/functions/methods/vars via universal-ctags, lists them in
# fzf (sorted top-to-bottom by line), previews the source highlighted at the
# selected symbol, and jumps $EDITOR to its line on ENTER. Launched from the
# level-2 file browser via ctrl-o. Arg: <file>.
file="$1"
[ -f "$file" ] || exit 0
if ! command -v ctags >/dev/null 2>&1; then
  printf 'Outline needs universal-ctags.\n  macOS:  brew install universal-ctags\n  Debian: sudo apt install universal-ctags\n'
  sleep 2.2; exit 0
fi
# Rows: "<line>\t<kind>  <name>" (kind dim, name yellow), ordered by line.
rows=$(ctags -x "$file" 2>/dev/null \
  | awk '{printf "%s\t\033[2m%-11s\033[0m \033[1;33m%s\033[0m\n", $3, $2, $1}' \
  | sort -n -k1,1)
if [ -z "$rows" ]; then
  echo "No symbols found in $(basename "$file")."; sleep 1.4; exit 0
fi

export PKGBROWSE_OUTLINE_FILE="$file"
if command -v bat >/dev/null 2>&1; then bcmd=bat
elif command -v batcat >/dev/null 2>&1; then bcmd=batcat
else bcmd=""; fi
if [ -n "$bcmd" ]; then
  prev="$bcmd --color=always --style=numbers --highlight-line {1} --paging=never \"\$PKGBROWSE_OUTLINE_FILE\""
  pwin="right,72%,+{1}-6"
else
  prev='awk -v L={1} "NR>=L-8 \&\& NR<=L+40 {printf \"%s%4d  %s\n\", (NR==L?\">\":\" \"), NR, \$0}" "$PKGBROWSE_OUTLINE_FILE"'
  pwin="right,72%"
fi

printf '%s\n' "$rows" | fzf \
  --style full --ansi --reverse --border --padding 1,2 \
  --delimiter='\t' --with-nth=2 \
  --border-label="🔎 $(basename "$file") — outline" \
  --list-label='symbols' \
  --preview-label='source' \
  --preview "$prev" \
  --preview-window="$pwin" \
  --bind "enter:execute(\${EDITOR:-vim} +{1} \"\$PKGBROWSE_OUTLINE_FILE\")" \
  --footer='ENTER edit at line · ESC back to files'
OUTLINE
  chmod +x /tmp/pkgbrowse-outline.sh
}

_pkgbrowse_files() {
  local label="$1" pkg="$2"
  local files; files=$(bash "$PKGBROWSE_BACKEND" files "$pkg")
  if [ -z "$files" ]; then
    echo "No source files found for $pkg."
    sleep 1.2
    return
  fi
  local batcmd; batcmd=$(_pkgbrowse_batcmd)
  _pkgbrowse_ensure_outline
  echo "$files" | fzf \
    --style full --ansi --reverse --border --padding 1,2 \
    --delimiter='\t' --with-nth=1 \
    --border-label="$label — source" \
    --list-label="$pkg" \
    --preview-label='source' \
    --preview "$batcmd {2} 2>/dev/null | head -400" \
    --preview-window='right,70%' \
    --bind "enter:execute(\${EDITOR:-vim} {2})" \
    --bind 'focus:transform-header:echo {2}' \
    --bind 'ctrl-o:execute(bash /tmp/pkgbrowse-outline.sh {2})' \
    --footer='ENTER edit · Ctrl-O outline · ESC back'
}

# Level 1: the package list. Reads $PKGBROWSE_BACKEND (exported by the caller).
# $1 border-label  $2 list-label  $3 registry-key-name  $4 docs-key-name
_pkgbrowse_engine() {
  local border="$1" listlabel="$2" regname="$3" docsname="$4"
  local BK="$PKGBROWSE_BACKEND"
  _pkgbrowse_ensure_open
  while true; do
    local sel
    sel=$(bash "$BK" list | fzf \
      --style full --ansi --reverse --border --padding 1,2 \
      --border-label="$border" \
      --list-label="$listlabel" \
      --preview-label='package info' \
      --preview "pkg=\$(printf '%s' {} | sed 's/\x1b\[[0-9;]*m//g' | awk '{print \$1}'); bash "$BK" show \"\$pkg\"" \
      --preview-window='right,55%' \
      --bind "alt-w:execute-silent(/tmp/pkgbrowse-open.sh registry {})" \
      --bind "alt-d:execute-silent(/tmp/pkgbrowse-open.sh docs {})" \
      --bind "alt-h:execute(pkg=\$(printf '%s' {} | sed 's/\x1b\[[0-9;]*m//g' | awk '{print \$1}'); bash "$BK" help \"\$pkg\" | \${PAGER:-less -R})" \
      --bind 'focus:transform-header:
        line=$(printf "%s" {} | sed "s/\x1b\[[0-9;]*m//g");
        pkg=$(echo "$line" | awk "{print \$1}");
        rest=$(echo "$line" | cut -d" " -f2-);
        echo -e "\033[1;33m$pkg\033[0m";
        echo -e "\033[0;36m$rest\033[0m"' \
      --footer="ENTER source · Alt-W $regname · Alt-D $docsname · Alt-H help · ESC quit")
    [ -z "$sel" ] && break
    local pkg; pkg=$(printf '%s' "$sel" | sed 's/\x1b\[[0-9;]*m//g' | awk '{print $1}')
    [ -z "$pkg" ] && break
    _pkgbrowse_files "$border" "$pkg"
  done
}

# ── Public functions ─────────────────────────────────────────────────────

nodebrowse() {
  command -v fzf >/dev/null 2>&1 || { echo "nodebrowse: fzf is required"; return 1; }
  command -v jq  >/dev/null 2>&1 || { echo "nodebrowse: jq is required"; return 1; }
  local root
  if [ "$1" = "-g" ] || [ "$1" = "--global" ]; then
    root=$(npm root -g 2>/dev/null)
  elif [ -d "./node_modules" ]; then
    root="$PWD/node_modules"
  else
    root=$(npm root -g 2>/dev/null)
  fi
  [ -d "$root" ] || { echo "nodebrowse: no node_modules found (looked at: $root)"; return 1; }
  _node_ensure_backend
  export NODEBROWSE_ROOT="$root"
  export PKGBROWSE_BACKEND="/tmp/nodebrowse-backend.sh"
  local scope="global"; [ "$root" = "$PWD/node_modules" ] && scope="./node_modules"
  _pkgbrowse_engine "📦 node — $scope" "npm packages" "npm" "homepage"
}

rustbrowse() {
  command -v fzf   >/dev/null 2>&1 || { echo "rustbrowse: fzf is required"; return 1; }
  command -v cargo >/dev/null 2>&1 || { echo "rustbrowse: cargo is required"; return 1; }
  if ! cargo metadata --format-version 1 >/tmp/rustbrowse-meta.json 2>/tmp/rustbrowse-err.txt; then
    echo "rustbrowse: could not read cargo metadata (run inside a Cargo project):"
    cat /tmp/rustbrowse-err.txt
    return 1
  fi
  _rust_ensure_backend
  export RUSTBROWSE_META=/tmp/rustbrowse-meta.json
  export PKGBROWSE_BACKEND="/tmp/rustbrowse-backend.sh"
  _pkgbrowse_engine "🦀 rust — $(basename "$PWD")" "crates" "crates.io" "docs.rs"
}

gobrowse() {
  command -v fzf >/dev/null 2>&1 || { echo "gobrowse: fzf is required"; return 1; }
  command -v go  >/dev/null 2>&1 || { echo "gobrowse: go is required"; return 1; }
  command -v jq  >/dev/null 2>&1 || { echo "gobrowse: jq is required"; return 1; }
  if ! go list -m -json all 2>/tmp/gobrowse-err.txt | jq -s . >/tmp/gobrowse-meta.json 2>/dev/null || [ ! -s /tmp/gobrowse-meta.json ]; then
    echo "gobrowse: could not list modules (run inside a Go module):"
    cat /tmp/gobrowse-err.txt
    return 1
  fi
  _go_ensure_backend
  export GOBROWSE_META=/tmp/gobrowse-meta.json
  export PKGBROWSE_BACKEND="/tmp/gobrowse-backend.sh"
  _pkgbrowse_engine "🐹 go — $(basename "$PWD")" "modules" "pkg.go.dev" "pkg.go.dev"
}

gembrowse() {
  command -v fzf >/dev/null 2>&1 || { echo "gembrowse: fzf is required"; return 1; }
  command -v gem >/dev/null 2>&1 || { echo "gembrowse: gem is required"; return 1; }
  _gem_ensure_backend
  export PKGBROWSE_BACKEND="/tmp/gembrowse-backend.sh"
  _pkgbrowse_engine "💎 ruby gems" "installed gems" "rubygems" "docs"
}

_node_ensure_backend() {
  cat >/tmp/nodebrowse-backend.sh <<'BACKEND'
#!/usr/bin/env bash
# nodebrowse backend. Reads NODEBROWSE_ROOT (a node_modules dir).
# Sub-commands: list | show <name> | files <name> | url <mode> <name> | help <name>
root="${NODEBROWSE_ROOT:?NODEBROWSE_ROOT not set}"
Y=$'\e[33m'; DIM=$'\e[2m'; C=$'\e[36m'; R=$'\e[0m'; W=$'\e[1;37m'; B=$'\e[1;34m'; G=$'\e[0;32m'
cmd="$1"

pkgdir() { printf '%s/%s' "$root" "$1"; }   # name may be @scope/pkg

case "$cmd" in
  list)
    for pj in "$root"/*/package.json "$root"/@*/*/package.json; do
      [ -f "$pj" ] || continue
      jq -r --arg Y "$Y" --arg D "$DIM" --arg C "$C" --arg R "$R" '
        "\($Y)\(.name)\($R) \($D)\(.version // "?")\($R)  \($C)\(((.description // "") | gsub("\n";" "))[0:100])\($R)"' \
        "$pj" 2>/dev/null
    done | sort -f
    ;;
  show)
    name="$2"; pj="$(pkgdir "$name")/package.json"
    [ -f "$pj" ] || { echo "${R}Package not found: $name"; exit 0; }
    jq -r --arg W "$W" --arg R "$R" --arg C "$C" --arg B "$B" '
      "\($W)\(.name) \(.version)\($R)",
      "",
      "\($W)Summary\($R)     \(.description // "")",
      "",
      "\($W)Homepage\($R)    \($B)\(.homepage // "(none)")\($R)",
      "\($W)npm\($R)         \($B)https://www.npmjs.com/package/\(.name)\($R)",
      "\($W)Repo\($R)        \($B)\(if (.repository|type)=="object" then (.repository.url // "") else (.repository // "") end)\($R)",
      "\($W)License\($R)     \(.license // "")",
      "\($W)Main\($R)        \(.main // "index.js")",
      "\($W)Requires\($R)    \($C)\((.dependencies // {}) | keys | join(", "))\($R)"
    ' "$pj" 2>/dev/null
    # Required-by: other installed packages whose runtime deps include this name.
    local_rb=$(for opj in "$root"/*/package.json "$root"/@*/*/package.json; do
      [ -f "$opj" ] || continue
      jq -r --arg n "$name" 'select((.dependencies // {}) | has($n)) | .name' "$opj" 2>/dev/null
    done | sort -u | awk 'NR>1{printf ", "}{printf "%s",$0}END{if(NR)print ""}')
    [ -n "$local_rb" ] && printf '%sRequired-by%s  %s%s%s\n' "$W" "$R" "$C" "$local_rb" "$R"
    d="$(pkgdir "$name")"
    nfiles=$(find "$d" -name node_modules -prune -o -type f \( -name '*.js' -o -name '*.mjs' -o -name '*.cjs' -o -name '*.ts' \) -print 2>/dev/null | wc -l | tr -d ' ')
    printf '\n%sSource files (%s)%s  %sENTER to browse%s\n' "$W" "$nfiles" "$R" "$DIM" "$R"
    ;;
  files)
    name="$2"; d="$(pkgdir "$name")"
    find "$d" -name node_modules -prune -o -type f \
      \( -name '*.js' -o -name '*.mjs' -o -name '*.cjs' -o -name '*.ts' -o -name '*.jsx' -o -name '*.tsx' \) -print 2>/dev/null \
      | while IFS= read -r f; do printf '%s\t%s\n' "${f#"$d"/}" "$f"; done | sort
    ;;
  url)
    mode="$2"; name="$3"
    if [ "$mode" = registry ]; then
      echo "https://www.npmjs.com/package/$name"
    else
      jq -r '.homepage // empty' "$(pkgdir "$name")/package.json" 2>/dev/null
    fi
    ;;
  help)
    name="$2"; d="$(pkgdir "$name")"
    rm=$(ls "$d"/README.md "$d"/README* "$d"/readme* 2>/dev/null | head -1)
    if [ -n "$rm" ]; then cat "$rm"; else echo "No README bundled for $name."; fi
    ;;
esac
BACKEND
  chmod +x /tmp/nodebrowse-backend.sh
}

_rust_ensure_backend() {
  cat >/tmp/rustbrowse-backend.sh <<'BACKEND'
#!/usr/bin/env bash
# rustbrowse backend. Reads RUSTBROWSE_META (cached `cargo metadata` JSON).
# Sub-commands: list | show <name> | files <name> | url <mode> <name> | help <name>
meta="${RUSTBROWSE_META:?RUSTBROWSE_META not set}"
Y=$'\e[33m'; DIM=$'\e[2m'; C=$'\e[36m'; R=$'\e[0m'; W=$'\e[1;37m'; B=$'\e[1;34m'
cmd="$1"

case "$cmd" in
  list)
    jq -r --arg Y "$Y" --arg D "$DIM" --arg C "$C" --arg R "$R" '
      .packages | unique_by(.name) | .[] |
      "\($Y)\(.name)\($R) \($D)\(.version)\($R)  \($C)\(((.description // "") | gsub("\n";" "))[0:100])\($R)"' \
      "$meta" 2>/dev/null | sort -f
    ;;
  show)
    name="$2"
    jq -r --arg n "$name" --arg W "$W" --arg R "$R" --arg C "$C" --arg B "$B" '
      .packages | map(select(.name==$n)) | .[0] // empty |
      "\($W)\(.name) \(.version)\($R)",
      "",
      "\($W)Summary\($R)     \(.description // "")",
      "",
      "\($W)docs.rs\($R)     \($B)\(.documentation // "https://docs.rs/\(.name)")\($R)",
      "\($W)crates.io\($R)   \($B)https://crates.io/crates/\(.name)\($R)",
      "\($W)Homepage\($R)    \($B)\(.homepage // "")\($R)",
      "\($W)Repo\($R)        \($B)\(.repository // "")\($R)",
      "\($W)License\($R)     \(.license // "")",
      "\($W)Requires\($R)    \($C)\([.dependencies[] | select(.kind==null) | .name] | unique | join(", "))\($R)"
    ' "$meta" 2>/dev/null
    # Required-by: crates in the resolve graph that depend on this one.
    rb=$(jq -r --arg n "$name" '
      (.packages | map({key:.id, value:.name}) | from_entries) as $names |
      [ .resolve.nodes[] | select([.dependencies[] | $names[.]] | index($n)) | $names[.id] ]
      | unique | map(select(. != $n)) | join(", ")' "$meta" 2>/dev/null)
    [ -n "$rb" ] && printf '%sRequired-by%s  %s%s%s\n' "$W" "$R" "$C" "$rb" "$R"
    mp=$(jq -r --arg n "$name" '.packages | map(select(.name==$n)) | .[0].manifest_path // empty' "$meta" 2>/dev/null)
    if [ -n "$mp" ]; then
      d=$(dirname "$mp")
      nfiles=$(find "$d" -name '*.rs' -not -path '*/target/*' 2>/dev/null | wc -l | tr -d ' ')
      printf '\n%sSource\n%s%s\n' "$W" "$R" "$d"
      printf '%sSource files (%s)%s  %sENTER to browse%s\n' "$W" "$nfiles" "$R" "$DIM" "$R"
    fi
    ;;
  files)
    name="$2"
    mp=$(jq -r --arg n "$name" '.packages | map(select(.name==$n)) | .[0].manifest_path // empty' "$meta" 2>/dev/null)
    [ -z "$mp" ] && exit 0
    d=$(dirname "$mp")
    find "$d" -name '*.rs' -not -path '*/target/*' 2>/dev/null \
      | while IFS= read -r f; do printf '%s\t%s\n' "${f#"$d"/}" "$f"; done | sort
    ;;
  url)
    mode="$2"; name="$3"
    if [ "$mode" = registry ]; then
      echo "https://crates.io/crates/$name"
    else
      u=$(jq -r --arg n "$name" '.packages | map(select(.name==$n)) | .[0].documentation // empty' "$meta" 2>/dev/null)
      [ -z "$u" ] && u="https://docs.rs/$name"
      echo "$u"
    fi
    ;;
  help)
    name="$2"
    mp=$(jq -r --arg n "$name" '.packages | map(select(.name==$n)) | .[0].manifest_path // empty' "$meta" 2>/dev/null)
    [ -z "$mp" ] && { echo "No source for $name"; exit 0; }
    d=$(dirname "$mp")
    rm=$(ls "$d"/README.md "$d"/README* "$d"/readme* 2>/dev/null | head -1)
    if [ -n "$rm" ]; then cat "$rm"
    elif [ -f "$d/src/lib.rs" ]; then
      echo "# $name — src/lib.rs (no README bundled)"; echo
      grep -E '^\s*//[!/]' "$d/src/lib.rs" | sed -E 's#^\s*//[!/]\s?##' | head -60
    else echo "No README or lib.rs docs for $name."; fi
    ;;
esac
BACKEND
  chmod +x /tmp/rustbrowse-backend.sh
}

_go_ensure_backend() {
  cat >/tmp/gobrowse-backend.sh <<'BACKEND'
#!/usr/bin/env bash
# gobrowse backend. Reads GOBROWSE_META (cached `go list -m -json all | jq -s .`).
# Sub-commands: list | show <name> | files <name> | url <mode> <name> | help <name>
# Go modules are identified by import path; there is no description field, so
# rows are "<path> <version>" and Alt-H runs `go doc` for the real synopsis.
meta="${GOBROWSE_META:?GOBROWSE_META not set}"
Y=$'\e[33m'; DIM=$'\e[2m'; C=$'\e[36m'; R=$'\e[0m'; W=$'\e[1;37m'; B=$'\e[1;34m'
cmd="$1"

case "$cmd" in
  list)
    jq -r --arg Y "$Y" --arg D "$DIM" --arg R "$R" '
      .[] | select(.Main != true) |
      "\($Y)\(.Path)\($R) \($D)\(.Version // "")\($R)"' "$meta" 2>/dev/null | sort -f
    ;;
  show)
    name="$2"
    jq -r --arg n "$name" --arg W "$W" --arg R "$R" --arg B "$B" '
      .[] | select(.Path==$n) |
      "\($W)\(.Path)\($R)",
      "",
      "\($W)Version\($R)    \(.Version // "(main module)")",
      "\($W)pkg.go.dev\($R) \($B)https://pkg.go.dev/\(.Path)\($R)",
      "\($W)Go\($R)         \(.GoVersion // "")",
      "\($W)Dir\($R)        \(.Dir // "(not downloaded — run: go mod download)")"
    ' "$meta" 2>/dev/null
    dir=$(jq -r --arg n "$name" '.[] | select(.Path==$n) | .Dir // empty' "$meta" 2>/dev/null)
    if [ -n "$dir" ] && [ -f "$dir/go.mod" ]; then
      req=$(awk '/^require[ (]/{f=1} f&&/^\t?[^ \t)]/{gsub(/^[ \t]+/,"");print $1} /^\)/{f=0}' "$dir/go.mod" \
            | grep -v '^require' | grep '\.' | sort -u | awk 'NR>1{printf ", "}{printf "%s",$0}END{if(NR)print ""}')
      [ -n "$req" ] && printf '\n%sRequires%s   %s%s%s\n' "$W" "$R" "$C" "$req" "$R"
    fi
    if [ -n "$dir" ]; then
      nfiles=$(find "$dir" -name '*.go' -not -name '*_test.go' 2>/dev/null | wc -l | tr -d ' ')
      printf '\n%sSource files (%s)%s  %sENTER to browse%s\n' "$W" "$nfiles" "$R" "$DIM" "$R"
    fi
    ;;
  files)
    name="$2"
    dir=$(jq -r --arg n "$name" '.[] | select(.Path==$n) | .Dir // empty' "$meta" 2>/dev/null)
    [ -z "$dir" ] && exit 0
    find "$dir" -type f -name '*.go' 2>/dev/null \
      | while IFS= read -r f; do printf '%s\t%s\n' "${f#"$dir"/}" "$f"; done | sort
    ;;
  url)
    name="$3"
    echo "https://pkg.go.dev/$name"
    ;;
  help)
    name="$2"
    if command -v go >/dev/null 2>&1; then
      out=$(timeout 15 go doc "$name" 2>/dev/null)
      [ -n "$out" ] && { echo "$out"; exit 0; }
    fi
    dir=$(jq -r --arg n "$name" '.[] | select(.Path==$n) | .Dir // empty' "$meta" 2>/dev/null)
    rm=$(ls "$dir"/README.md "$dir"/README* "$dir"/readme* 2>/dev/null | head -1)
    if [ -n "$rm" ]; then cat "$rm"; else echo "No 'go doc' output or README for $name."; fi
    ;;
esac
BACKEND
  chmod +x /tmp/gobrowse-backend.sh
}

_gem_ensure_backend() {
  cat >/tmp/gembrowse-backend.sh <<'BACKEND'
#!/usr/bin/env bash
# gembrowse backend (Ruby gems, global). Sub-commands:
#   list | show <name> | files <name> | url <mode> <name> | help <name>
Y=$'\e[33m'; DIM=$'\e[2m'; C=$'\e[36m'; R=$'\e[0m'; W=$'\e[1;37m'; B=$'\e[1;34m'
cmd="$1"

case "$cmd" in
  list)
    # "name (1.2.3, 4.5.6)" or "name (default: 1.2.3)" -> name + newest version.
    gem list 2>/dev/null | while IFS= read -r line; do
      [ -z "$line" ] && continue
      nm=${line%% *}
      ver=$(printf '%s' "$line" | sed -E 's/^[^(]*\(//; s/\).*//; s/default: //; s/,.*//')
      printf '%s%s%s %s%s%s\n' "$Y" "$nm" "$R" "$DIM" "$ver" "$R"
    done | sort -f
    ;;
  show)
    name="$2"
    ruby -e '
      require "rubygems"
      begin; s = Gem::Specification.find_by_name(ARGV[0]); rescue Exception; puts "Gem not found: #{ARGV[0]}"; exit; end
      W="\e[1;37m"; R="\e[0m"; C="\e[36m"; B="\e[1;34m"
      puts "#{W}#{s.name} #{s.version}#{R}"
      puts
      puts "#{W}Summary#{R}     #{s.summary}"
      puts
      puts "#{W}rubygems#{R}    #{B}https://rubygems.org/gems/#{s.name}#{R}"
      puts "#{W}Homepage#{R}    #{B}#{s.homepage}#{R}"
      puts "#{W}License#{R}     #{(s.licenses || []).join(", ")}"
      deps = s.dependencies.select { |d| d.type == :runtime }.map(&:name).sort
      puts "#{W}Requires#{R}    #{C}#{deps.join(", ")}#{R}" unless deps.empty?
      rb = Gem::Specification.select { |g| g.dependencies.any? { |d| d.type == :runtime && d.name == s.name } }.map(&:name).uniq.sort
      puts "#{W}Required-by#{R}  #{C}#{rb.join(", ")}#{R}" unless rb.empty?
      puts
      puts "#{W}Location#{R}    #{s.gem_dir}"
      n = Dir.glob(File.join(s.gem_dir, "**", "*.rb")).size
      puts "#{W}Source files (#{n})#{R}  \e[2mENTER to browse#{R}"
    ' "$name" 2>/dev/null
    ;;
  files)
    name="$2"
    ruby -e '
      require "rubygems"
      begin; s = Gem::Specification.find_by_name(ARGV[0]); rescue Exception; exit; end
      d = s.gem_dir
      Dir.glob(File.join(d, "**", "*.rb")).sort.each do |f|
        rel = f.sub(d + "/", "")
        puts "#{rel}\t#{f}"
      end
    ' "$name" 2>/dev/null
    ;;
  url)
    mode="$2"; name="$3"
    if [ "$mode" = registry ]; then
      echo "https://rubygems.org/gems/$name"
    else
      u=$(ruby -e 'require "rubygems"; begin; puts Gem::Specification.find_by_name(ARGV[0]).homepage; rescue Exception; end' "$name" 2>/dev/null)
      [ -z "$u" ] && u="https://www.rubydoc.info/gems/$name"
      echo "$u"
    fi
    ;;
  help)
    name="$2"
    d=$(ruby -e 'require "rubygems"; begin; puts Gem::Specification.find_by_name(ARGV[0]).gem_dir; rescue Exception; end' "$name" 2>/dev/null)
    rm=$(ls "$d"/README* "$d"/readme* 2>/dev/null | head -1)
    if [ -n "$rm" ]; then cat "$rm"; else echo "No README bundled for $name."; fi
    ;;
esac
BACKEND
  chmod +x /tmp/gembrowse-backend.sh
}
