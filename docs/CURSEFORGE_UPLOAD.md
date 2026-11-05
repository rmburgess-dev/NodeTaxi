# CurseForge upload checklist

## Project

- **Name:** NodeTaxi
- **Slug:** nodetaxi
- **Summary:** Tracking-aware gathering routes for WoW Forever: dashed taxi paths through herb/ore nodes between you and your TomTom waypoint.
- **Category:** Map & Minimap
- **Game version:** WoW Forever 1.60.1 (Interface 16001)
- **License:** Other / custom — point at the repository `LICENSE`. The code is
  MIT, but `data.lua`, `transitions.lua` and `Media/` contain third-party data/art with their own
  terms (see `ATTRIBUTION.md`). Do not select plain MIT for the whole package.
- **Source:** https://github.com/rmburgess-dev/NodeTaxi
- **Required dependency:** TomTom (CurseForge project 18808 / slug `tomtom`)

## Files

- **Upload:** `dist/NodeTaxi-0.9.12.zip`
- **Project icon:** `docs/icon-256.png` (or `docs/icon-512.png`)
- **Description:** paste `docs/CURSEFORGE.md`
- **Release type:** Beta (first public release, Forever data snapshot)

## Upload steps

1. Create the project with the fields above.
2. Upload `NodeTaxi-0.9.12.zip` for game version 1.60.1.
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
luac -p data.lua route.lua core.lua overlay.lua
lua tests/route_spec.lua
lua tests/load_spec.lua
lua tests/seed_spec.lua
python3 tools/package.py
```

Expected archive: `NodeTaxi/NodeTaxi.toc` at the top level, 50 files, no
`tests/`, `tools/`, `docs/`, `.git`, or `.pkgmeta`.

## Third-party content note

`data.lua` is derived from *GatherMate2 Data Wowhead classic* (Forever tables)
and `Media/` is copied from GatherMate2's artwork folder, which is marked ARR.
Both are attributed in `ATTRIBUTION.md`; neither is covered by NodeTaxi's MIT
grant. CurseForge may ask about redistribution rights; have an answer ready
(permission, replacement art, or an import-only data model).
