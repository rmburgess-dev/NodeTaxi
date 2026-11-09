# CurseForge upload checklist

## Project

- **Name:** NodeTaxi
- **Slug:** nodetaxi
- **Summary:** NodeTaxi turns your TomTom target into a gathering-friendly journey: a smooth dashed route along real zone transitions, with short side-trips through nearby herbs and ore. 23,842 baked nodes, Blizzard item icons, and a full multi-zone map.
- **Category:** Map & Minimap
- **Game version:** WoW Forever 1.60.1 (Interface 16001)
- **License:** **Other / custom** — use the repository `LICENSE` as the
  license URL. The code is MIT; `transitions.lua` and `corridors.lua` are
  GPLv3 route data. Node icons are resolved at runtime from Blizzard items.
  Do not select plain MIT or plain GPL for the whole package.
- **License URL:** https://github.com/rmburgess-dev/NodeTaxi/blob/main/LICENSE
- **Project Distribution:** **Off** for the first upload. This disables
  third-party API distribution while the project remains available on
  CurseForge.
- **Source:** https://github.com/rmburgess-dev/NodeTaxi
- **Required dependency:** TomTom (CurseForge project 18808 / slug `tomtom`)

## Files

- **Upload:** `dist/NodeTaxi-0.9.30.zip`
- **Project icon:** `docs/icon-256.png` (or `docs/icon-512.png`)
- **Description:** paste `docs/CURSEFORGE.md` (English first, then Deutsch/Français/Español)
- **Release type:** Beta (first public release, Forever data snapshot)

## Upload steps

1. Create the project with the fields above.
2. Upload `NodeTaxi-0.9.30.zip` for game version 1.60.1.
3. Paste the description from `docs/CURSEFORGE.md`.
4. Upload the icon.
5. Add TomTom as a required dependency.
6. After the project exists, copy its numeric project ID into `NodeTaxi.toc`:

   ```
   ## X-Curse-Project-ID: <id>
   ```

7. Rebuild the zip and upload a new file (do not overwrite the released file):

   ```
   python3 tools/package.py
   ```

## Pre-upload verification

```
luac -p data.lua route.lua core.lua overlay.lua options.lua
lua tests/route_spec.lua
lua tests/load_spec.lua
lua tests/seed_spec.lua
python3 tools/package.py
```

Expected archive: `NodeTaxi/NodeTaxi.toc` at the top level, 52 files, no
`tests/`, `tools/`, `docs/`, `.git`, or `.pkgmeta`.

## Data note

Node coordinates are compiled from public Classic data and standardized by
NodeTaxi. `transitions.lua` and `corridors.lua` are GPLv3 route data. Icons are
Blizzard item icons resolved at runtime through `GetItemIcon`; no icon files
are bundled.

Keep `LICENSE`, `LICENSE-GPL-3.0.txt` and `ATTRIBUTION.md` with the project.
