# NodeTaxi

A route overlay for **WoW Forever (1.60.1 / Interface 16001)** that turns a
baked Forever node snapshot - plus the herb and ore nodes you learn in game -
into a dashed "taxi" path between you and the current TomTom arrow target.

It is deliberately **read-only towards TomTom**:

* no `TomTom:AddWaypoint`
* no `TomTom:SetCrazyArrow`
* no `TomTom:RemoveWaypoint`
* no changes to TomTom's arrow, destination or saved waypoints

NodeTaxi only listens to TomTom's public `ArrowTargetChanged` callback (and
reads the active target once at login) to learn *where* you are going.

## What it does

1. Starts with **23,818 baked herb/ore nodes** across 44 Forever zones, then
   learns more from your own **Herb Gathering** and **Mining** casts and
   manual `/nt here` marks. By default it follows the player's *active*
   minimap tracking (Find Herbs or Find Minerals) and only routes to that
   resource type.
2. Takes the current TomTom arrow target as the destination.
3. Keeps the known nodes that lie inside a corridor around the straight line
   between you and that destination.
4. Orders them with nearest-neighbour + 2-opt, within a node budget and a
   detour budget.
5. Re-evaluates the remaining route as you move (every 30 yards by default),
   so the order follows your actual position instead of the original start.
   Targets in another zone get a **real-crossing leg**: NodeTaxi uses paired
   zone-connection coordinates baked from Carbonite's Classic dataset, plus
   crossings learned from your actual zone changes and the client's map-link
   pins. It routes through this zone's nodes to the real point and rebuilds the
   next leg after you cross. A dim continuation line shows the following zones.
   It never guesses a geometric border or map edge.
6. Draws the result as **dashes on the world map** and on the **minimap**,
   with a Herb Gathering/Mining **resource icon** per node and a larger pulsing
   icon for the next one. Inside the ring distance (100 yd by default) the icon
   becomes a **hollow ring**: the game's own tracking dot can be seen through
   the middle, so you can tell whether a node is really there.

The player position is live, so the first dash segment updates as you run; the
node chain stays put until you collect a node, skip one, or rebuild.

## Install

Unzip the release so the layout is:

```
World of Warcraft/_forever_/Interface/AddOns/NodeTaxi/NodeTaxi.toc
World of Warcraft/_forever_/Interface/AddOns/NodeTaxi/core.lua
...
```

TomTom is a hard dependency. Restart the client once after adding the folder;
`/reload` is enough for later updates.

## Quick test (no farming required)

```
/nt preview
```

Draws a synthetic route from you toward the current TomTom target (or straight
ahead if there is none) so you can check the map/minimap look immediately.
`/nt stop` clears it.

Then, with a real TomTom waypoint set:

```
/nt route
```

## Commands

| Command | Effect |
| --- | --- |
| `/nt` | status + help |
| `/nt route` | build (or rebuild) the route to the TomTom arrow target |
| `/nt stop` | clear the drawn route (TomTom is untouched) |
| `/nt dest` | print the current TomTom arrow target |
| `/nt here [herb\|ore]` | remember a node where you stand |
| `/nt nodes` | node counts (learned / total, plus baked counts) |
| `/nt near [yd]` | list known nodes around you and whether they are baked, learned, or imported |
| `/nt validate` | compare your current spot with the baked snapshot and log the distances |
| `/nt log [n]` | show the last n diagnostic entries (default 15) |
| `/nt log clear` | empty the diagnostic log |
| `/nt log chat on\|off` | toggle the one-line gather message |
| `/nt seed` | show the baked Forever snapshot version |
| `/nt import gathermate2` | copy herb/ore nodes out of your local GatherMate2 data |
| `/nt skip` | skip the current node |
| `/nt preview` | synthetic demo route |
| `/nt width 300` | corridor half-width in yards (25-3000) |
| `/nt max 8` | maximum nodes per route (1-20) |
| `/nt detour 1.8` | route length budget as a multiple of direct distance |
| `/nt arrive 18` | yards at which a node counts as collected |
| `/nt replan 30` | yards moved before the remaining route is re-ordered (0 = off) |
| `/nt ring 100` | yards at which a node marker becomes a hollow ring (0 = off) |
| `/nt auto on\|off` | rebuild automatically when the TomTom target changes |
| `/nt kind auto\|herb\|ore\|both` | node filter; `auto` follows active tracking (default) |
| `/nt learn herb\|ore <spellID>` | teach a gather spell the addon does not know |
| `/nt watch` | log successful casts, to verify node learning |
| `/nt debug` | client, HBD, map canvas, position, target, overlay state |
| `/nt clear yes` | delete learned/imported nodes (the baked snapshot stays) |

