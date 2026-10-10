---
name: task-loop
description: Work a long list of tasks straight through without stopping between them, by turning the list into an on-disk checklist that a Stop hook enforces. Use when the user has a big batch of work (dozens of tasks, a migration, a backlog, a sweep across many files) and wants it done unattended — or says any of "don't stop", "keep going until done", "work the whole list", "don't stop until it's all finished", "I don't want to babysit this", "grind through these", "work TASKS.md", or asks why Claude keeps stopping after each item. Also use to set up, inspect, or tear down the checklist, and to triage whatever ended up BLOCKED.
---

# task-loop

Run a long list of tasks to completion in one unattended stretch, instead of stopping after each item for a "want me to continue?" round trip.

## Why this skill exists

A turn ends when the model emits no tool call. That means "don't stop until done" is an instruction competing against a *structural default* — there is no action to forbid, so the instruction has nothing to grab, and it loses. It loses even harder on a long list, because a 60-task session will be compacted several times and the instruction is summarized away along with the task list itself.

So the enforcement does not live in a prompt. It lives in `~/.claude/hooks/task-loop-guard.sh`, registered on the `Stop` event. That hook fires *after* Claude has decided to stop, counts unchecked boxes in an on-disk checklist, and exits 2 to veto the stop while work remains. Exit 2 on a `Stop` hook means "you may not end this turn," and the hook's stderr becomes Claude's next instructions.

This skill is the ergonomics around that hook: building the checklist, honoring its contract, and triaging the leftovers.

## Arm the loop — this session only

**The hook does nothing until the current session is explicitly armed.** Arming is keyed to `$CLAUDE_CODE_SESSION_ID` and pins the checklist's absolute path, so no other session is affected and this one cannot be redirected onto a different list.

```bash
~/.claude/hooks/task-loop-guard.sh --arm .claude/TASKS.md   # or --arm with no path to auto-discover
~/.claude/hooks/task-loop-guard.sh --status                 # is this session armed? what list?
~/.claude/hooks/task-loop-guard.sh --disarm                 # stop the loop, this session only
```

**You must run this yourself, via the Bash tool.** `CLAUDE_CODE_SESSION_ID` exists only inside Claude Code's tool environment — a plain terminal (including the VS Code integrated terminal) does not have it, so telling the user to paste these into a shell fails with "no session id". If they need to arm from a terminal, they pass the id explicitly: `--sessions` lists ids by recency, then `--arm <checklist> --session <ID>`.

Arm it **after** the user has confirmed the checklist and immediately before starting the run. It auto-disarms when the list completes, when the anti-spin guard trips, or if the checklist disappears.

**Always pass an ABSOLUTE checklist path.** Auto-discovery uses `$PWD`, which is wrong in a multi-root VS Code workspace: the session's cwd is the *first* workspace folder, so a checklist in the third folder never resolves relatively. `$(pwd)/.claude/TASKS.md` is a trap there.

⛔ **Why this is per session, not per directory** (regression observed 2026-08-06): the hook used to engage whenever it *found* a checklist near the cwd. That conscripted every session touching the project — including one opened to ask an unrelated question — and `$CLAUDE_PROJECT_DIR` let it reach across projects. A bystander session burned 35 minutes and 127.6k tokens being force-continued through a list it never agreed to work. Never re-introduce discovery-based opt-in.

### Preflight

If the hook is not registered, nothing loops and the session will quietly stop after one item — the failure is silent, so check before promising unattended behavior.

```bash
test -x ~/.claude/hooks/task-loop-guard.sh && echo "hook: present" || echo "hook: MISSING"
command -v jq >/dev/null && echo "jq: present" || echo "jq: MISSING"
python3 -c 'import json,pathlib; p=pathlib.Path.home()/".claude/settings.json"; d=json.loads(p.read_text()); print("registered:", any("task-loop-guard" in h.get("command","") for g in d.get("hooks",{}).get("Stop",[]) for h in g.get("hooks",[])))'
```

- All good → arm it and proceed.
- `jq` missing → both hooks silently no-op without it (they cannot read the session id from the hook payload). Ask the user to install `jq`.
- Hook missing or unregistered → install it, below.
- Just registered it this session → **it will not take effect until a new session starts.** Claude Code snapshots hooks at startup, so tell the user to restart before relying on the loop; do not claim it is running when it is not.

### Install

Both hooks ship in the `hooks/` folder next to this `SKILL.md`. Link them into `~/.claude/hooks/`, the path every command in this skill uses:

