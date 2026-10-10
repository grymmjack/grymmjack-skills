---
name: open-in-pixel-viewer
description: Open a folder or file in kaleidotron — grymmjack's preferred image viewer AND audio/module player. Use this instead of xdg-open whenever presenting generated audio, images, or text art for review. Plays wav/flac/ogg/mp3/mid and tracker modules (mod/xm/s3m/it) with its own audio path, avoiding GStreamer level quirks.
---

# Open in kaleidotron

kaleidotron is grymmjack's own viewer/player (`~/git/kaleidotron`, binary `target/release/kaleidotron`; the old `pixelview` binary and `~/git/pixel-viewer` are retired). It is the
**preferred way to present anything for review** — audio renders, image batches,
ANSI/text art. Use it in place of `xdg-open`.

## Invocation

```bash
cd ~/git/kaleidotron
setsid nohup ./target/release/kaleidotron -f /path/to/folder >/tmp/pv.log 2>&1 < /dev/null & disown
```

Launch it **detached** (`setsid nohup … & disown`) so it outlives the tool call and
does not block.

### The one gotcha

The folder is a **flag**, not a positional argument:

```bash
kaleidotron -f /path/to/folder     # correct
kaleidotron /path/to/folder        # "unknown argument" — fails
```

`cargo run --release -- <folder>` fails for the same reason; pass `-f`.

Useful options: `-t/--thumbnail-size <N|WxH>`, and `-r/--render <PATH>…` for
headless conversion of text art to images (`--outdir`, `--scale`, `--font-9px`).
`--help` is accurate; read it rather than guessing.

If the binary is missing: `cd ~/git/kaleidotron && cargo build --release`.

## Why this instead of xdg-open

It has **its own audio playback path**, which matters concretely. A FLAC and the
WAV it came from were verified bit-identical (same peak, same RMS, no ReplayGain
tags), yet Parole — GStreamer-based — played the FLAC noticeably quieter. Opening
the same folder in kaleidotron played them at matching levels, which is what
identified the player as the variable rather than the files.

So when a level or quality difference is suspected between two audio files,
kaleidotron is also the better *diagnostic*: it removes the desktop audio stack from
the comparison.

## What it handles

| kind | formats |
|---|---|
| audio | wav, flac, ogg, mp3 |
| symbolic | mid / midi |
| trackers | mod, xm, s3m, it (via libxmp) |
| instruments | sf2, dls, sfz, xi |
| images | the usual raster formats |
| text art | ANS, XB/XBIN, RIP and friends, with SAUCE |

Because it plays MIDI and modules directly, a generated `.mid` can be auditioned
next to the audio rendered from it without converting anything.

## Presenting a review folder well

grymmjack has asked for this explicitly: **put only the files meant to be compared
in the folder, and name them so the order is obvious.** Stale or half-finished
renders sitting alongside cause real confusion about which is which.

```
0-source.mid
1-TARGET-soundfont.wav
2-OPL.ogg
3-CHIP.ogg
```

Delete previous audition folders rather than accumulating them.