Settings and learned/imported nodes persist account-wide in `NodeTaxiDB`; the
baked snapshot lives in `data.lua` and is never written to saved variables.

## How the route is chosen

* **Corridor**: nodes more than `width` yards from the player->target line (or
  behind you) are ignored. `/nt kind` can restrict the route to herbs or ore.
* **Budget**: `max(length / max(direct, 200 yd), ...) <= detour`; nodes are
  removed one at a time (the one that saves the most length) until the route
  fits both the node budget and the detour budget.
* **Order**: greedy nearest neighbour, then 2-opt with the player and the
  target pinned at the ends.
* **Re-planning**: after every `replan` yards of movement (and after each node
  is collected or skipped), the remaining nodes are re-ordered from the current
  position; collected nodes are never fed back in. The 2-second guard keeps a
  fast mount or flight path from rebuilding every tick.
* **Markers**: node-specific resource icons at distance - Copper Vein uses the
  copper ore art, Peacebloom the peacebloom art, and so on. The pristine
  artwork comes from GatherMate2's `Artwork/` folder and is bundled under
  `Media/`; node IDs from the snapshot select the icon. Learned nodes inherit
  the nearest snapshot node's ID, and GatherMate2 imports preserve the ID.
  A node with no known species uses the generic Herb Gathering/Mining icon.
  Within `ring` yards the icon is replaced by a hollow ring, so the game's own
  tracking dot remains visible in the middle.
* The planner is pure Lua (`route.lua`), so it runs without the WoW API and is
  covered by unit tests.

## Where the node data comes from

### Resource filter follows tracking

`/nt kind` defaults to `auto`. The addon asks the client for the active
tracking types (`C_Minimap.GetTrackingInfo`) and compares them with Find Herbs
(2383) and Find Minerals (2580). A miner with Find Minerals up sees only ore
nodes and ore routes; a herbalist sees only herbs. Switching tracking rebuilds
the route automatically on `MINIMAP_UPDATE_TRACKING`. `/nt kind herb`, `ore`, or
`both` overrides this; `/nt kind auto` returns to tracking-driven filtering.

### Baked zone connections (included)

`transitions.lua` is generated from Carbonite's Classic `ZoneConnections`
dataset (commit `edc6226`, GPLv3). It provides **paired** coordinates for 63
real connections — land passes, portals, boats, zeppelins and the tram — using
the same `UiMap` IDs as Forever. A target can have more than one connection
(for example two Dun Morogh passes); NodeTaxi keeps each and picks the one
nearest you. Land connections are preferred over transports when both reach
the destination.

The world map draws the node-to-node dashed line and the selected node icons
for every leg. The line follows the corridor reference between nodes and
detours to each icon; the corridor itself is not painted as a separate line.
If you are looking at the zone map, only that zone is visible; zoom out to the
continent to see the full multi-zone path.

Tirisfal Glades to Elwynn Forest, for example, uses:

```
1420 Tirisfal       54.14,75.77  ->  1421 Silverpine     67.56, 5.45
1421 Silverpine     66.36,79.80  ->  1424 Hillsbrad      14.35,46.20
1424 Hillsbrad      81.96,56.91  ->  1417 Arathi         20.34,29.73
1417 Arathi         45.45,89.06  ->  1437 Wetlands        51.06,11.95
1437 Wetlands       53.97,70.33  ->  1432 Loch Modan      25.57,10.47
1432 Loch Modan     47.19,80.82  ->  1418 Badlands        49.36, 7.97
1418 Badlands        1.09,62.92  ->  1427 Searing Gorge   76.63,56.67
1427 Searing Gorge  34.81,83.74  ->  1428 Burning Steppes 31.83,50.44
1428 Burning Steppes 78.85,82.50 ->  1433 Redridge        46.52, 8.56
1433 Redridge        8.95,71.90  ->  1429 Elwynn         93.21,72.27
```

The other Tirisfal option is Western Plaguelands: `84.09,70.49` on the
Tirisfal side, `28.62,57.46` in the Plaguelands. Cross-continent boats and
zeppelins are in the table too; `/nt crossings` prints the available points for
your current zone.

### Corridor backbones (included)

