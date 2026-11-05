# Attribution

NodeTaxi's original code is by rmburgess-dev (MIT, see LICENSE). It stands on
several community projects:

## TomTom

Waypoint target, distance and map data are read through TomTom's public
callback API. TomTom is a required dependency and is not bundled.

- TomTom by Cladhaire, Ludovicus and contributors
- https://github.com/Nevcairiel/TomTom

## HereBeDragons

Zone/world coordinate conversion, map sizes and minimap projection use
HereBeDragons, which ships inside TomTom.

- HereBeDragons-2.0 by Nevcairiel and contributors

## Node data

`data.lua` is generated from the **Forever** tables of
*GatherMate2 Data Wowhead classic* `v2026-10-17`:

- package by Marrtin, based on Spinx's classic data
- coordinate collection originally by Wowhead users
- GatherMate2 itself by kagaro, Xinhuan, Nevcairiel and contributors
- generator: `tools/build_seed.py`, source layout documented by GatherMate2_Data

The coordinate values are factual map positions, but the compilation is
derived from those projects. `data.lua` is not covered by NodeTaxi's MIT
license; see LICENSE.

## Resource artwork

The per-node art in `Media/` (copper, tin, peacebloom, ...) comes from
GatherMate2's `Artwork/` folder (Nevcairiel and contributors), which is marked
All Rights Reserved. It is included here with attribution, not relicensed.
`tools/node_icons.json` maps GatherMate2 node IDs to those files.

## World of Warcraft

World of Warcraft, its icons and map data are property of Blizzard
Entertainment. NodeTaxi is an unofficial fan addon and is not affiliated with
or endorsed by Blizzard.
