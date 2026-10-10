# RESOURCES.md Format

`RESOURCES.md` is the curated set of trusted sources for the topic, filed by **type** — Rick's resource taxonomy from the Learn Anything map. Knowledge for deep dives is drawn from here, not from parametric guesses. Prefer official and primary sources; annotate every entry with what it covers and when to reach for it.

## Structure

```md
# {Topic} Resources

## Official
- [Official website]({url}) — {what lives here; when to use it}
- [Official repo]({url}) — {source, issues, releases}
- [Docker image]({url}) — {the fastest way to run it clean}
- [Sandbox / playground]({url}) — {try it with zero install}

## Documentation
- [Official docs (web)]({url}) — {the reference; use for X}
- [GitHub README]({url}) — {quickstart, the 5-minute version}
- man page(s): `man {cmd}`, `man 5 {cmd}` — {authoritative on-machine syntax}
- CLI help: `{cmd} --help` / `{cmd} help` — {the fastest lookup, offline}

## Videos
- [Official YouTube channel]({url}) — {talks, release walkthroughs}
- [Trusted expert: {name}]({url}) — {why trusted; what they cover}

## Books & cheat sheets
- [Book: _{title}_ — {author}]({url}) — {the deep, canonical treatment}
- [Cheat sheet / quick reference]({url}) — {the one-page recall aid}
- Dash / Zeal docset: {name} — {offline API browsing}

## Instant Gratification Nerdery Lab (VS Code)
- Extensions: {ext}, {ext} — {what each buys you}
- Workspace: `./lab/{topic}.code-workspace` — {wired to run/debug immediately}

## Wisdom (Communities)
- [{community}]({url}) — {signal level; use for troubleshooting / critique}
```

## Rules

- **Official and primary first.** Official site, repo, and docs outrank blogs and tutorials. Man pages and `--help` win on _this machine's_ behaviour when sources disagree.
- **File by type.** The taxonomy above mirrors the map. Drop any heading with no entry — don't pad. Add a type the map doesn't list if the topic needs it.
- **Annotate every entry.** A bare link is useless in three months. One line: what it covers, when to reach for it.
- **Verify every link before it goes in.** Fetch each URL and confirm it resolves to the intended content — a candidate from memory or a search result is not a fact. A `200` that redirects a real path down to the site root is a **dead link**, not a live one; check the final URL, not just the status. Run `bash verify-urls.sh` after editing links; a URL you can't verify goes under `## Gaps`, not into the list. (See SKILL.md → _Never trust parametric knowledge_.)
- **The Nerdery Lab is a resource.** Rick's VS Code extensions + a ready-to-run workspace are how he gets instant hands-on gratification. Capture the exact extensions and the workspace file so setup is one step next time.
- **Surface gaps.** If no good source exists for an area the topic needs, add a `## Gaps` section listing what's missing. It drives the next search.
- **Prune ruthlessly.** Five sharp sources beat thirty mediocre ones. Remove what turned out wrong or shallow.
- **Record community preferences.** If Rick opts out of a community, note it so it isn't re-proposed.
