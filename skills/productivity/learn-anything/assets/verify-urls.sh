#!/usr/bin/env bash
# verify-urls.sh — check every http(s) URL linked in this workspace actually resolves.
# Belongs at the WORKSPACE ROOT (next to build-docs.sh). Run before committing docs:
#     bash verify-urls.sh
# Scans *.md (incl. learning-records/) and hand-authored *.html (index/lessons/reference),
# skipping assets/ and lab/. bash 3.2 compatible (no mapfile/readarray).
#
# Exit status: 0 if all URLs OK; 1 if any FAIL or SUSPECT (so it can gate a commit).
#
# Why this exists: a link can return HTTP 200 yet be dead — many sites 301 a moved/
# missing page to their home page, which then 200s. This script flags that case
# (SUSPECT: "redirect collapsed a real path to '/'") in addition to hard 4xx/5xx/000.
set -uo pipefail

WS="$(cd "$(dirname "$0")" && pwd)"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Safari/537.36"

# path portion of a URL: drop scheme+host, keep from first '/'. "" or "/" == root.
url_path() { printf '%s' "$1" | sed -E 's#^[a-z]+://[^/]+##; s#\?.*$##; s#\#.*$##'; }

# Gather source files (portable; no -print0 needed for these paths).
files=()
while IFS= read -r f; do files+=("$f"); done < <(
  find "$WS" -type f \( -name '*.md' -o -name '*.html' \) \
    -not -path "$WS/assets/*" -not -path "$WS/lab/*" | sort
)

# Extract + dedupe URLs from those files. Trailing markdown/HTML/punct stripped.
urls=()
while IFS= read -r u; do
  [ -n "$u" ] && urls+=("$u")
done < <(
  grep -rhoE 'https?://[^[:space:]<>"]+' "${files[@]}" 2>/dev/null \
    | sed -E "s/['\").,;:]+$//" \
    | sort -u
)

echo "verify-urls: ${#urls[@]} unique URLs across ${#files[@]} files under $(basename "$WS")/"
echo "--------------------------------------------------------------------------------"
fails=0
for u in "${urls[@]}"; do
  out="$(curl -sS -A "$UA" -L --max-time 25 -o /dev/null \
        -w '%{http_code} %{url_effective}' "$u" 2>/dev/null)"
  code="${out%% *}"; final="${out#* }"; code="${code:-000}"
  reqp="$(url_path "$u")"; finp="$(url_path "$final")"
  mark="ok   "; bad=0
  case "$code" in
    2*)
      # 200 but a non-root path collapsed to root/empty on the final URL == silent dead link
      if [ "$reqp" != "" ] && [ "$reqp" != "/" ] && { [ "$finp" = "" ] || [ "$finp" = "/" ]; }; then
        mark="SUSPT"; bad=1
      fi ;;
    3*) mark="redir" ;;                 # -L should resolve these; a bare 3xx final is odd
    000) mark="FAIL "; bad=1 ;;
    *)   mark="FAIL "; bad=1 ;;         # 4xx / 5xx
  esac
  note=""; [ "$u" != "$final" ] && note="   -> $final"
  printf '%s %-4s %s%s\n' "$mark" "$code" "$u" "$note"
  [ "$bad" -eq 1 ] && fails=$((fails+1))
done
echo "--------------------------------------------------------------------------------"
if [ "$fails" -gt 0 ]; then
  echo "FAILED: $fails URL(s) are dead or silently redirected. Fix or remove before committing."
  exit 1
fi
echo "All URLs resolve cleanly."
