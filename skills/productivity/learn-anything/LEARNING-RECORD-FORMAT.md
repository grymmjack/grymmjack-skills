# Learning Record Format

Learning records live in `./learning-records/` and use sequential numbering: `0001-slug.md`, `0002-slug.md`, etc. Create the directory lazily — only when the first record is written.

They are the **Capture** stream of the framework — Rick's "observations and connections and discoveries," plus every mastery demonstration and every move along the continuum. Loosely the learning equivalent of ADRs: they record non-obvious lessons and decisions that steer future sessions, and they're how you judge what to do next.

## Template

```md
# {Short title of what was learned, decided, or reached}

{1-3 sentences: what happened and why it matters for future sessions.}
```

That is the whole format. A record can be a single paragraph. The value is recording _that_ this is now true and _why_ it changes what to do next — not in filling out sections.

## Optional sections

Only when they add value:

- **Status** frontmatter (`active | superseded by LR-NNNN`) — when a later understanding replaces an earlier one.
- **Evidence** — how Rick demonstrated it (a question answered, a probe run clean, a thing explained aloud). Essential for mastery claims.
- **Implications** — what this unlocks or rules out next.

## When to write a learning record

Write one when any of these is true:

1. **Rick demonstrated genuine understanding of something non-trivial** — evidence, not exposure. Sets a new floor.
2. **Rick disclosed prior knowledge** — "I already know X." Record it (and the depth claimed) so it isn't re-taught. This is core to the Critical Observations anchor.
3. **A misconception was corrected** — high-value: it predicts future stumbling blocks on related topics.
4. **A continuum transition** — Rick moved up (or deliberately parked) a rung. Note the old rung, the new rung, and what triggered the move. Update `TOPIC.md` and `index.html` to match.
5. **A mastery demonstration** — Rick explained the thing to someone else, or ran the full analysis/dissection/experiment unaided. Record the evidence; this is what promotes a topic to "mastered."
6. **A depth verdict on a reconnaissance topic** — "looked into it, it's a Curious-and-done." A valid, valuable outcome; record it so the topic isn't reopened on a whim.

### What does _not_ qualify

- Material merely covered. Coverage is not learning. Wait for evidence.
- A term already captured tersely in `GLOSSARY.md`. Don't duplicate.
- Session activity logs. Records are decision-grade insights, not a journal.

## Numbering & supersession

Scan `./learning-records/` for the highest number and increment. When a later record contradicts an earlier one (understanding deepened or corrected), mark the old one `Status: superseded by LR-NNNN` rather than deleting it — the history of how understanding evolved is itself signal.
