#!/usr/bin/env bash
# pybrowse — a fuzzy Python-environment browser (fzf + bat).
#
# Install: source this file from your shell rc (bash or zsh), then run `pybrowse`.
#   echo 'source /path/to/pybrowse.sh' >> ~/.zshrc     # or ~/.bashrc
#   pybrowse                 # browse the active environment's packages
#   pybrowse /venv/bin/python  # target a specific interpreter / venv
#
# Requires: fzf, python3 (or python). Optional: bat/batcat for the source
# preview (falls back to cat). See SKILL.md for keys and behaviour.

# ─────────────────────────────────────────────────────────────────────────
# pybrowse — introspect a Python environment the same fuzzy way brewbrowse
# introspects Homebrew. Level 1 is the installed-package list (pip's world,
# read fast in one process via importlib.metadata): each row is
# "<name> <version> <summary>". The preview pane shows the full metadata
# (summary, homepage, docs, requires, required-by, install location, source
# files). Level 2 is reached with ENTER: it drills into the package's own
# .py source tree with a bat preview, so you can actually read what a
# dependency is made of. ESC pops level 2 back to the package list, and ESC
# on the list quits.
#
# Keys are Alt-chords, NOT plain w/d/h, on purpose: plain letters would be
# swallowed by fzf's type-to-filter search box (the whole point of the list).
#   Alt-W  open the package's PyPI page   (https://pypi.org/project/<name>/)
#   Alt-D  open its documentation/homepage (from the package metadata)
#   Alt-H  pydoc help() for the package    (paged through $PAGER/less)
#
# Works against whichever interpreter is active: `pybrowse` uses python3 on
# PATH (so an activated venv is respected); `pybrowse /path/to/venv/bin/python`
# or `pybrowse python3.12` targets a specific one.
# ─────────────────────────────────────────────────────────────────────────

