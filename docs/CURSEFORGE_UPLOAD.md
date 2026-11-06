# CurseForge upload checklist

## Project

- **Name:** NodeTaxi
- **Slug:** nodetaxi
- **Summary:** NodeTaxi turns your TomTom target into a gathering-friendly journey: a smooth dashed route along real zone transitions, with short side-trips through nearby herbs and ore. 23,827 baked nodes, GatherMate2-style icons, and a full multi-zone map.
- **Category:** Map & Minimap
- **Game version:** WoW Forever 1.60.1 (Interface 16001)
- **License:** **Other / custom** — use the repository `LICENSE` as the
  license URL. The code is MIT, but `data.lua`, `transitions.lua` and `Media/`
  contain third-party data/art with their own terms (see `ATTRIBUTION.md`).
  Do not select plain MIT or plain GPL for the whole package.
- **License URL:** https://github.com/rmburgess-dev/NodeTaxi/blob/main/LICENSE
- **Project Distribution:** **Off** for the first upload. This disables
  third-party API distribution while the project remains available on
  CurseForge. The artwork is marked All Rights Reserved; do not authorize
  third-party redistribution until you have permission or replace it.
- **Source:** https://github.com/rmburgess-dev/NodeTaxi
- **Required dependency:** TomTom (CurseForge project 18808 / slug `tomtom`)

## Files

- **Upload:** `dist/NodeTaxi-0.9.27.zip`
- **Project icon:** `docs/icon-256.png` (or `docs/icon-512.png`)
- **Description:** paste `docs/CURSEFORGE.md` (English first, then Deutsch/Français/Español)
- **Release type:** Beta (first public release, Forever data snapshot)

## Upload steps

1. Create the project with the fields above.
2. Upload `NodeTaxi-0.9.27.zip` for game version 1.60.1.
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

## Third-party content note

`data.lua` is derived from *GatherMate2 Data Wowhead classic* (Forever tables),
`transitions.lua` and `corridors.lua` are GPLv3 data, and `Media/` is copied
from GatherMate2's artwork folder, which is marked ARR. All are attributed in
`ATTRIBUTION.md`; none is covered by NodeTaxi's MIT grant.

This is why the project license is **Other / custom**, not MIT or GPL alone.
The conservative distribution choice is **Off** until the ARR artwork is
permissioned or replaced. If you later enable API distribution, confirm the
artwork permission first and keep `LICENSE`, `LICENSE-GPL-3.0.txt` and
`ATTRIBUTION.md` in the project/source distribution.

### Can we just pick GPLv3?

Not for the package as it stands.

- The MIT source code is GPLv3-compatible, and `transitions.lua` /
  `corridors.lua` are already GPLv3. A combined code/data distribution can be
  GPLv3.
- `Media/` is GatherMate2 artwork marked **All Rights Reserved**. A GPLv3
  grant over the whole package would purport to grant rights you do not have.
- The node data package terms should also be confirmed before relicensing the
  combined work.

If you replace the ARR artwork with original/licensed icons and confirm the
node-data terms, then **GPLv3** becomes a clean choice. In that case, the
distribution toggle can be **On**, because GPLv3 permits redistribution.
Choosing GPLv3 while also trying to prohibit third-party distribution is
contradictory in spirit; use Other/custom plus Off until the art is resolved.
