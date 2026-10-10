Skills live in bucket folders under `skills/`:

- `engineering/` — code work
- `productivity/` — non-code workflow tools
- `personal/` — tied to my own tools or projects; not promoted

Every skill in `engineering/` or `productivity/` (the **promoted** buckets) must be listed in the top-level `README.md`, with its name linked to its `SKILL.md`, and must have an entry in `.claude-plugin/plugin.json`. Skills in `personal/` are listed in the README under **Personal** but must not appear in `plugin.json`.

A skill that needs supporting files (scripts, hooks, templates) keeps them inside its own folder, so it installs as one unit.

Nothing in this repo may contain secrets, machine-specific absolute paths, or private project names. Before adding a skill, scan it for those.

To (re)link every skill into `~/.claude/skills` and `~/.agents/skills`, run `scripts/link-skills.sh`. It leaves real directories alone unless given `--force`.
