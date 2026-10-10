#!/usr/bin/env bash
# task-loop-write-guard.sh — PreToolUse hook: hide a checklist that a DIFFERENT
# session has armed. Not just writes — reads too. 2026-08-06
#
# Registered on PreToolUse for Read|Edit|Write|MultiEdit|NotebookEdit|Grep|Glob.
#   exit 2 -> the tool call is BLOCKED and stderr is handed to Claude
#   exit 0 -> allowed
#
# WHY THIS EXISTS (observed 2026-08-06): task-loop-guard.sh is armed per session,
# but it only ever READS the checklist — it cannot add tasks. The writing is done
# by Claude, on instructions from the task-loop SKILL, and skill loading is not
# gated by arming. So a second session that happened to trigger the skill started
# appending to a checklist another session was actively working. The hook was
# enforced; the skill was merely advice. This closes that half.
#
# THE RULE — deliberately narrow, so ordinary work is untouched:
#
#   nobody has armed this file      -> ALLOW. It is just a file. Creating a new
#                                     checklist, or editing one nobody is looping
#                                     on, must keep working.
#   THIS session armed it           -> ALLOW. It owns the run.
#   ANOTHER session armed it        -> BLOCK, reads included. A session that can
#                                     read someone else's list starts "helping"
#                                     with it; concealing it removes the
#                                     temptation rather than relying on restraint.
#
# Bash is gated too: a command that NAMES a claimed checklist (`cat .../TASKS.md`,
# `grep x .claude/TASKS.md`, `sed -i ... TASKS.md`) is blocked, so Read being
# closed cannot simply be routed around with a shell.
#
# WHAT IT STILL CANNOT HIDE, stated plainly so nobody trusts it too far:
#   * a command that reaches the file WITHOUT naming it — `grep -r foo <repo>`, or
#     a script whose paths are internal (this is deliberate: it is what lets a
#     generator script keep rewriting a derived checklist)
#   * a Grep/Glob whose path is a PARENT directory; blocking those would take out
#     every repo-wide search in the project, which is too much collateral
#   * the file open in an editor tab, or listed in its explorer
# For a list that must be truly invisible to other sessions, put it somewhere they
# have no reason to look — the arm pins any absolute path, so it does not have to
# live in a shared project directory at all.
#
# Protection is driven entirely by what is actually armed — there is no filename
# heuristic — so a checklist called something other than TASKS.md is protected
# once armed, and an unarmed TASKS.md is never in the way.
#
# NOT covered on purpose: writes made through Bash (a generator script
# regenerating a derived checklist). Those are the legitimate
# writer for a derived list, and blocking them would break the very workflow the
# loop is meant to drive.
#
# Escape hatch: CLAUDE_TASK_NO_WRITE_GUARD=1 disables it entirely.

set -uo pipefail

# CLAUDE_TASK_NO_GUARD is the current name; the older WRITE_ variant still works.
[ -n "${CLAUDE_TASK_NO_GUARD:-${CLAUDE_TASK_NO_WRITE_GUARD:-}}" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0     # cannot parse the payload -> allow

state_dir="${XDG_CACHE_HOME:-$HOME/.claude/cache}/task-loop"
payload="$(cat)"

jqv() { printf '%s' "$payload" | jq -r "$1 // empty" 2>/dev/null; }

sid="$(jqv '.session_id')"
cwd="$(jqv '.cwd')"; [ -n "$cwd" ] || cwd="$PWD"
tool="$(jqv '.tool_name')"

# Only ever gate WRITES. The registered matcher already excludes Read, but this
# must not depend on the matcher staying correct — a guard that could block reads
# because someone widened a regex is a guard that will eventually break work.
case "$tool" in
  Read|Edit|Write|MultiEdit|NotebookEdit|Grep|Glob|Bash) ;;
  *) exit 0 ;;
esac

# Collect every checklist claimed by a session OTHER than this one.
foreign=""
for f in "$state_dir"/armed-"$sid" ; do :; done   # (no-op; keeps shellcheck quiet)
for f in "$state_dir"/armed-*; do
  [ -e "$f" ] || continue
  o="$(basename "$f")"; o="${o#armed-}"
  [ "$o" = "$sid" ] && continue
  pin="$(head -1 "$f" 2>/dev/null)"
  [ -n "$pin" ] && foreign="$foreign$pin"$'\n'
done

