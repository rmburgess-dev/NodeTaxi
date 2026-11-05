# NodeTaxi

**Tracking-aware gathering routes for WoW Forever (1.60.1 / Interface 16001).**

NodeTaxi draws a dashed "taxi" path through herb and ore nodes between you and
your current **TomTom** waypoint. It never adds, removes, or retargets TomTom
waypoints — your arrow and destination stay exactly where they were.

## Features

- **23,818 baked Forever nodes** across 44 zones, including Zephras Isle and
  Riverglades.
- **Follows your tracking.** With Find Minerals up you see only ore nodes; with
  Find Herbs, only herbs. Switching tracking rebuilds the route automatically.
  Override with `/nt kind auto|herb|ore|both`.
- **Per-node icons.** Copper Vein uses copper art, Tin Vein tin, Peacebloom
  peacebloom, and so on, with a generic fallback for nodes with no known
  species.
- **Re-plans as you move.** Every 30 yards the remaining nodes are re-ordered
  from your current position; collected nodes are never revisited. Tune with
  `/nt replan`.
- **Crosses zone borders.** Targets in another zone on the same continent get a
  border leg: NodeTaxi finds the crossing, routes through this zone's nodes to
  it, and rebuilds after you cross. A dim continuation shows the following
  zones. Cross-continent trips are reported as unsupported.
- **Hollow rings up close.** Inside 100 yards the icon becomes an empty ring,
  so the game's own tracking dot remains visible in the center. Tune with
  `/nt ring`.
- **Learns from you.** Every successful Herb Gathering or Mining cast is
  remembered, and stale snapshot nodes near a learned node are suppressed.
- **Read-only toward TomTom.** No waypoint changes, no arrow hijack.

## Requires

- **TomTom** (required)
- WoW Forever 1.60.1, Interface 16001
- HereBeDragons ships inside TomTom; no separate install

## Install

1. Install TomTom.
2. Install NodeTaxi.
3. `/reload`, then `/nt` for the command list.

## Quick start

```
/nt preview     -- draw a synthetic route to check the overlay
/nt route       -- build a route to the current TomTom arrow target
/nt debug       -- client, tracking, position, icon paths, snapshot version
```

Set a TomTom waypoint, make sure your gathering tracking is active, and the
route appears on the world map and minimap.

## Commands

| Command | Effect |
| --- | --- |
| `/nt route` | build/rebuild the route to TomTom's arrow target |
| `/nt stop` | clear the drawn route |
| `/nt dest` | show the TomTom target |
| `/nt here [herb\|ore]` | remember a node where you stand |
| `/nt nodes` | learned + baked node counts |
| `/nt near [yd]` | list known nodes around you and their source |
| `/nt validate` | compare your spot with the baked snapshot |
| `/nt log [n\|clear\|chat on\|off]` | diagnostic log |
| `/nt kind auto\|herb\|ore\|both` | resource filter; defaults to active tracking |
| `/nt width 300` | corridor half-width, yards |
| `/nt max 8` | maximum nodes per route |
| `/nt detour 1.8` | route length / direct distance |
| `/nt replan 30` | movement before re-ordering (0 = off) |
| `/nt ring 100` | distance where icons become rings (0 = off) |
| `/nt import gathermate2` | import your local GatherMate2 data |
| `/nt seed` | show the baked snapshot version |
| `/nt debug` | client, tracking, cross-zone leg, icon paths, snapshot |

## Data notes

The baked snapshot is from **GatherMate2 Data Wowhead classic v2026-10-17**
(Forever tables), a Wowhead-derived package. Old-world zones are dense and
roughly 92% overlap with the mature Classic Era table; Zephras Isle and
Riverglades are included. Mount Hyjal and Shen'dralas have no baked nodes yet.
Node coordinates are user submissions at roughly two-decimal precision, so
treat markers as approximate and use the rings to confirm live nodes.

Node IDs and matching artwork come from GatherMate2's node tables and
`Artwork/` folder. See `ATTRIBUTION.md` for credits and `LICENSE` for the
third-party data/art terms.

## Credits

TomTom (Cladhaire, Ludovicus), HereBeDragons (Nevcairiel), GatherMate2 and
GatherMate2_Data (Nevcairiel, kagaro, Xinhuan, Spinx, Marrtin), Wowhead's
contributors, and Blizzard's world data.

Source: https://github.com/rmburgess-dev/NodeTaxi
