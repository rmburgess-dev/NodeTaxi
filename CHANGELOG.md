# Changelog

## 0.6.0 - 2026-11-04

- Add cross-zone routing for targets on the same continent. NodeTaxi samples
  the world-space line to find the zone border, plans the current zone's nodes
  to that exit, and rebuilds the next leg after crossing.
- Draw a faint continuation line through the following zones on the world map.
- Add a map-rectangle fallback when zone sampling is unavailable, and explicit
  messaging for cross-continent targets.
- Keep `/nt replan`, tracking filtering and ring markers working per leg.

## 0.5.0 - 2026-11-04

- Follow the player's active minimap tracking by default (`/nt kind auto`);
  Find Minerals shows only ore, Find Herbs only herbs. Tracking changes rebuild
  the route automatically.
- Preserve GatherMate2 node IDs in the baked snapshot and use per-node art:
  Copper Vein, Tin Vein, Iron Deposit, Peacebloom, etc.
- Bundle 46 node-ID icon mappings under `Media/`.
- Learned nodes inherit the nearest snapshot node ID; existing learned nodes are
  backfilled at login. GatherMate2 imports preserve node IDs.
- `/nt debug` lists active tracking types and the resolved icon paths.

## 0.4.0 - 2026-11-04

- Resource icons replace diamonds at range; hollow rings within `/nt ring`.
- Icons use Herb Gathering/Mining spell textures with item-icon fallbacks.

## 0.3.3 - 2026-11-04

- Fix a vertical mirror in the world-map overlay (`y` is top-down). The minimap
  and the learned-vs-seed comparison were already correct.
- Add canvas/projection orientation tests.

## 0.3.2 - 2026-11-04

- Add the persistent diagnostic log (`/nt log`, `/nt validate`) recording the
  nearest baked node distance for every gather.
- Add `/nt near` to list nearby known nodes and their source.
- Suppress stale snapshot nodes within 60 yards of a learned node.

## 0.3.0 - 2026-11-04

- Re-plan the remaining route every 30 yards of movement and after each node.
- Hollow ring markers within 100 yards (the game's tracking dot remains visible
  in the center).
- Add `/nt replan` and `/nt ring`.

## 0.2.0 - 2026-11-04

- Bake 23,818 Forever herb/ore nodes (44 zones) into `data.lua` as a read-only
  runtime layer, without bloating SavedVariables.
- Add `/nt seed` diagnostics and versioned snapshot data.

## 0.1.0 - 2026-11-04

- Initial prototype: read TomTom's arrow target without modifying it, corridor
  route planning, world-map/minimap dashed overlays, node learning from
  gathering casts, GatherMate2 import.
