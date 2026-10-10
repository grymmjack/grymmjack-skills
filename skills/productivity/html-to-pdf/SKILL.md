---
name: html-to-pdf
description: Convert an HTML file to a clean, full-bleed PDF on macOS with headless Chrome, and/or publish it as a shareable web page. Use when the user wants a PDF of an HTML page/report/runbook, wants to make a document shareable, or asks to turn HTML into a shareable file.
---

# HTML → shareable PDF (and web page)

The standing preference: **deliverables should be easy to share.** When you produce an HTML document (runbook, report, status page), offer both a **hosted web page** (Artifact tool) and a **PDF** — they often go to non-technical stakeholders who don't have repo/filesystem access. This skill covers the reliable HTML→PDF path on macOS plus the gotchas learned in practice.

## 1. Make the HTML print full-bleed

Before converting, add print CSS — otherwise the PDF gets white margins and **drops all background colors**. Put inside the page's `<style>`:

```css
@page { size: 1240px 1754px; margin: 0; }   /* desktop-ish width, ~A-ratio, zero margins = full bleed */
@media print {
  * { -webkit-print-color-adjust: exact; print-color-adjust: exact; }  /* CRITICAL: keeps background colors/tags */
  .topbar, .sticky { position: static; }     /* unstick fixed/sticky headers so they don't overlap */
  .topnav, canvas, #weave { display: none; } /* hide nav links + animated canvas (meaningless on paper) */
  .card, .section, .decision, li, pre { break-inside: avoid; }  /* don't split blocks across pages */
  pre { white-space: pre-wrap; word-break: break-word; }        /* stop long commands/code from clipping */
  section { break-before: page; }            /* one top-level section per page → clean, deterministic bookmark targets */
  section:first-of-type { break-before: auto; }
}
```

Giving each section its own page makes the bookmark mapping in step 4 deterministic (bookmark for section N = page N).

Tune `@page size` to the design's content width. Keep `margin: 0` for full-bleed. These rules are print-only, so they don't change the on-screen/web version — safe to leave in.

## 2. Convert with headless Chrome

```bash
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
# Chrome frequently will NOT self-exit after print-to-pdf — bound it with timeout.
timeout 30 "$CHROME" \
  --headless=new \
  --disable-gpu \
  --no-pdf-header-footer \
  --user-data-dir="$(mktemp -d)" \
  --print-to-pdf="/abs/path/output.pdf" \
  "/abs/path/input.html"
# macOS without GNU coreutils: use `gtimeout` instead of `timeout`.
```

Why each flag:
- `--headless=new` — modern headless mode (old `--headless` is deprecated and renders differently).
- `--disable-gpu` — avoids GPU-path flakiness in headless on macOS.
- `--no-pdf-header-footer` — drops Chrome's default date/URL/page-number chrome.
- `--user-data-dir="$(mktemp -d)"` — fresh throwaway profile per run. Reusing the default profile causes silent locking/contention if Chrome is already open, and stale state changes render output. New temp dir = deterministic.
- `--print-to-pdf` — output path. Use **absolute paths** for both input and output.

**The exit-hang (important):** if the page has a `requestAnimationFrame` loop (animations, a `<canvas>`), Chrome writes the PDF in the first few seconds but the renderer stays "busy" and the process **never exits** — so the call hangs until killed. `--virtual-time-budget=N` is *supposed* to fix this but in practice often doesn't for RAF pages. The reliable fix is `timeout 30` (above): it kills the lingering process after the PDF is already written. The PDF is complete and valid despite the non-zero exit code — verify it in step 3, don't trust the exit status. (Alternatively, run Chrome with the Bash tool's `run_in_background`, then `pkill -f "Google Chrome"` once the output file stops growing.)

Asset note: for local CSS/images to resolve, inline them in the HTML (best), or use absolute paths / a `file://` URL with the right base. Self-contained single-file HTML is the most reliable.

## 3. Verify the render — don't skip

```bash
pdfinfo output.pdf | grep -iE "Pages|Page size"      # page count + dimensions
pdftoppm -png -r 70 -f 1 -l 2 output.pdf /tmp/chk/p   # rasterize first pages to PNG
```
Then Read the PNGs and confirm: no margins, background colors present, nothing clipped, no ugly mid-block page breaks. (`pdfinfo`/`pdftoppm` are poppler. If absent: `qlmanage -t -s 1400 -o outdir output.pdf` for a page-1 thumbnail; `mdls -name kMDItemNumberOfPages` is unreliable for this — prefer `pdfinfo`.)

## 4. Add a clickable outline / bookmarks — ALWAYS

**Standing rule: every PDF must have a clickable bookmarks outline in the nav pane.** `--print-to-pdf` does not emit one — add it with pypdf after generating. Two parts make it clean:

1. The `break-before: page` print CSS (step 1) puts each top-level section on its own page, so bookmark page N = section N — no guessing.
2. Confirm the section→page mapping (`pdfinfo` for the count; render thumbnails to check boundaries), then run:

```python
from pypdf import PdfReader, PdfWriter
from pypdf.generic import NameObject
src = "/abs/path/output.pdf"
w = PdfWriter(); w.append(PdfReader(src))        # append preserves pages + existing link annotations
sections = [("Overview", 0), ("Section Two", 1), ("Section Three", 2)]   # (title, 0-based page index)
for title, pg in sections:
    w.add_outline_item(title, pg)                # nest with parent=<returned item> for sub-bookmarks
w._root_object[NameObject("/PageMode")] = NameObject("/UseOutlines")   # open with the bookmarks pane visible
tmp = src + ".tmp"
with open(tmp, "wb") as f: w.write(f)
import os; os.replace(tmp, src)
```

Then **verify**: re-open and confirm the outline item count, that `/PageMode` is `/UseOutlines`, the destination page of each item, and that any external URL link annotations survived (`page["/Annots"] → /A /URI`). pypdf's `append` keeps link annotations; a harmless "Annotation sizes differ" warning may print.

Fallbacks if pypdf is absent: `pikepdf` (`with pdf.open_outline() as o: o.root.append(pikepdf.OutlineItem(title, page_index))`), or Ghostscript pdfmark (`[/Title (..) /Page N /OUT pdfmark`). Prefer pypdf/pikepdf — they edit in place; gs re-distills the file.

## 5. Shareable web page (companion / alternative)

To share as a hosted page, call the **Artifact** tool on the same HTML file — it returns a private claude.ai URL the user can share. Redeploy to the same URL by passing the same file path. For best results follow the `artifact-design` skill when authoring the HTML, and keep it self-contained (strict CSP blocks external CDNs/fonts/images — inline everything, embed assets as `data:` URIs).

## Default handoff

Produce **both** by default — they serve different audiences:
- **Hosted web-page URL (Artifact)** — lead with it. Best for people on their Claude / internal team who can open a claude.ai link, and it stays current on redeploy.
- **Full-bleed PDF** — **always include it too.** It's the format for people *outside* their Claude who can't open the artifact link (external partners, vendors, anyone without access). Don't drop it.

So: publish the Artifact and give the URL first, then generate the PDF (steps 1–3 above) and hand over its path as well. Keep the source HTML.
