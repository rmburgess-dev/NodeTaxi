# NodeTaxi

**Tracking-aware gathering routes for WoW Forever — follow your TomTom path, with short detours through nearby herbs and ore.**

NodeTaxi draws a dashed yellow route from you toward your current **TomTom** waypoint. It follows a hidden zone-to-zone walking corridor, makes brief side-trips to nearby resource nodes, then rejoins the path. It never moves your TomTom arrow, changes your destination, or edits your TomTom waypoints.

## Highlights

- **Follows your active tracking.** Find Minerals shows ore routes; Find Herbs shows herb routes. Switching tracking rebuilds the route. Override with `/nt kind auto|herb|ore|both`.
- **23,827 baked herb/ore nodes** across 44 Forever zones, including Zephras Isle and Riverglades. Every node is shown, explored or not, even with no route active.
- **GatherMate2-style node display.** Node-specific artwork at 12 px on the world map and 9 px on the minimap, full alpha, matching GatherMate2's default presentation.
- **All nearby nodes become rings.** Inside `/nt ring` (100 yd by default) every node switches from an icon to a hollow circle, so the game's own tracking dot stays visible in the middle.
- **Minimap field.** Every known node in the current zone is drawn on the minimap, including faded rim markers for nodes just outside the view. Updates at 20 FPS.
- **Cross-zone routing at real transitions.** Uses 63 paired Carbonite transition coordinates — land borders, portals, boats, zeppelins and the tram — not guessed map edges. Nodes are selected in every zone along the route.
- **Short resource side-trips.** After reaching a node, NodeTaxi chains nearby nodes within 100 yd, then merges back to the corridor. Up to 4 nodes per cluster and 8 per leg by default; both limits are configurable.
- **Curved, forward-moving line.** The corridor itself is hidden; the visible line is smoothed and never paints a separate spine or blue transition bars.
- **Learns from you.** Successful Herb Gathering and Mining casts are remembered. `/nt import gathermate2` imports local GatherMate2 data, and `/nt here` records a manual node.
- **Read-only toward TomTom.** No waypoint changes, no arrow hijack, no destination replacement.

## Requirements

- **TomTom** — required
- **WoW Forever 1.60.1**, Interface **16001**
- HereBeDragons is included with TomTom; no separate install

## Install

1. Install TomTom.
2. Install NodeTaxi into `_forever_/Interface/AddOns/NodeTaxi`.
3. `/reload`, then `/nt` for the command list.

## Quick start

Set a TomTom waypoint in the destination zone, make sure your gathering tracking is active, then:

```
/nt route
```

For example:

```
/way #1429 42.0 65.0 Goldshire
/nt route
```

Open the world map and zoom out to Eastern Kingdoms to see the full multi-zone route. The current leg is bright; later legs are paler. The minimap shows the current area.

Useful first checks:

```
/nt preview      -- synthetic route to test the overlay
/nt allnodes on  -- show every known node (default)
/nt debug        -- client, tracking, position, snapshot and overlay state
```

## Common commands

| Command | Effect |
| --- | --- |
| `/nt route` | Build or rebuild the route to TomTom's arrow target |
| `/nt stop` | Clear the drawn route |
| `/nt dest` | Show the current TomTom target |
| `/nt allnodes on\|off` | Toggle the full known-node field |
| `/nt kind auto\|herb\|ore\|both` | Resource filter; `auto` follows active tracking |
| `/nt max 8` | Maximum selected route nodes per leg |
| `/nt cluster 4` | Maximum nodes selected from one nearby cluster |
| `/nt spur 100` | Maximum yards a selected node may pull away from the route |
| `/nt width 300` | Corridor search half-width in yards |
| `/nt replan 30` | Movement before the remaining leg is re-evaluated (0 = off) |
| `/nt ring 100` | Distance where any nearby icon becomes a hollow circle |
| `/nt detour 1.8` | Route-length / direct-distance budget |
| `/nt here [herb\|ore]` | Record a node at your current position |
| `/nt near [yd]` | List known nodes around you and their source |
| `/nt import gathermate2` | Import your local GatherMate2 herb/ore data |
| `/nt seed` | Show the baked snapshot version |
| `/nt debug` | Print client, tracking, position, icon and snapshot diagnostics |

Run `/nt` in game for the complete list, including log, validation, crossing and preview commands.

## Data notes

The baked snapshot is from **GatherMate2 Data Wowhead classic v2026-11-05** (Forever tables), a Wowhead-derived package by Marrtin based on Spinx's classic data and Wowhead coordinate submissions.

- **13,332 herbs + 10,495 ore = 23,827 nodes** across 44 zones.
- Nine Tirisfal veins from the player's saved NodeTaxi scan are merged via `tools/extra_nodes.json`.
- Mount Hyjal and Shen'dralas currently have no baked nodes.
- Coordinates are user submissions at roughly two-decimal precision; treat markers as approximate and use the rings to confirm live nodes.

Node IDs and matching artwork come from GatherMate2's tables and `Artwork/` folder. See `ATTRIBUTION.md` for full credits and third-party terms.

## Limitations

- **Not an autopilot.** The route is a suggestion. Terrain between published points is not fully modelled; cliffs, water, walls and flight paths are not avoided.
- **Side-trips use local distance**, not a full walkability mesh. Zones without a generated corridor, and transport legs, use a fallback line through the selected nodes or leg endpoints.
- **The snapshot can be stale.** Let NodeTaxi learn from your casts and use `/nt import gathermate2` after updating GatherMate2 data.
- **The all-node field is intentionally dense.** Use `/nt allnodes off` for a route-only view, or lower the ring distance.
- NodeTaxi is herb/ore only; it does not route to fishing pools or treasure.

## Credits

TomTom (Cladhaire, Ludovicus), HereBeDragons (Nevcairiel), GatherMate2 and GatherMate2_Data (Nevcairiel, kagaro, Xinhuan, Spinx, Marrtin), Carbonite transition data, the Shortest Path Forever navmesh work, Wowhead contributors, and Blizzard's world data.

**Source:** https://github.com/rmburgess-dev/NodeTaxi
