# grymmjack-skills

My own agent skills for [Claude Code](https://claude.com/claude-code) and other harnesses that read the [Agent Skills](https://agentskills.io) format.

## Install

As a Claude Code plugin (installs the `engineering/` and `productivity/` skills):

```
/plugin marketplace add grymmjack/grymmjack-skills
/plugin install grymmjack-skills@grymmjack
```

Or with the `skills` CLI, one skill at a time:

```bash
npx skills add grymmjack/grymmjack-skills --skill=task-loop
```

Or clone the repo and symlink every skill into `~/.claude/skills` and `~/.agents/skills`, so a `git pull` keeps them current:

```bash
git clone https://github.com/grymmjack/grymmjack-skills.git
grymmjack-skills/scripts/link-skills.sh
```

## Skills

### Engineering

- **[env-browser](./skills/engineering/env-browser/SKILL.md)** — Explore a project's package environment with fzf: browse installed packages, read their source, and jump to their registry or docs. Covers Python, Node, Rust, Go and Ruby. *User-invoked.*

### Productivity

- **[task-loop](./skills/productivity/task-loop/SKILL.md)** — Work a long task list straight through, unattended. It turns the list into an on-disk checklist that a per-session Stop hook enforces, so the agent can't stop until every box is checked. Ships its two hooks in `hooks/`.
- **[learn-anything](./skills/productivity/learn-anything/SKILL.md)** — Work through a new topic with my "Learn Anything" framework (the 5 Ws, resources, the continuum of learning, mastery) in a stateful per-topic workspace. *User-invoked.*
- **[xmind-mindmap](./skills/productivity/xmind-mindmap/SKILL.md)** — Turn any topic into a real `.xmind` mind map from a hierarchical topic tree, with optional SVG, PNG, PDF or interactive-HTML renders.
- **[summarize](./skills/productivity/summarize/SKILL.md)** — Condense a conversation or document into a scannable briefing with emoji-headed bullets, colored status boxes, and a tickable "needs you" checklist.
- **[html-to-pdf](./skills/productivity/html-to-pdf/SKILL.md)** — Turn an HTML file into a full-bleed PDF with a bookmark outline using headless Chrome, and publish it as a shareable web page too.
- **[find-audio-on-disk](./skills/productivity/find-audio-on-disk/SKILL.md)** — Fill a list of named sound-effect or music slots from sample libraries you already have, instead of making new sounds. It indexes, matches, verifies with ffprobe, and copies the picks with a manifest.
- **[open-scratchpad](./skills/productivity/open-scratchpad/SKILL.md)** — Open the current Claude Code session's scratchpad directory in Finder (macOS).
- **[add-scratchpad-to-workspace](./skills/productivity/add-scratchpad-to-workspace/SKILL.md)** — Add the current session's scratchpad directory to the open VS Code window as a workspace folder.

### Personal

These depend on my own tools and projects. They aren't in the plugin, but `link-skills.sh` links them.

- **[open-in-pixel-viewer](./skills/personal/open-in-pixel-viewer/SKILL.md)** — Present images, audio, tracker modules and ANSI art for review in [kaleidotron](https://github.com/grymmjack/kaleidotron).
- **[fill-asset-gaps-with-ai](./skills/personal/fill-asset-gaps-with-ai/SKILL.md)** — Find a game's missing or placeholder assets from its own manifest audits, then generate them with [pixelmon](https://github.com/grymmjack/pixelmon), [ansimon](https://github.com/grymmjack/ansimon) and [soundmon](https://github.com/grymmjack/soundmon).

## Credits

This repo grew out of my fork of **[Matt Pocock's skills](https://github.com/mattpocock/skills)**. `env-browser`, `learn-anything` and `xmind-mindmap` were first written there. The repo layout (bucket folders, a plugin manifest listing the promoted skills, a symlink installer) follows his. His skills are excellent, so go use them. Matt's MIT license notice is reproduced in [NOTICE](./NOTICE).

## License

[MIT](./LICENSE)
