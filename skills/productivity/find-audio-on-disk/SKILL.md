---
name: find-audio-on-disk
description: "Scavenge audio you already have on disk (wav/ogg/mp3/flac) to fill a set of named sound-effect or music slots, instead of making new ones from scratch. Indexes large sample libraries, INTERROGATES the user for sonic palette + constraints, concept-matches candidates, verifies with ffprobe, then copies+renames into a destination with a manifest. Use when the user wants to find/reuse/scavenge existing sounds for a game or app, gives a list of effect names to fill, or says 'find audio on disk', 'find sfx', 'scavenge sounds', 'match my sound list to files I have'."
argument-hint: "What sound slots do you need filled, and where should I search?"
---

# Find audio on disk

Fill a list of **named audio slots** (e.g. `hit`, `door`, `treasure`, `boom`) by
scavenging sound files the user already owns — before anyone makes new ones in
sfxr, Bfxr, or a DAW. The output is one file per slot, named `<slot>.<ext>`, in a
destination directory, plus a `MANIFEST.tsv` recording exactly where each came from.

The single most important habit of this skill: **interrogate first.** Do not guess
the sonic direction — matching `door` to a real creaking wooden door versus a
chiptune blip is a taste decision that reshapes the entire result. Ask, show
concrete previews, then act.

## Tools

Check availability up front (all optional but strongly preferred):
- `fd` — fast file discovery (fallback: `find`)
- `rg` — fast filename/keyword grep over the index (fallback: `grep`)
- `ffprobe` (from ffmpeg) — read durations so you can reject long loops / oversized files
- `fzf` — optional interactive narrowing if the user wants to pick by hand

```sh
command -v fd rg ffprobe fzf 2>/dev/null
```

## Inputs to gather

1. **The slot list** — each slot is a `name` (target filename base) + a short
   `concept` (what the sound is *for*). It may arrive as a typed list, a table, a
   screenshot/image, or a README. If the target project already documents the names
   (e.g. an `assets/sfx/README`), read that — the names must match exactly or the
   game won't pick them up.
2. **Source directories** to scavenge (one or more roots).
3. **Destination directory** + naming convention (default: `<slot>.<ext>`, one file
   per slot; the source extension is preserved).

## Step 1 — Interrogate the user (the heart of this skill)

Only ask what you can't already infer. Ask the rest with `AskUserQuestion`. The
**must-ask** question is the sonic palette, and it must carry concrete previews.

**Q1 — Sonic palette (always ask, with real example mappings):**
Offer 3–4 directions grounded in what you actually found on disk. Typical menu:
- **8-bit / chiptune** — cohesive, retro, blip-and-bloop; great for terminal/QB64/PICO-8
  vibes. Weakness: no literal world sounds (a real door creak or siren won't exist).
- **Realistic / cinematic foley** — literal concept matches (real doors, coins,
  swords, explosions). Immersive; may clash with a tone/beeper aesthetic.
- **Hybrid (X-forward)** — one palette for arcade-y events, the other only where the
  first has no equivalent. Best coverage; mixed timbre.
- Populate each option's `preview` with 4–6 real `slot -> candidate_filename` lines
  from your index so the trade-off is visible, not abstract.

**Q2 — Constraints (ask if not obvious):**
- Max duration for one-shots (e.g. reject > 3 s except fanfares like `win`/`lose`).
- Avoid loop-designed files? (A file named `*_loop` still plays once in a one-shot
  engine — usually fine, and often a clean single sweep. Note it; don't auto-reject.)
- mono vs stereo, and any hard format requirement.

**Q3 — Sources/destination (ask only if unspecified).**

Record the answers before proceeding — they drive every match below.

## Step 2 — Build the index

Huge libraries (hundreds of thousands of files) can't be eyeballed. Index, then
grep. If a root is enormous, first look for a well-categorized SFX/foley pack inside
it (folders like `Sound Effects`, `Foley`, `SFX`, game-audio packs) and index that —
category folders do most of the concept-matching for you.

```sh
scripts/build-index.sh /tmp/audio_index.txt "DIR1" "DIR2"
# Then sanity-check scale and structure:
wc -l /tmp/audio_index.txt
rg -o '/[^/]+/[^/]+\.(wav|ogg|mp3|flac)$' /tmp/audio_index.txt | sed 's#/[^/]*$##' | sort | uniq -c | sort -rn | head
```

## Step 3 — Concept-match each slot

For every slot, grep the index for concept synonyms and prefer files whose **folder
category** matches the concept. Keep the chosen palette in mind (e.g. include or
exclude an `8BIT/` path segment).

```sh
# Example: candidates for a "treasure / loot / gold" slot, realistic palette
rg -iN 'coin|gold|money|loot|jewel|treasure' /tmp/audio_index.txt | rg -iv '8bit'
```

Matching guidance:
- Map the concept to a category first (door→DOORS, key→LOCKS_KEYS, boom→EXPLOSIONS,
  hit/crit→WEAPONS/IMPACTS, win/lose/levelup→MUSIC_EFFECTS, select/save→UI/BUTTONS,
  idle→a single water DROP beats a long ambience loop, secretpass→a stone SCRAPE, etc.).
- Differentiate near-duplicates deliberately: `hit` = clean sword strike, `crit` = a
  heavier body/hammer impact; `secretpass` = heavy stone grind, `search` = light
  feeling-along-the-wall scrape.
- You can't listen — judge by filename + folder + duration. Prefer descriptive,
  short, one-shot names over long/loop/ambience files (unless a fanfare).

Write the chosen matches to a tab-separated mapping file (`#` comments allowed):

```
# slot<TAB>absolute_source_path
treasure	/mnt/music/SFX/FOLEY/COINS/COINS_Rattle_01_mono.wav
boom	/mnt/music/SFX/EXPLOSIONS/Short/EXPLOSION_Short_Dark_Debris_stereo.wav
```

## Step 4 — Verify durations, then install

`install-from-mapping.sh` copies each source to `<dest>/<slot>.<ext>`, records
duration + provenance in `MANIFEST.tsv`, and **flags any missing sources** (those
become the make-in-sfxr list).

```sh
scripts/install-from-mapping.sh /tmp/mapping.tsv "DEST_DIR"
```

Before installing, spot-check outliers you already suspect are long:
```sh
ffprobe -v error -show_entries format=duration -of csv=p=0 "SOME_FILE.wav"
```
If a pick is too long for its event, go back to Step 3 and choose a shorter sibling.

## Step 5 — Report

Show the manifest as a table (slot / file / duration / source). Explicitly call out:
- Any slot with **no good match** or a weak/approximate one — recommend sfxr/Bfxr
  or a custom recording for those, and say why nothing on disk fit.
- Any deliberate reuse (same source family used for two related slots).

## Notes & gotchas

- **Each `Bash` call is a fresh shell** — re-declare helper functions every call, or
  just use the bundled scripts.
- **One file per slot.** If the target engine tries extensions in a fixed order
  (e.g. `.ogg` before `.wav`), two files with the same base name will shadow each
  other — keep exactly one.
- **Filenames must match the engine's expected names exactly** (case, spelling).
- Keep the mapping file and index in a scratch dir, not the user's project.
- Respect provenance: this scavenges the user's *own* files for their *own* project.
  Don't redistribute copyrighted sample-pack content beyond that use.
