---
name: add-scratchpad-to-workspace
description: Add the CURRENT Claude Code session's scratchpad directory into the user's currently-open VS Code window as a workspace folder (multi-root), using the `code --add` CLI, so session-generated files show up in the Explorer. Use when the user says "add the scratchpad to my workspace", "put the scratchpad in vscode", or wants generated files to appear in the VS Code file tree.
---

# add-scratchpad-to-workspace

Add this session's **scratchpad directory** to the user's currently-open VS Code window so the generated files appear directly in the Explorer (as a second root in a multi-root workspace).

## Why this skill exists

Files Claude generates live in the session scratchpad — a real, persistent directory the harness designates as writable. Surfacing it as a VS Code workspace folder is the most convenient way for the user to open/diff/preview those files in the editor they're already in (better than Finder for code/text).

## Steps

1. **Find the scratchpad path.** It is given in your system prompt under the **"Scratchpad Directory"** section — an absolute path ending in `/scratchpad` (shape: `/private/tmp/claude-<uid>/<project-slug>/<session-id>/scratchpad`). Use that exact value. Never guess or hardcode a session id — it changes every session.

2. **Add it to the active VS Code window**, running the Bash command **with the sandbox disabled** (`dangerouslyDisableSandbox: true`) — required so the `code` CLI reaches the real running VS Code instance (the sandbox blocks it otherwise):

   ```bash
   code --add "<SCRATCHPAD_PATH>"
   ```

   Use `--add` (`-a`) **alone**. Do **not** add `--wait` (`-w`): `--wait` blocks the command until the window/files are closed, which hangs the terminal. `--add` is the non-blocking "merge this folder into the current workspace" flag.

3. **Confirm.** Tell the user the scratchpad now appears as a folder in their VS Code Explorer (it turns the window into a multi-root workspace if it wasn't already). They can remove it later via right-click → "Remove Folder from Workspace".

## Notes

- Requires the `code` CLI on PATH (`which code`). If missing: VS Code → Command Palette → **"Shell Command: Install 'code' command in PATH"**, or call the absolute binary (e.g. `/usr/local/bin/code --add ...`).
- macOS/desktop VS Code. Pairs with the `open-scratchpad` skill (which reveals the same directory in Finder instead).
- This adds the folder to the **last active** VS Code window. If the user has multiple windows open, it lands in whichever was focused most recently.