```bash
mkdir -p ~/.claude/hooks
ln -sf <this-skill-dir>/hooks/task-loop-guard.sh       ~/.claude/hooks/task-loop-guard.sh
ln -sf <this-skill-dir>/hooks/task-loop-write-guard.sh ~/.claude/hooks/task-loop-write-guard.sh
```

Then merge this into the `hooks` object of `~/.claude/settings.json`. Append to any existing `Stop` / `PreToolUse` arrays; do not replace them. Show the user the change before writing it:

```json
"PreToolUse": [
  { "matcher": "Read|Edit|Write|MultiEdit|NotebookEdit|Grep|Glob|Bash",
    "hooks": [{ "type": "command", "command": "$HOME/.claude/hooks/task-loop-write-guard.sh", "timeout": 10 }] }
],
"Stop": [
  { "hooks": [{ "type": "command", "command": "$HOME/.claude/hooks/task-loop-guard.sh", "timeout": 10 }] }
]
```

Both hooks are inert for any session that has not been armed, so registering them globally is safe.

## Building the checklist

Write it to **`.claude/TASKS.md`** in the project. That location keeps repo roots clean and needs no `.gitignore` change in most repos. The hook also accepts `./TASKS.md`, `$CLAUDE_PROJECT_DIR/TASKS.md`, or an explicit `$CLAUDE_TASKS_FILE`.

Format is a plain GitHub task list:

```markdown
# <what this batch is>

- [ ] one concrete, independently checkable task
- [ ] the next one
- [x] already finished — short note on what was done
- [x] BLOCKED: needs a production credential only you can provision
```

Rules that make the loop converge:

- **One box per genuinely independent unit of work.** If two items must happen together, make them one box. The unchecked count is the loop's only progress signal, so a box that cannot be finished alone stalls it.
- **Concrete and verifiable.** "Migrate `billing.ts` to the new client" is a box; "improve the pipeline" is not.
- **Order matters when there are dependencies** — the hook always points at the topmost unchecked item.
- If the user hands over a raw dump (a ticket, a paste, a plan, a spreadsheet), convert it to boxes and **show the list for confirmation before starting** a long unattended run. Silently misreading 60 items is expensive.

## Never write to a checklist this session does not own

⛔ **Observed 2026-08-06:** this skill loads on trigger, with no connection to whether the session is armed — so a second session picked up these instructions and started appending items to a checklist another session was actively working. The Stop hook is armed-gated; **this document is not**, and it only ever *reads* the checklist. Every write comes from you, on the strength of this text.

So before any Edit/Write to a checklist, confirm this session owns it:

```bash
~/.claude/hooks/task-loop-guard.sh --owns /abs/path/to/TASKS.md   # exit 0 = yours
```

- exit 0 → you own the run, proceed.
- `owned by another session` → **do not edit it, and do not work its items.** Report what you wanted to add and let the user relay it. Taking over is their call, not yours (`--disarm --session <ID>` then `--arm`).
- `unclaimed` → nobody is looping on it. Editing is fine, but if you are about to start a run, arm it first.

A `PreToolUse` hook (`task-loop-write-guard.sh`) enforces this and will block the tool call outright, so a mistake here fails loudly rather than corrupting someone's run. Reading is always allowed — use `Read`.

## The contract while looping

1. Re-read the checklist file **in full** before each item. It is authoritative, not your context — after a compaction it is the only reliable record of what is already done.
2. **Mark the item in-progress BEFORE the first tool call against it, then re-read the file to confirm the mark landed.** The user watches this file to see what you are doing; an unmarked file reads as "nothing is happening". Do it even for an item you expect to finish in one step — the ones that look quick are the ones that turn into an hour.
3. Do the item completely.
4. **Edit the file** to flip `- [ ]` → `- [x]`, appending a one-line note on what was done. Editing is what counts; saying "done" in a reply does not move the count and will simply re-trigger the hook.
5. **Clear the in-progress mark in the SAME edit that closes the item** — never as a separate step you might not reach. A stale mark pointing at finished work is worse than none, because it is confidently wrong.
6. Repeat. Do not stop to report progress mid-list — the checklist *is* the progress report.

### Always show the loop status — running OR paused

Put the state at the TOP of the checklist, every time:

```markdown
## ▶️ LOOP RUNNING — items are being worked top-down
## ⏸️ LOOP PAUSED — `loop:off`
_<the reason, in one line — a paused loop with no stated reason is indistinguishable from a broken one>_
```

Rendering only the PAUSED case is the trap: a running loop then looks identical to a file that forgot to say, and **an absent status reads as "nobody knows"** — the state the checklist exists to eliminate. If it is paused, the reason is mandatory and must name what would un-pause it.

