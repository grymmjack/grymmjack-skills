#!/usr/bin/env bash
set -euo pipefail

# Links every skill in this repo into the local skill directories:
#   - ~/.claude/skills  — Claude Code
#   - ~/.agents/skills  — other Agent-Skills-standard harnesses
# Each entry is a symlink into this repo, so a `git pull` keeps them current.
#
# An existing symlink is replaced. An existing real directory is left alone
# (it may be managed by something else, e.g. chezmoi) unless --force is given.
#
# Usage: scripts/link-skills.sh [--force]

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DESTS=("$HOME/.claude/skills" "$HOME/.agents/skills")
FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

skipped=0
while IFS= read -r -d '' skill_md; do
  src="$(dirname "$skill_md")"
  name="$(basename "$src")"
  for dest in "${DESTS[@]}"; do
    mkdir -p "$dest"
    target="$dest/$name"
    if [ -e "$target" ] && [ ! -L "$target" ]; then
      if [ "$FORCE" -eq 1 ]; then
        rm -rf "$target"
      else
        echo "skip   $target (real directory; re-run with --force to replace)"
        skipped=$((skipped + 1))
        continue
      fi
    fi
    ln -sfn "$src" "$target"
    echo "linked $target -> $src"
  done
done < <(find "$REPO/skills" -name SKILL.md -not -path '*/node_modules/*' -print0)

[ "$skipped" -eq 0 ] || echo "$skipped skipped."
