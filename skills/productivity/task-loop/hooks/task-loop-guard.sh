#!/usr/bin/env bash
# task-loop-guard.sh — Stop hook: refuse to end the turn while an ARMED session's
# on-disk checklist still has unchecked boxes and progress is still being made.
# Ships with the task-loop skill; install into ~/.claude/hooks/. 2026-08-06
#
# WHY A HOOK AND NOT A SKILL OR A PROMPT: a turn ends when the model emits no
# tool call. There is no action to forbid, so no instruction reliably prevents
# it — "don't stop until done" competes against a structural default and loses,
# especially after a compaction has summarized the instruction away. This hook
# fires *after* Claude has decided to stop and vetoes the decision:
#   exit 2  -> stop is blocked, stderr is handed to Claude as its instructions
#   exit 0  -> stop is allowed
# The principle: enforce in the harness, don't ask.
#
# ═══ OPT-IN IS PER SESSION, NOT PER DIRECTORY ═══════════════════════════════
# This hook does NOTHING unless the current session has been explicitly armed:
#
#     task-loop-guard.sh --arm [/path/to/TASKS.md]   # arm THIS session
#     task-loop-guard.sh --disarm                    # stop the loop
#     task-loop-guard.sh --status                    # is this session armed?
#
# Arming keys off $CLAUDE_CODE_SESSION_ID (a UUID, unique per session, stable
# across compaction and `claude --resume`), and the arm file PINS the absolute
# checklist path.
#
# WHY (regression observed 2026-08-06): the previous version engaged whenever it
# *found* a checklist — $cwd/.claude/TASKS.md, or $CLAUDE_PROJECT_DIR/... . That
# conscripted EVERY session touching the project into working the list, including
# one opened to ask an unrelated question, and $CLAUDE_PROJECT_DIR let it reach
# across projects entirely. One bystander session burned 35 minutes and 127.6k
# tokens being force-continued through a checklist it never agreed to work.
# "A checklist exists nearby" is not "this session agreed to work it."
# Pinning the path also means an armed session cannot be redirected onto a
# different list mid-run by a cwd or CLAUDE_PROJECT_DIR change.
#
# CHECKLIST FORMAT (GitHub-style task list, any indent, - or *):
#   - [ ] not done
#   - [x] done
#   - [ ] ⛔ **BLOCKED** · item ⟵ why   <- stays OPEN: a checked box means done
#   - [x] BLOCKED: reason              <- legacy form; still triaged at the end
#
# ESCAPE HATCHES (any one of these ends the loop):
#   * --disarm                       (surgical: this session only)
#   * every box checked              (auto-disarms)
#   * a line containing  loop:off    anywhere in the checklist
#   * delete or rename the checklist
#   * MAX_STALLS consecutive stops with nothing newly checked (anti-spin)
#   * Esc / Ctrl-C — a user interrupt is not a Stop event, so it always wins

set -uo pipefail

# Consecutive turn-ends with zero progress before standing down. Progress means
# the unchecked count went DOWN. This asymmetry is the core of the design:
# forward motion earns unlimited continuations, spinning in place does not.
MAX_STALLS="${CLAUDE_TASK_MAX_STALLS:-3}"

# Consecutive unreadable-checklist observations before concluding it is really
# gone. Generators rewrite derived checklists in place, so 1 is far too eager.
MISS_LIMIT="${CLAUDE_TASK_MISS_LIMIT:-3}"

state_dir="${XDG_CACHE_HOME:-$HOME/.claude/cache}/task-loop"
mkdir -p "$state_dir" 2>/dev/null || true

# Every state change gets a reason on disk. Today's whole class of bug was
# failing SILENTLY — an arm would vanish and nobody could say why. `--status`
# replays the tail of this.
log_event() {
  printf '%s  %s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${1:0:8}" "$2" \
    >> "$state_dir/events.log" 2>/dev/null || true
}

open_count() { grep -c -iE '^[[:space:]]*[-*][[:space:]]+\[[[:space:]]*\]' "$1" 2>/dev/null || true; }
done_count() { grep -c -iE '^[[:space:]]*[-*][[:space:]]+\[[xX]\]'          "$1" 2>/dev/null || true; }
blkd_count() { grep -c -iE '^[[:space:]]*[-*][[:space:]]+\[[xX]\][[:space:]]*BLOCKED' "$1" 2>/dev/null || true; }

# Locate a checklist relative to a directory. Used ONLY when arming — the hook
# path always uses the pinned path from the arm file.
discover() {
  local base="$1" cand
  for cand in "$base/.claude/TASKS.md" "$base/TASKS.md"; do
    [ -f "$cand" ] && { printf '%s' "$cand"; return 0; }
  done
  return 1
}

