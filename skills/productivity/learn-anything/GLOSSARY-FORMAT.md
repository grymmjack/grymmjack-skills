# GLOSSARY.md Format

`GLOSSARY.md` is the **Applied Learning** capture — the topic's own language, made Rick's own. It holds the **terms**, **acronyms**, **languages**, and **formats** the topic uses, plus an index of worked **examples**. Compressing a concept into a tight definition is itself evidence Rick understands it, so building this is part of learning, not a chore before it.

## Structure

```md
# {Topic} Glossary

{One or two sentences describing the topic this glossary covers.}

## Terms

**{Term}**:
{One or two sentences. Define what it IS, not how to do it.}
_Avoid_: {alias 1}, {alias 2}

## Acronyms

**{ACRONYM}** ({expansion}):
{What it means in this topic, in one line.}

## Languages & formats

**{Format / language}**:
{What it is and where the topic uses it — e.g. a config format, a query language, a wire format.}

## Examples

- [`lessons/0003-...html`](./lessons/0003-...html) — {the one thing this worked example demonstrates}
```

## Rules

- **Add a term only when Rick understands it.** The glossary records compressed knowledge; it is not a dictionary he reads to learn. Wait until he can use the term correctly before promoting it.
- **Be opinionated.** When several words mean the same thing, pick the best and list the rest as aliases to avoid. That's how language compresses.
- **Keep definitions tight.** One or two sentences. Define what the term IS.
- **Use the glossary's own terms inside definitions.** Once a term is in, prefer it everywhere — including inside other definitions.
- **Acronyms get expanded once, then used.** Spell it out in the glossary; after that the short form is fair game everywhere.
- **Group under subheadings** when natural clusters emerge (by subsystem, by layer). A flat list is fine when terms cohere.
- **Flag ambiguities explicitly.** If the wider field uses a term loosely, note the resolution for this workspace.
- **Revise as understanding deepens.** A week-one definition may be wrong by week six. Update in place; don't leave stale entries.