# The metadata backend. One Python file, several sub-commands, invoked under
# the *target* interpreter so it sees that environment's packages:
#   list        → "<name> <version> <summary>" rows, ANSI-colored
#   show <name> → full metadata block for the preview pane
#   files <name>→ absolute paths of the package's .py source files
#   url <name>  → best docs/homepage URL (for Alt-D)
#   help <name> → pydoc text for the package's importable top-level module
_py_ensure_meta() {
  local helper=/tmp/pybrowse-meta.py
  cat >"$helper" <<'PYEOF'
import sys, os, re
import importlib.metadata as im

Y = "\033[33m"; DIM = "\033[2m"; C = "\033[36m"; W = "\033[1;37m"
B = "\033[1;34m"; G = "\033[0;32m"; R = "\033[0m"

def _dist(name):
    return im.distribution(name)

def _urls(m):
    """Return (homepage, docs) mined from Home-page + Project-URL."""
    home = (m["Home-page"] or "").strip()
    docs = ""
    for entry in (m.get_all("Project-URL") or []):
        label, _, u = entry.partition(",")
        label = label.strip().lower(); u = u.strip()
        if not u:
            continue
        if any(k in label for k in ("doc",)):
            docs = docs or u
        if not home and label in ("homepage", "home", "home-page", "source"):
            home = u
    return home, docs

def cmd_list():
    rows, seen = [], set()
    for dist in im.distributions():
        try:
            name = dist.metadata["Name"]
            ver = dist.version or "?"
            summ = (dist.metadata["Summary"] or "").strip().replace("\n", " ")
        except Exception:
            continue
        if not name:
            continue
        key = name.lower()
        if key in seen:
            continue
        seen.add(key)
        rows.append((key, name, ver, summ))
    for _, name, ver, summ in sorted(rows):
        if len(summ) > 100:
            summ = summ[:97] + "..."
        # ANSI-colored; name stays the first whitespace token for extraction.
        print(f"{Y}{name}{R} {DIM}{ver}{R}  {C}{summ}{R}")

def cmd_show(name):
    try:
        d = _dist(name)
    except Exception:
        print(f"{R}Package not found: {name}"); return
    m = d.metadata
    home, docs = _urls(m)
    loc = ""
    try:
        loc = str(d.locate_file(""))
    except Exception:
        pass
    reqs = []
    for r in (d.requires or []):
        # Hide the extras-only optional deps; keep the real runtime ones.
        if "extra ==" in r:
            continue
        mm = re.match(r"\s*([A-Za-z0-9][A-Za-z0-9._-]*)", r)
        if mm:
            reqs.append(mm.group(1))
    def line(label, val, color=""):
        if not val:
            return
        print(f"{W}{label:<12}{R}{color}{val}{R}")
    print(f"{W}{m['Name']} {DIM}{d.version}{R}")
    print()
    line("Summary", (m["Summary"] or "").strip())
    print()
    line("Homepage", home or "(none)", B)
    line("Docs", docs or "(none)", B)
    line("PyPI", f"https://pypi.org/project/{m['Name']}/", B)
    line("License", (m["License"] or m["License-Expression"] or "").strip()[:60])
    line("Author", (m["Author"] or m["Author-email"] or "").strip()[:60])
    print()
    line("Location", loc)
    if reqs:
        print(f"{W}Requires{R}    {C}{', '.join(sorted(reqs))}{R}")
    # Required-by: which installed dists depend on this one.
    dependents = _dependents(m["Name"])
    if dependents:
        print(f"{W}Required-by{R}  {C}{', '.join(dependents)}{R}")
    files = _pyfiles(d)
    if files:
        print()
        print(f"{W}Source files ({len(files)}){R}  {DIM}ENTER to browse{R}")
        for f in files[:12]:
            print(f"  {G}{os.path.basename(f)}{R}")
        if len(files) > 12:
            print(f"  {DIM}... and {len(files) - 12} more{R}")

def _req_name(r):
    """Leading distribution name of a requirement string, normalized."""
    m = re.match(r"\s*([A-Za-z0-9][A-Za-z0-9._-]*)", r)
    return m.group(1).lower().replace("_", "-") if m else ""

def _dependents(name):
    target = name.lower().replace("_", "-")
    out = []
    for dist in im.distributions():
        try:
            dn = dist.metadata["Name"]
            for r in (dist.requires or []):
                if "extra ==" in r:
                    continue
                if _req_name(r) == target:
                    out.append(dn); break
        except Exception:
            continue
    return sorted(set(out))

def _pyfiles(d):
    """Absolute .py paths owned by this distribution (RECORD, else top_level walk)."""
    paths = []
    try:
        if d.files:
            for p in d.files:
                if p.suffix == ".py":
                    paths.append(os.path.realpath(str(d.locate_file(p))))
    except Exception:
        pass
    if not paths:
        try:
            base = str(d.locate_file(""))
            tops = (d.read_text("top_level.txt") or "").split()
            for t in tops:
                tdir = os.path.join(base, t)
                if os.path.isdir(tdir):
                    for root, _, fs in os.walk(tdir):
                        for f in fs:
                            if f.endswith(".py"):
                                paths.append(os.path.join(root, f))
                elif os.path.isfile(tdir + ".py"):
                    paths.append(tdir + ".py")
        except Exception:
            pass
    return sorted(set(p for p in paths if os.path.isfile(p)))

def cmd_files(name):
    try:
        d = _dist(name)
    except Exception:
        return
    try:
        base = os.path.realpath(str(d.locate_file("")))
    except Exception:
        base = ""
    for f in _pyfiles(d):
        rf = os.path.realpath(f)
        # Show only the package-relative path (macholib/dyld.py); keep the
        # absolute path in a second, tab-separated field for preview + editor.
        disp = os.path.relpath(rf, base) if base else os.path.basename(rf)
        if disp.startswith(".."):
            disp = os.path.basename(rf)
        print(f"{disp}\t{rf}")

def cmd_url(name):
    try:
        m = _dist(name).metadata
    except Exception:
        return
    home, docs = _urls(m)
    print(docs or home or f"https://pypi.org/project/{name}/")

def cmd_help(name):
    import importlib, pydoc
    try:
        d = _dist(name)
        tops = (d.read_text("top_level.txt") or "").split()
    except Exception:
        tops = []
    # Drop compiled/mangled artifacts (e.g. mypyc "<hash>__mypyc" modules) and
    # prefer the module whose name matches the package's own name.
    tops = [t for t in tops if "__mypyc" not in t and not t.endswith("__mypyc")]
    if not tops:
        tops = [name.replace("-", "_"), name]
    norm = name.lower().replace("-", "_")
    tops.sort(key=lambda t: 0 if t.lower().replace("-", "_") == norm else 1)
    target = None
    for t in tops:
        try:
            importlib.import_module(t); target = t; break
        except Exception:
            continue
    if not target:
        print(f"Could not import a module for '{name}'. Top-level candidates: "
              f"{', '.join(tops) or '(none)'}")
        return
    print(pydoc.render_doc(target, renderer=pydoc.plaintext))

def main():
    if len(sys.argv) < 2:
        return
    cmd = sys.argv[1]
    arg = sys.argv[2] if len(sys.argv) > 2 else ""
    if cmd == "list":
        cmd_list()
    elif cmd == "show":
        cmd_show(arg)
    elif cmd == "files":
        cmd_files(arg)
    elif cmd == "url":
        cmd_url(arg)
    elif cmd == "help":
        cmd_help(arg)

if __name__ == "__main__":
    main()
PYEOF
}