# ─── subcommands ────────────────────────────────────────────────────────────
# Handled BEFORE reading stdin: these are run interactively and there is no hook
# payload to consume, so a `cat` here would hang waiting for input.
case "${1:-}" in
  --arm|--disarm|--status|--sessions|--owns)
    sub="$1"; shift
    # Optional args in any order: a checklist path, and/or --session <id>.
    tasks_arg=""; sid_arg=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --session)   sid_arg="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
        --session=*) sid_arg="${1#--session=}"; shift ;;
        *)           [ -z "$tasks_arg" ] && tasks_arg="$1"; shift ;;
      esac
    done

    # Claude Code names each session's transcript <session-id>.jsonl inside a
    # per-cwd directory whose name is the absolute path with / replaced by -.
    # That lets a plain shell discover ids it cannot read from the environment.
    proj_dir_for() { printf '%s' "$HOME/.claude/projects/$(printf '%s' "$1" | sed 's|/|-|g')"; }

    if [ "$sub" = "--sessions" ]; then
      base="${tasks_arg:-$PWD}"
      d="$(proj_dir_for "$base")"
      echo "sessions recorded for: $base"
      echo "  ($d)"
      if [ -d "$d" ] && ls "$d"/*.jsonl >/dev/null 2>&1; then
        # shellcheck disable=SC2012
        ls -t "$d"/*.jsonl 2>/dev/null | head -10 | while read -r f; do
          printf '  %s   %s\n' "$(basename "$f" .jsonl)" \
            "$(date -r "$f" '+%Y-%m-%d %H:%M' 2>/dev/null)"
        done
        echo "  newest first — the top entry is usually the live session."
        echo "  arm it with: $0 --arm <checklist> --session <ID>"
      else
        echo "  (none — no Claude Code session has run with that as its cwd)"
        echo "  NOTE: in a multi-root VS Code workspace the session's cwd is the"
        echo "        FIRST folder, so try that path rather than this one."
      fi
      exit 0
    fi

    if [ "$sub" = "--owns" ]; then
      # Who is armed for a given checklist? Exits 0 only if THIS session owns it,
      # so a skill can gate its own writes instead of trusting prose.
      want="${tasks_arg:-}"
      [ -n "$want" ] || { echo "usage: $0 --owns /path/to/TASKS.md" >&2; exit 2; }
      case "$want" in /*) ;; *) want="$PWD/$want" ;; esac
      wd="$(dirname "$want")"; wb="$(basename "$want")"
      [ -d "$wd" ] && want="$(cd "$wd" && pwd)/$wb"
      me="${sid_arg:-${CLAUDE_TASK_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-}}}"
      owners=""
      for f in "$state_dir"/armed-*; do
        [ -e "$f" ] || continue
        [ "$(head -1 "$f" 2>/dev/null)" = "$want" ] || continue
        o="$(basename "$f")"; owners="$owners ${o#armed-}"
      done
      if [ -z "$owners" ]; then
        echo "unclaimed: no session is armed for $want"; exit 1
      fi
      for o in $owners; do
        if [ "$o" = "$me" ]; then echo "OWNED BY THIS SESSION: $want"; exit 0; fi
      done
      echo "owned by another session:$owners"
      echo "  -> do not edit it; ask the user to hand the run over"
      exit 1
    fi

    # Session id: explicit flag > env override > Claude Code's own env var.
    sid="${sid_arg:-${CLAUDE_TASK_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-}}}"
    if [ -z "$sid" ]; then
      cat >&2 <<'EOF'
task-loop: no session id, so there is nothing safe to scope the loop to.

CLAUDE_CODE_SESSION_ID is set only inside Claude Code's own tool environment. A
plain terminal shell — including the VS Code integrated terminal — does not have
it, which is why this refused rather than guessing.

Two ways forward:

  1. BEST — ask Claude, in the session you want to arm, to run the command.
     It knows its own id. In VS Code that means typing into the Claude Code
     panel, not the terminal.

  2. From a terminal, pass the id explicitly:
       task-loop-guard.sh --sessions                          # list ids by recency
       task-loop-guard.sh --arm <checklist> --session <ID>

Arming the wrong session is not harmful — it simply loops a session that is not
working the list, and --disarm undoes it.
EOF
      exit 1
    fi
    armed="$state_dir/armed-$sid"

    case "$sub" in
      --arm)
        tasks="$tasks_arg"
        if [ -n "$tasks" ]; then
          [ -f "$tasks" ] || { echo "task-loop: no such checklist: $tasks" >&2; exit 1; }
        else
          tasks="$(discover "$PWD")" || {
            echo "task-loop: no checklist found. Create .claude/TASKS.md, or pass a path:" >&2
            echo "           task-loop-guard.sh --arm /path/to/TASKS.md" >&2
            exit 1
          }
        fi
        # Absolute path: the loop must survive the session changing directory.
        tasks="$(cd "$(dirname "$tasks")" && pwd)/$(basename "$tasks")"
        printf '%s\n' "$tasks" > "$armed"
        printf '%s %s %s\n' "$(open_count "$tasks")" 0 0 > "$state_dir/$sid"
        echo "task-loop ARMED for session $sid"
        echo "  checklist: $tasks"
        echo "  open: $(open_count "$tasks")   done: $(done_count "$tasks")"
        echo "  disarm with: $0 --disarm"
        log_event "$sid" "ARMED: $tasks"
        # Housekeeping: a session that never disarmed leaves its files behind.
        # Harmless (ids are unique, so they can never capture a new session) but
        # they accumulate, so drop anything untouched for a month.
        find "$state_dir" -maxdepth 1 -type f -mtime +30 -delete 2>/dev/null || true
        exit 0 ;;
      --disarm)
        rm -f "$armed" "$state_dir/$sid" 2>/dev/null || true
        log_event "$sid" "DISARMED: by --disarm"
        echo "task-loop DISARMED for session $sid"
        exit 0 ;;
      --status)
        echo "session:  $sid"
        if [ -r "$armed" ]; then
          tasks="$(head -1 "$armed")"
          echo "armed:    YES"
          echo "checklist: $tasks"
          if [ -f "$tasks" ]; then
            echo "open: $(open_count "$tasks")   done: $(done_count "$tasks")   blocked: $(blkd_count "$tasks")"
            grep -qi 'loop:off' "$tasks" && echo "NOTE: loop:off present — the loop will not run."
          else
            echo "WARNING: pinned checklist no longer exists — the loop will not run."
          fi
          [ -r "$state_dir/$sid" ] && echo "state:    $(cat "$state_dir/$sid")  (open stalls wrapped)"
        else
          echo "armed:    no  (this hook is a no-op for this session)"
        fi
        if [ -r "$state_dir/events.log" ]; then
          echo "recent events for this session:"
          grep -F " ${sid:0:8} " "$state_dir/events.log" 2>/dev/null | tail -8 | sed 's/^/  /' \
            || echo "  (none)"
        fi
        exit 0 ;;
    esac ;;
esac

# ─── hook path ──────────────────────────────────────────────────────────────
payload="$(cat)"

if command -v jq >/dev/null 2>&1; then
  sid="$(printf '%s' "$payload" | jq -r '.session_id // ""' 2>/dev/null || true)"
else
  sid=""
fi
# No session id means we cannot tell whose loop this is. Do nothing rather than
# risk capturing an unrelated session — silence is the safe failure here.
[ -n "$sid" ] || exit 0

armed="$state_dir/armed-$sid"
[ -r "$armed" ] || exit 0          # ← THE GATE: unarmed sessions are untouched

state="$state_dir/$sid"
# State: remaining-count, consecutive stalls, wrap-up-done, consecutive misses.
prev_open=""; stalls=0; wrapped=0; misses=0
if [ -r "$state" ]; then
  read -r prev_open stalls wrapped misses < "$state" 2>/dev/null || true
  stalls="${stalls:-0}"; wrapped="${wrapped:-0}"; misses="${misses:-0}"
fi

tasks="$(head -1 "$armed" 2>/dev/null)"

# ---- transient-absence tolerance ------------------------------------------
# A DERIVED checklist is rewritten by its generator (e.g. a script that
# regenerates TASKS.md from another list on every close), so there is a window
# where the file is absent, truncated, or half-written. Disarming on the first
# miss silently stole the arm mid-regeneration. Require MISS_LIMIT consecutive
# misses before concluding the checklist is really gone.
if [ -z "$tasks" ] || [ ! -f "$tasks" ]; then
  misses=$(( misses + 1 ))
  if [ "$misses" -ge "$MISS_LIMIT" ]; then
    log_event "$sid" "DISARMED: checklist unreadable $misses times in a row: ${tasks:-<empty arm file>}"
    rm -f "$armed" "$state" 2>/dev/null || true
  else
    printf '%s %s %s %s\n' "${prev_open:-0}" "$stalls" "$wrapped" "$misses" > "$state"
    log_event "$sid" "checklist unreadable (miss $misses/$MISS_LIMIT), staying armed: $tasks"
  fi
  exit 0
fi

# Kill switch that lives in the file, so it survives compaction and machine hops.
grep -qi 'loop:off' "$tasks" && exit 0

open="$(open_count "$tasks")";  open="${open:-0}"
done_="$(done_count "$tasks")"; done_="${done_:-0}"
blocked="$(blkd_count "$tasks")"; blocked="${blocked:-0}"
[ -n "$prev_open" ] || prev_open="$open"
misses=0                            # readable again — reset the miss counter

# ---- an EMPTY checklist is not a FINISHED one -----------------------------
# Zero open AND zero done means no task lines were parsed at all: the file is
# empty, mid-write, or its format changed. Treating that as "complete" is what
# silently disarmed a live run during regeneration. Stay armed and wait.
if [ "$open" -eq 0 ] && [ "$done_" -eq 0 ]; then
  printf '%s %s %s %s\n' "$prev_open" "$stalls" "$wrapped" "$misses" > "$state"
  log_event "$sid" "checklist parsed 0 open + 0 done (empty or mid-write), staying armed: $tasks"
  exit 0
fi

# ---- list complete ----
if [ "$open" -eq 0 ]; then
  # One-shot triage pass: if anything was parked as BLOCKED, make Claude account
  # for it before the session goes quiet, so blockers can't hide behind a tidy
  # all-checked list. `wrapped` makes this fire exactly once, never a loop.
  if [ "$blocked" -gt 0 ] && [ "$wrapped" -ne 1 ]; then
    printf '%s %s 1\n' "$open" "$stalls" > "$state"
    cat >&2 <<EOF
The checklist at $tasks is fully worked: $done_ item(s) closed, but $blocked were
parked as BLOCKED. Do not stop yet — write the triage summary now:

$(grep -iE '^[[:space:]]*[-*][[:space:]]+\[[xX]\][[:space:]]*BLOCKED' "$tasks" 2>/dev/null)

For each blocked item, state in your reply: what specifically blocked it, the one
action that would unblock it, and who has to take that action (you, the user, or
a third party). Group items sharing a root cause. Then stop.
EOF
    exit 2
  fi
  log_event "$sid" "DISARMED: list complete ($done_ done, $blocked blocked): $tasks"
  rm -f "$state" "$armed" 2>/dev/null || true   # done: auto-disarm
  exit 0
fi

# ---- progress accounting ----
if [ "$open" -lt "$prev_open" ]; then
  stalls=0                       # a box got checked -> earn another continuation
else
  stalls=$(( stalls + 1 ))
fi
printf '%s %s %s %s\n' "$open" "$stalls" "$wrapped" "$misses" > "$state"

# ---- anti-spin: nothing checked for MAX_STALLS stops in a row -> stand down ----
if [ "$stalls" -ge "$MAX_STALLS" ]; then
  # SUSPEND, do not disarm. Disarming here silently revoked the arm on a derived
  # checklist, where the open count only drops after the generator runs — so
  # several legitimate working turns can pass with the count unchanged. The arm
  # survives, the loop simply stops pushing, and it RESUMES BY ITSELF as soon as
  # the open count drops again (progress resets stalls to 0 above).
  [ "$stalls" -eq "$MAX_STALLS" ] && \
    log_event "$sid" "SUSPENDED after $stalls stops with no progress (still armed, auto-resumes on progress): $tasks"
  echo "task-loop-guard: $stalls stops with no progress on $tasks — not pushing." >&2
  echo "  Still ARMED. It resumes automatically when the open count drops." >&2
  echo "  If this list is GENERATED, the count only moves after you re-run its generator." >&2
  exit 0                         # exit 0 allows the stop; stderr is only a log
fi

# ---- veto the stop ----
next="$(grep -iE '^[[:space:]]*[-*][[:space:]]+\[[[:space:]]*\]' "$tasks" 2>/dev/null | head -3)"

cat >&2 <<EOF
DO NOT STOP. $tasks still has $open unchecked item(s); $done_ done.

Next up:
$next

Continue now, without asking for confirmation or summarizing progress:
  1. Re-read $tasks in full. It is the authoritative task list, NOT your context.
     If this session has been compacted, your in-context memory of it is stale
     and the file is the only reliable record of what is already finished.
  2. Do the next unchecked item completely.
  3. Edit $tasks to flip that box from "- [ ]" to "- [x]" the moment it is done,
     appending a short note on what you did. Editing the file is what counts —
     saying "done" in your reply does not, and will simply re-trigger this hook.
  4. Repeat until every box is checked.

If an item is genuinely blocked, leave its box UNCHECKED (a checked box means
done), mark it "- [ ] ⛔ **BLOCKED** · <item> ⟵ <specific reason and who owes it>",
move it below the workable items, and carry on. If nothing left is workable, write
loop:off into the checklist. Do not stop to report progress mid-list; the
checklist is the progress report.

If this checklist is GENERATED from another source of truth, do not hand-edit it:
close the item in the SOURCE and re-run its generator, or the next regeneration
erases your edit and this hook re-fires on work you already finished.
EOF
exit 2   # exit 2 on a Stop hook = "you may not end the turn"
