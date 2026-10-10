# TOPIC.md Format

`TOPIC.md` lives at the workspace root and is the grounding doc for one topic. It captures the **5 Ws**, why Rick cares, his **interest level**, and where he sits on the **continuum of learning**. Every other decision — which resources to gather, how deep to dive, when to stop — traces back to this file.

## Template

```md
# {Topic}

## The 5 Ws
- **What**: {One or two sentences. What is it, plainly.}
- **Why**: {The load-bearing one. The concrete reason Rick cares — what changes in his work or nerd life if he learns this. Push past "to understand it".}
- **Who**: {The people/org behind it — whose docs, talks, and opinions to trust.}
- **Where**: {The canonical place to get it — install command, download, repo.}
- **When**: {The situations that should make Rick reach for this.}

## Interest level & continuum target
- **Interest**: {Mastery | Reconnaissance} — {one line on why this level}
- **Target rung**: {e.g. Continue? for mastery topics; Curious / Explore for reconnaissance}
- **Current rung**: {where Rick is right now on the continuum}

## Constraints
- {Time, budget, prior commitments, learning preferences — anything that bounds the approach.}

## Out of scope (for now)
- {Adjacent things Rick explicitly does not want to chase yet — protects focus.}
```

## Rules

- **One topic per workspace.** Two unrelated topics are two folders.
- **The Why is load-bearing.** If Rick can't say why he cares, interview him before writing anything else. A weak Why makes everything downstream abstract and gives you no way to judge depth.
- **Set the target rung early, revise freely.** Whether this is a mastery topic or a reconnaissance topic changes how much you invest. Deciding partway that a "mastery" topic is actually "reconnaissance-and-done" (or vice-versa) is normal — update this file and write a learning record.
- **Keep the current rung honest.** This is the top of the state machine `index.html` mirrors. Move it as Rick moves.
- **Concrete over abstract.** "Reach for `jq` by reflex when munging JSON in pipelines" beats "get good at jq."
- **Keep it short.** Past one screen, it has stopped being a compass.
