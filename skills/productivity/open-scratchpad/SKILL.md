---
name: open-scratchpad
description: Open a macOS Finder window to the CURRENT Claude Code session's scratchpad directory so the user can browse and examine the files Claude generated there. Use when the user says "open the scratchpad", "open a finder to it", "show me the generated files", "where are the files you made", or otherwise wants to see session-generated artifacts in Finder.
---

# open-scratchpad

Reveal the current session's **scratchpad directory** in Finder so the user can see the files generated during the session.

## Why this skill exists

The Bash tool runs inside a filesystem sandbox. Two consequences bite repeatedly:

- **Writes to arbitrary paths** (e.g. `~/Desktop`, `~/Documents`) can land in an ephemeral sandbox **overlay** — a follow-up `ls` from the sandboxed shell "sees" the file, but it never reached the real disk, so it's invisible in Finder.
- **GUI calls** like `open` must reach the real macOS session, which the sandbox blocks.

The scratchpad directory is a **real, persistent** location that the harness designates as writable, so anything Claude saved there actually exists. This skill points Finder straight at it.

## Steps

1. **Find the scratchpad path.** It is given in your system prompt under the **"Scratchpad Directory"** section — an absolute path ending in `/scratchpad` (shape: `/private/tmp/claude-<uid>/<project-slug>/<session-id>/scratchpad`). Use that exact value. Never guess or hardcode a session id — it changes every session.

2. **Open it in Finder and list its contents**, running the Bash command **with the sandbox disabled** (`dangerouslyDisableSandbox: true`) — this is required so `open` reaches the real GUI:

   ```bash
   open "<SCRATCHPAD_PATH>" && ls -lah "<SCRATCHPAD_PATH>"
   ```

3. **Confirm and summarize.** Tell the user Finder is open and briefly note the notable files (e.g. "tiktok_audit.html, two CSVs, the SQL queries").

## Variations

- **Reveal one specific file** (e.g. a PDF the user expected on the Desktop): `open -R "<file>"` selects that file in Finder. `open "<dir>"` opens a folder.
- If the user asks for a path *other* than the scratchpad (Desktop, a repo dir, etc.), `open` that path instead — same sandbox-disabled requirement.
- If a file the user wanted is missing from its intended spot but present in the scratchpad, it's almost certainly the sandbox-overlay issue above: re-create/copy it to the real destination with a `dangerouslyDisableSandbox: true` Bash command, then `open -R` it.

## Notes

- macOS only (relies on `open`). If `open` isn't available, just print the absolute scratchpad path so the user can navigate there manually.
