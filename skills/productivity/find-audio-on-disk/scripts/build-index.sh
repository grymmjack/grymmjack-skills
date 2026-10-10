#!/usr/bin/env bash
# build-index.sh — Build a flat index of audio files (absolute paths, one per line).
#
# Usage:  build-index.sh OUTPUT_INDEX DIR [DIR ...]
# Example: build-index.sh /tmp/audio_index.txt /mnt/music "/mnt/backup/Sound FX"
#
# Prefers `fd` (fast) and falls back to `find`. Handles spaces in paths.
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "usage: $0 OUTPUT_INDEX DIR [DIR ...]" >&2
  exit 2
fi

out="$1"; shift
exts=(wav ogg mp3 flac aif aiff)
: > "$out"

if command -v fd >/dev/null 2>&1; then
  fdargs=(); for e in "${exts[@]}"; do fdargs+=(-e "$e"); done
  for d in "$@"; do
    [ -d "$d" ] || { echo "  (skip, not a dir) $d" >&2; continue; }
    fd "${fdargs[@]}" . "$d" >> "$out" 2>/dev/null || true
  done
else
  fexpr=(); for e in "${exts[@]}"; do fexpr+=(-iname "*.$e" -o); done
  unset 'fexpr[${#fexpr[@]}-1]'   # drop trailing -o
  for d in "$@"; do
    [ -d "$d" ] || { echo "  (skip, not a dir) $d" >&2; continue; }
    find "$d" -type f \( "${fexpr[@]}" \) >> "$out" 2>/dev/null || true
  done
fi

sort -u -o "$out" "$out"
echo "indexed $(wc -l < "$out") audio files -> $out"