### Building is not publishing

If the checklist has a companion surface (a published page, a dashboard, a shared doc), **regenerating it is not shipping it.** Ship it in the same breath, and make the un-shipped state loud in whatever script rebuilds it — a quiet "now publish" line at the end of successful output gets read past every single time. Ask instead: *if I stopped right now, would the reader see the old version?*

### The in-progress mark

Put a `## 🔨 NOW — doing right now` section at the TOP of the file and move the active item under it.

- **Keep the checkbox `- [ ]`.** The hook counts open as `\[[[:space:]]*\]` and done as `\[[xX]\]`, so `- [*]` or `- [~]` matches **neither** — the item silently drops out of the open count, and if it is the last one the loop exits early on unfinished work. Mark it with an emoji on the text (`➡️`), never by changing the box.
- **Move the item, don't copy it.** Two `- [ ]` lines for one id are counted twice, so the loop's only progress signal reads high.
- **Top of file, not in place.** A mark on item 10 of 10 is a mark nobody finds — the reader checks the most visible thing first.

⛔ **Three ways this goes wrong, all observed 2026-08-06:**
- **Setting the mark only on close, not on start.** Finish A, clear the mark, pick up B, never set it — the file shows no active work while you are busy. Hence step 2: setting it is part of the loop, not a courtesy.
- **Marking in place.** The item was 10th of 10 in its group and the user still could not see it.
- **A GENERATED checklist.** If the file is derived from another source of truth, a hand-edited mark — or a hand-flipped box — is erased by the next regeneration, and the hook then re-fires forever on work already done. Keep the active id in a small state file the generator reads, expose a flag for it, and close items in the SOURCE. Never hand-edit a derived checklist.

⛔ **A CHECKED BOX MEANS DONE. NOTHING ELSE.** The older guidance here was to mark a blocked item `- [x] BLOCKED: <reason>` so the unchecked count reaches zero and the hook settles. **Do not do that.** It buys loop convergence by mismarking not-done work on the surface the human actually reads — as the user put it on 2026-08-06: *"blocked should not be checked! ONLY DONE tasks should be checked."*

Mark a genuinely blocked item `- [ ] ⛔ **BLOCKED** · <item> ⟵ <specific reason and WHO owes it>`, leaving the box unchecked, and give the loop an honest way to stop instead: **when nothing left is actionable, write `loop:off` into the checklist**. That says "nothing here is workable", which is true, rather than "everything is finished", which is not — and it clears the moment one item becomes actionable again.

Never mark something blocked to escape a hard task — only for a real external dependency (missing credential, unreachable service, a decision only the user can make). And name **who** owes it: "blocked on Alice" and "nobody has asked Alice" look identical on a board, so if a checklist has any long-lived human dependencies, carry a sent/not-asked marker beside them.

### A blocker REPRIORITIZES the list — it does not stop the loop

When an item needs someone else, **reorder and keep going**; do not pause the run and do not stop to report. Blocked work moves down or out, the next workable item moves up into NOW, and the loop continues. Pausing the whole loop because one item needs a person converts a one-item wait into a zero-progress session.

Reserve an actual pause for when the user asks for one, or when *nothing left on the list* is workable without them. Even then the NOW section stays populated — **NOW is independent of pause state.** It answers "what is being worked", which is still true while paused; a paused list with an empty NOW reads as "stalled and nobody knows where."

## Blocked triage

When every box is checked and any are `BLOCKED:`, the hook blocks the stop exactly once more and asks for a triage summary. For each blocked item state: what specifically blocked it, the single action that would unblock it, and who has to take that action. Group items that share a root cause — five failures on one missing credential are one problem, not five.

## Stopping early

Any one of these ends the loop:

- every box checked
- add a line containing `loop:off` anywhere in the checklist
- delete or rename the checklist
- **Esc / Ctrl-C** — a user interrupt is not a `Stop` event, so it always wins
- three consecutive stops with nothing newly checked: the anti-spin guard stands down on its own (tune with `CLAUDE_TASK_MAX_STALLS`)

## Notes

- No checklist file means the hook is a total no-op, so ordinary sessions are unaffected. Creating the file *is* the opt-in.
- Progress, not attempts, buys continuations: the stall counter resets whenever the unchecked count drops, so real work loops indefinitely while spinning in place gives up quickly.
- For fully independent tasks with no shared context, `claude -p` in a loop over the list is an alternative worth mentioning — one clean context per task, no compaction risk at all.