# ---- Bash: block any command that NAMES a foreign checklist -----------------
if [ "$tool" = "Bash" ]; then
  [ -n "$foreign" ] || exit 0
  cmd="$(jqv '.tool_input.command')"
  [ -n "$cmd" ] || exit 0
  hit=""; owner_of_hit=""
  while IFS= read -r pin; do
    [ -n "$pin" ] || continue
    # The absolute path always counts. A RELATIVE form only counts when the
    # foreign checklist actually lives under this session's cwd — otherwise a
    # tail like ".claude/TASKS.md" would match every project's checklist and
    # block a session from touching its OWN list. (Observed 2026-08-06: with
    # one project's list armed, an unrelated repo's .claude/TASKS.md was blocked.)
    case "$cmd" in *"$pin"*) hit="$pin" ;; esac
    if [ -z "$hit" ]; then
      case "$pin" in
        "$cwd"/*)
          rel="${pin#"$cwd"/}"
          case "$cmd" in *"$rel"*) hit="$pin" ;; esac
          ;;
      esac
    fi
    [ -n "$hit" ] && break
  done <<< "$foreign"
  [ -n "$hit" ] || exit 0
  for f in "$state_dir"/armed-*; do
    [ -e "$f" ] || continue
    [ "$(head -1 "$f" 2>/dev/null)" = "$hit" ] || continue
    o="$(basename "$f")"; owner_of_hit="${o#armed-}"
  done
  printf '%s  %s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${sid:0:8}" \
    "BLOCKED Bash naming $hit — armed by ${owner_of_hit%%-*}" \
    >> "$state_dir/events.log" 2>/dev/null || true
  cat >&2 <<BASHEOF
BLOCKED (Bash): that command names $hit, which belongs to another Claude
session's task loop (session: ${owner_of_hit%%-*}).

That checklist is off-limits to this session — no read, no write, no shell access.
Do NOT retry, and do NOT reach it another way. Tell the user you were blocked.
BASHEOF
  exit 2
fi

target="$(jqv '.tool_input.file_path')"
[ -n "$target" ] || target="$(jqv '.tool_input.notebook_path')"
# Grep/Glob carry .path. Only an EXACT file match is interceptable — a path that
# is a directory is left alone rather than blocking whole trees.
[ -n "$target" ] || target="$(jqv '.tool_input.path')"
[ -n "$target" ] || exit 0                  # nothing file-shaped -> allow

# Resolve to an absolute path without needing realpath (absent on some systems).
case "$target" in
  /*) ;;
  *)  target="$cwd/$target" ;;
esac
t_dir="$(dirname "$target")"; t_base="$(basename "$target")"
[ -d "$t_dir" ] && target="$(cd "$t_dir" && pwd)/$t_base"

# Who, if anyone, has armed exactly this file?
owners=""
for f in "$state_dir"/armed-*; do
  [ -e "$f" ] || continue
  pinned="$(head -1 "$f" 2>/dev/null)"
  [ "$pinned" = "$target" ] || continue
  owner="$(basename "$f")"; owner="${owner#armed-}"
  owners="$owners $owner"
done

[ -n "$owners" ] || exit 0                              # unclaimed -> allow
case " $owners " in *" $sid "*) exit 0 ;; esac           # we own it -> allow

# Someone else is looping on this file. Block, name the owner, offer the outs.
short=""
for o in $owners; do short="$short ${o%%-*}"; done
printf '%s  %s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${sid:0:8}" \
  "BLOCKED write to $target — armed by:$short" >> "$state_dir/events.log" 2>/dev/null || true

cat >&2 <<EOF
BLOCKED ($tool): $target belongs to another Claude session's task loop
(session:$short). This session is not armed for it, so it is off-limits —
reads included, not only writes.

Treat that file as if it does not exist. Do NOT retry, do NOT try another route to
its contents, and do NOT work any item from it. Two sessions sharing one checklist
is how four items got done twice in twenty minutes.

  * Something to add to that list? Put it in your reply and let the user relay it.
  * Meant to take over the run? That is the user's call, not yours:
      ~/.claude/hooks/task-loop-guard.sh --disarm --session $short
      ~/.claude/hooks/task-loop-guard.sh --arm $target
  * Need your OWN checklist? Use a different path and arm this session for it.

Tell the user you were blocked and why. Do not work around it.
EOF
exit 2
