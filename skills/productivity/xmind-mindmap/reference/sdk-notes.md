# XMind SDK notes & gotchas

`generate-xmind.js` uses the `xmind` npm package (v2.2.33) — the same toolchain
proven in DRAW's mind-map generator
([`DEV/XMIND-GENERATOR.md`](https://github.com/grymmjack/DRAW/blob/main/DEV/XMIND-GENERATOR.md))
and the `create-xmind` skill. An `.xmind` file is just a ZIP containing
`content.json`, `content.xml`, `manifest.json`, and `metadata.json`.

The high-level API has sharp edges. These are the ones the generator works
around — read before changing `generate-xmind.js`.

| Issue | Workaround (used in the script) |
|-------|--------------------------------|
| `createSheet()` (singular) overwrites `this.workbook` on each call — only the last sheet survives. | Always build with `createSheets([...])` (batch), even for one sheet. |
| `wb.theme(title, name)` relies on state that `createSheets()` never sets, and throws. | Theme each sheet directly: `sheet.changeTheme(new Theme({ themeName }).data)`. |
| `new Theme()` with no/invalid name throws `theme name undefined is not allowed`. | Only pass `snowbrush`, `robust`, or `business`; validated before building. |
| `topic.on(id)` cannot address a node by a custom id. | After `topic.add({ title })`, call `topic.cid()` to capture the auto-generated UUID, then recurse with it. |
| Cross-sheet links must point at a **topic** id, not a **sheet** id. | Link target is `sheet.getRootTopic().getId()`, formatted as `xmind:#<topicId>`. |
| `addHref()` lives on the raw xmind-model topic, not the high-level `Topic`. | Get it via `sheet.findComponentById(uuid)` (overview links) or `sheet.getRootTopic()` (back-links). |

## Verifying an output

An `.xmind` is a ZIP — inspect `content.json` to confirm the structure:

```bash
cd "$(mktemp -d)" && unzip -q /path/to/output.xmind && python3 -c "
import json
data = json.load(open('content.json'))
print('sheets:', len(data))
for i, s in enumerate(data):
    root = s['rootTopic']
    kids = root.get('children', {}).get('attached', [])
    print(f'  [{i}] {s[\"title\"]} — {len(kids)} children, rootHref={root.get(\"href\") or \"none\"}')
"
```

Multi-sheet output should show an `Overview` sheet plus one sheet per branch,
each detail sheet carrying a `rootHref` back to the overview.