# URL opener, detached so it survives fzf's execute-silent teardown (same
# approach as brewfzf-open). Args: <pybin> <pypi|docs> <fzf-line>. Strips the
# ANSI from the line, takes the first token as the package name, resolves the
# URL, and hands it to the OS opener fully backgrounded.
_py_ensure_open() {
  local helper=/tmp/pybrowse-open.sh
  cat >"$helper" <<'PYEOF'
#!/usr/bin/env bash
pybin="$1"; mode="$2"; shift 2
line="$*"
name=$(printf '%s' "$line" | sed 's/\x1b\[[0-9;]*m//g' | awk '{print $1}')
[ -z "$name" ] && exit 0
if [ "$mode" = "pypi" ]; then
  url="https://pypi.org/project/$name/"
else
  url=$("$pybin" /tmp/pybrowse-meta.py url "$name" 2>/dev/null)
fi
[ -z "$url" ] && url="https://pypi.org/project/$name/"
if [ "$(uname)" = "Darwin" ]; then opener=open; else opener=xdg-open; fi
nohup "$opener" "$url" >/dev/null 2>&1 &
PYEOF
  chmod +x "$helper"
}

# Pick a syntax-highlighting pager for the level-2 source preview: bat on
# macOS/Homebrew, batcat on Debian/Ubuntu, plain cat as a last resort.
_py_batcmd() {
  if command -v bat >/dev/null 2>&1; then
    echo 'bat --color=always --style=numbers --paging=never'
  elif command -v batcat >/dev/null 2>&1; then
    echo 'batcat --color=always --style=numbers --paging=never'
  else
    echo 'cat'
  fi
}

# Level 2: browse one package's .py source files with a bat preview.
# ENTER opens the file in $EDITOR; ESC returns to the package list.
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

_pybrowse_files() {
  local pybin="$1" pkg="$2"
  local files
  files=$("$pybin" /tmp/pybrowse-meta.py files "$pkg")
  if [ -z "$files" ]; then
    echo "No .py source files found for $pkg (may be a compiled/namespace package)."
    sleep 1.2
    return
  fi
  local batcmd; batcmd=$(_py_batcmd)
  _pkgbrowse_ensure_outline
  echo "$files" | fzf \
    --style full \
    --ansi \
    --reverse \
    --border \
    --padding 1,2 \
    --delimiter='\t' \
    --with-nth=1 \
    --border-label="🐍 $pkg — source" \
    --list-label="$pkg .py files" \
    --preview-label='source' \
    --preview "$batcmd {2} 2>/dev/null | head -400" \
    --preview-window='right,70%' \
    --bind "enter:execute(\${EDITOR:-vim} {2})" \
    --bind 'focus:transform-header:echo {2}' \
    --bind 'ctrl-o:execute(bash /tmp/pkgbrowse-outline.sh {2})' \
    --footer='ENTER edit · Ctrl-O outline · ESC back'
}

pybrowse() {
  local pybin="${1:-}"
  if [ -z "$pybin" ]; then
    if command -v python3 >/dev/null 2>&1; then pybin=python3
    elif command -v python >/dev/null 2>&1; then pybin=python
    else echo "pybrowse: no python3/python on PATH"; return 1; fi
  fi
  if ! command -v fzf >/dev/null 2>&1; then
    echo "pybrowse: fzf is required"; return 1
  fi
  _py_ensure_meta
  _py_ensure_open

  local list_cmd="$pybin /tmp/pybrowse-meta.py list"
  # Outer loop: package list. ENTER drills into the selected package's source
  # (level 2); when that returns we loop back to the list. ESC quits.
  while true; do
    local sel
    sel=$(eval "$list_cmd" | fzf \
      --style full \
      --ansi \
      --reverse \
      --border \
      --padding 1,2 \
      --border-label='🐍 python env browser' \
      --list-label="$($pybin -c 'import sys;print(sys.version.split()[0])' 2>/dev/null | sed 's/^/python /')" \
      --preview-label='package info' \
      --preview "pkg=\$(printf '%s' {} | sed 's/\x1b\[[0-9;]*m//g' | awk '{print \$1}'); $pybin /tmp/pybrowse-meta.py show \"\$pkg\"" \
      --preview-window='right,55%' \
      --bind "alt-w:execute-silent(/tmp/pybrowse-open.sh $pybin pypi {})" \
      --bind "alt-d:execute-silent(/tmp/pybrowse-open.sh $pybin docs {})" \
      --bind "alt-h:execute(pkg=\$(printf '%s' {} | sed 's/\x1b\[[0-9;]*m//g' | awk '{print \$1}'); $pybin /tmp/pybrowse-meta.py help \"\$pkg\" | \${PAGER:-less -R})" \
      --bind 'focus:transform-header:
        line=$(printf "%s" {} | sed "s/\x1b\[[0-9;]*m//g");
        pkg=$(echo "$line" | awk "{print \$1}");
        rest=$(echo "$line" | cut -d" " -f2-);
        echo -e "\033[1;33m$pkg\033[0m";
        echo -e "\033[0;36m$rest\033[0m"' \
      --footer='ENTER browse source · Alt-W PyPI · Alt-D docs · Alt-H help() · ESC quit')
    [ -z "$sel" ] && break
    local pkg
    pkg=$(printf '%s' "$sel" | sed 's/\x1b\[[0-9;]*m//g' | awk '{print $1}')
    [ -z "$pkg" ] && break
    _pybrowse_files "$pybin" "$pkg"
  done
}

