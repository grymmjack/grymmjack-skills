#!/usr/bin/env bash
# install-from-mapping.sh — Copy scavenged audio into a destination, renamed to
# <slot>.<ext>, and write a MANIFEST.tsv recording where each file came from.
#
# Usage:  install-from-mapping.sh MAPPING_TSV DEST_DIR
#
# MAPPING_TSV: tab-separated, one slot per line:
#     <slot_name>\t<absolute_source_path>
# Blank lines and lines starting with # are ignored. The slot name becomes the
# output filename; the source extension is preserved.
#
# Reports duration (via ffprobe, if present) and flags any missing sources so
# unfilled slots are obvious — those are the ones to make in sfxr/custom.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 MAPPING_TSV DEST_DIR" >&2
  exit 2
fi

map="$1"; dest="$2"
[ -f "$map" ] || { echo "mapping not found: $map" >&2; exit 1; }
mkdir -p "$dest"
man="$dest/MANIFEST.tsv"
printf 'effect\tfile\tduration_s\tsource_path\n' > "$man"

have_ffprobe=0; command -v ffprobe >/dev/null 2>&1 && have_ffprobe=1
n=0; miss=0
while IFS=$'\t' read -r name src rest; do
  [ -z "${name:-}" ] && continue
  case "$name" in \#*) continue;; esac
  if [ ! -f "${src:-}" ]; then
    printf '  !! MISSING  %-14s <- %s\n' "$name" "${src:-<empty>}"
    miss=$((miss+1)); continue
  fi
  ext="${src##*.}"
  cp -f "$src" "$dest/$name.$ext"
  dur="?"
  [ "$have_ffprobe" = 1 ] && dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$src" 2>/dev/null | cut -c1-6)
  printf '%s\t%s.%s\t%s\t%s\n' "$name" "$name" "$ext" "${dur:-?}" "$src" >> "$man"
  n=$((n+1))
done < "$map"

echo "installed $n file(s); $miss missing -> $dest"
echo "manifest: $man"
if command -v column >/dev/null 2>&1; then column -t -s$'\t' "$man"; fi