`corridors.lua` contains **121 compact entrance→exit walking polylines** for
the 46 Carbonite-connected zones, generated offline from the public
[Shortest Path Forever](https://github.com/cjber/shortest-path-forever)
navigation maps (GPLv3). It is 94 KB; the 12 MB navmesh is not bundled and
there is no runtime dependency.

NodeTaxi uses a corridor when both ends of a zone leg are known connection
points, but only as a **reference**: it selects nodes by their progress along
the corridor, then builds the visible dashed line through those nodes. For the
first and last leg it uses the nearest published endpoint and a short
connector to the player/target. Zones without a generated corridor fall back to
transition points and node icons only — no invented straight line. The
corridor spine itself is never painted.

### Baked Forever snapshot (included)

`data.lua` is generated from the **Forever** tables of *GatherMate2 Data
Wowhead classic* `v2026-10-17`, a Wowhead-derived package by Marrtin based on
Spinx's classic data. It keeps each node's coordinate key **and** its
GatherMate2 node ID, so the matching resource art can be selected:

* **13,332 herbs + 10,486 ore = 23,818 nodes** across 44 zones.
* Includes the new **Zephras Isle (2521)** and **Riverglades (2548)** zones.
* Compared with the mature Classic Era table, about 92% of the coordinate keys
  overlap; the remainder is new or changed.
* **Mount Hyjal (2482)** and **Shen'dralas (2652)** have no data in that
  snapshot yet, so those zones rely on your own gathering.

The snapshot is read-only addon data. It is merged into the route at query
time and is **not** copied into `NodeTaxiDB`, so 23k baked nodes do not bloat
SavedVariables; only nodes you learn or import are persisted. Its node IDs
select the bundled art under `Media/` (attribution: GatherMate2 Artwork by
Nevcairiel). `/nt seed` prints
the snapshot version and size, and `/nt nodes` shows how many baked nodes exist
in the current zone.

`tools/build_seed.py` regenerates `data.lua` from an extracted
`GatherMate2_Data/Forever` folder:

```
python3 tools/build_seed.py /path/to/GatherMate2_Data/Forever
```

### Refresh from a local GatherMate2 install (optional)

When a newer data package is released, you can pull it through GatherMate2
without waiting for a NodeTaxi build:

1. Install **GatherMate2** (Forever build) and a Forever-capable data package.
2. In game: `/gathermate` -> Import -> Herbs and Mining -> Import.
3. In game: `/nt import gathermate2`.

This reads `GatherMate2HerbDB` / `GatherMate2MineDB` from your saved variables,
decodes GatherMate2's coordinate keys, and merges them with the baked snapshot.

### Your own gathering

NodeTaxi's built-in learning and `/nt here` remain the only source guaranteed
to match the server's current spawns. Use it to correct stale coordinates and
to fill the new zones that the snapshot does not cover yet.

**Reliability caveat:** the baked coordinates are Wowhead user submissions,
stored at roughly two-decimal precision (about 100 yards in a large zone).
They are a good starting map, not ground truth; spawns can be phased, removed,
or changed by a Forever update.

## Map orientation (0.3.3 fix)

World-map y is **top-down**: y=0 is the north edge. `HereBeDragons` converts a
zone coordinate to world space as `worldY = top - height * y`, and RareScanner
draws map points at `-y * height` from `TOPLEFT`. An earlier build subtracted
y from 1 in the world overlay, which mirrored the path north/south; the
minimap was already correct. `NodeTaxi:MapPointToCanvas` now uses `y * height`
directly, and the test suite asserts that y=0.2 lands 20% from the top and that
a child map's top edge projects to the parent's `minY`.

## Validation and logging

Every gather writes a persistent entry to `NodeTaxiDB.log` (last 300 events):

- spell name and spell id
- zone, player coordinates, and zone size
- whether a node was learned or an existing one updated
- distance to the nearest **baked herb/ore node of the same kind**
- the nearest learned/imported node

That distance is the answer to "does the snapshot actually match the live
node?" Roughly:

| Distance to nearest baked node | Meaning |
| --- | --- |
| ≤ 60 yd | `matched`; the stale snapshot node is suppressed at route time and the learned node is used instead |
| 60-120 yd | `near`; probably the same node, but coarse or slightly stale |
| > 120 yd or none | `novel`; the snapshot does not know this node, and the learned position is added to the route |

`/nt validate` does the same comparison for wherever you are standing, without
harvesting, so you can check a visible node before touching it. `/nt log`
shows the most recent entries in chat; `/nt log clear` empties them. The log is
saved with the other NodeTaxi saved variables on `/reload` or logout, so it
survives a session and can be inspected offline.

## Known limitations (by design for this first version)

* **Corridor coverage is limited to generated pairs.** 121 entrance/exit
  pairs are covered; if a route uses a crossing not in `corridors.lua`, that
  zone leg shows only its node icons and real transition points, not a guessed
  road line. The corridor is a hidden reference; the visible line is the
  node-to-node dashed path.
* **Cross-zone routing uses published or observed crossings.** NodeTaxi never
  guesses a border from map geometry. It uses (a) the paired zone-connection
  coordinates in `transitions.lua`, published by Carbonite (GPLv3), for 63
  land/portal/boat/zeppelin/tram connections in the old world; (b) crossings it
  learned from an actual `ZONE_CHANGED_NEW_AREA` transition, with the real
  positions on both sides; and (c) the client's map-link pins
  (`C_Map.GetMapLinksForMap`). New zones or transitions missing from the baked
  table are learned the first time you cross them. It refuses a leg when no
  real point is known rather than pointing at a mountain. `/nt crossings` lists
  what it knows. Terrain between the published points is still not modelled.
* **No terrain data.** The dashes are straight lines between coordinates, not a
  navigable path. Cliffs, water, roads and flight paths are not modelled; the
  route is a suggestion, not an autopilot. Re-planning every 30 yards does not
  know about obstacles either.
* **Node data is a snapshot, not authoritative.** The baked data is from
  2026-10-17 and is Wowhead-derived; it can be stale, incomplete, or from a
  different phase. Mount Hyjal and Shen'dralas have no baked nodes yet. Learned
  nodes that do not match any snapshot node have no species ID, so they use the
  generic herb/ore icon. Let the addon learn from your own harvests and use
  `/nt import gathermate2` for refreshed packages.
* **Minimap drawing needs `C_Minimap.GetViewRadius`** (present in this client)
  and HereBeDragons for world coordinates. World-map drawing uses the map
  canvas that RareScanner also uses on this client.
* **No route in instances**, and cave/sub-zone maps are skipped when they do
  not agree with the outdoor zone.
* If `/nt watch` shows a gather spell the addon does not recognise, teach it
  once with `/nt learn herb <spellID>` (or `ore`); it is remembered in
  `NodeTaxiDB`. `/nt here` always works as a manual fallback.

## Files

| File | Purpose |
| --- | --- |
| `NodeTaxi.toc` | load order, dependency on TomTom |
| `data.lua` | generated Forever snapshot: coordinate keys, node IDs, icon map |
| `Media/` | bundled per-node resource art (Copper Vein, Peacebloom, ...) |
| `tools/build_seed.py` | regenerates `data.lua` from a GatherMate2 data package |
| `tools/node_icons.json` | node ID to artwork mapping used by the generator |
| `route.lua` | corridor filter, nearest neighbour, 2-opt, map projection |
| `core.lua` | node learning, GatherMate2 import, TomTom target adapter, state machine, slash commands |
| `overlay.lua` | world-map canvas overlay + minimap projection/overlay |
| `tests/route_spec.lua` | planner and projection unit tests |
| `tests/seed_spec.lua` | validates the baked snapshot (counts, coordinates) |
| `tests/load_spec.lua` | headless load/login/route/command smoke test |

Run the tests from the addon folder:

```
luac -p data.lua route.lua core.lua overlay.lua
lua tests/route_spec.lua
lua tests/load_spec.lua
lua tests/seed_spec.lua
```

## Development

```
git clone https://github.com/rmburgess-dev/NodeTaxi
cd NodeTaxi

luac -p data.lua route.lua core.lua overlay.lua
lua tests/route_spec.lua
lua tests/load_spec.lua
lua tests/seed_spec.lua

python3 tools/package.py      # dist/NodeTaxi-<version>.zip
python3 tools/make_icon.py    # docs/icon-256.png, docs/icon-512.png
```

`tools/build_seed.py` regenerates `data.lua` from an extracted
`GatherMate2_Data/Forever` folder; `tools/node_icons.json` maps GatherMate2
node IDs to the bundled artwork.

## License and credits

Original code is MIT (see `LICENSE`). The baked node data and the artwork in
`Media/` are third-party, attributed in `ATTRIBUTION.md`, and are not covered
by the MIT grant. TomTom is required and not bundled.

## In-game checklist

1. `/reload`, then `/nt debug` — confirm client 1.60.1, HereBeDragons yes,
   world map overlay ready or "not created" (open the map once).
2. `/nt preview` — dashed yellow path on the world map and minimap.
3. Set a TomTom waypoint, farm one herb or vein, `/nt route` — the node you
   just gathered should appear as a herb/ore icon on the path.
4. Walk to the next node: the icon should pulse and the route should advance
   to the next node when you arrive.
5. Move the TomTom waypoint: with `/nt auto on`, the route should rebuild and
   TomTom's own arrow must keep pointing exactly where it did before.
