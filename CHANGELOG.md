# Changelog

## 0.9.28 - 2026-11-05

- Keep one short “route updated: N nodes, Z zones” line for automatic
  TomTom-target and zone rebuilds, so quiet mode does not hide that the route
  actually changed. Routine node/gather/crossing messages stay quiet.
- Add a one-second TomTom target watcher as a fallback if the callback is
  missed.
- Add a settings-page checkbox for the short route-update line.
- Add regression coverage for automatic target updates with the quiet defaults.

## 0.9.27 - 2026-11-05

- Add a native **Settings → AddOns → NodeTaxi** page with routing, display,
  tracking, quiet-chat and action controls. `/nt options` opens it.
- Default automatic chat to quiet: no node-reached, crossing, gather or
  automatic route-summary messages. Manual `/nt` commands still respond.
- Default rolling re-plan to off. The route updates when the TomTom target
  changes or you enter a new zone; `/nt replan 30` enables rolling updates.
- Migrate existing 30-yard re-plan and chat-logging settings to the new quiet
  defaults while preserving explicit non-default values.
- Add `/nt quiet on|off` and `/nt options`.

## 0.9.26 - 2026-11-05

- Raise minimap redraw from every 0.35 s (~3 FPS) to every 0.05 s (~20 FPS).
- Keep minimap redraws running without an active route, so the all-node field
  no longer freezes.
- Cache per-zone node lists and world-coordinate conversions to avoid rebuilding
  the data set every frame.
- Leave the world-map redraw cadence unchanged.

## 0.9.25 - 2026-11-05

- Fix nearby-node markers: every known node within `/nt ring` now switches to
  the hollow circle on both the world map and minimap, not only route-selected
  nodes. This removes the small GatherMate-style icon appearing under/next to
  the circle.

## 0.9.24 - 2026-11-05

- Rebuilt the baked snapshot from the updated Wowhead-derived
  `GatherMate2_Data/Forever` package. The base package contains the same
  13,332 herb and 10,486 ore coordinates; the nine extra Tirisfal veins from
  the player's saved NodeTaxi import are merged via `tools/extra_nodes.json`
  for a total of 23,827 nodes.
- Match GatherMate2's default node presentation: 12 px full-alpha world icons,
  9 px full-alpha minimap icons, node-specific artwork.
- Show every known node in the current zone on the minimap even with no active
  route, including faded rim markers for nodes just outside the view.
- Keep tracking filtering and `/nt allnodes` behavior.

## 0.9.23 - 2026-11-05

- Add a per-cluster cap (`/nt cluster`, default 4) so one dense node group
  cannot consume the whole 8-node route and turn into a large zig-zag.
- Routes can still select up to `/nt max` nodes across multiple clusters.
- Document `/nt spur` and `/nt cluster` in the command table.
- Add regression coverage for the 5-node → 4-node cluster cap.

## 0.9.22 - 2026-11-05

- Solve each normal-sized cluster as an exact open path (Held-Karp) from its
  entry node through the cluster to its forward merge point. This replaces the
  nearest-neighbour/2-opt approximation for clusters of up to 8 nodes.
- Large clusters keep the bounded heuristic to avoid exponential work.
- The exact order preserves the forward merge endpoint, so branches still
  cannot loop back behind their entry.

## 0.9.21 - 2026-11-05

- Remove duplicate Catmull-Rom smoothing of the world route line.
- Dim the non-route all-node field (alpha 0.32, 7 px) so the yellow journey
  line reads first while every known node remains visible.
- Fix a stale test node after the 100-yard candidate-band change.

## 0.9.20 - 2026-11-05

- Pin each cluster's merge to its furthest corridor projection and 2-opt only
  the middle nodes, so a branch cannot finish behind its entry and loop back.
- Draw the corridor line on every leg that selects zero nodes, not just the
  first/last leg. No zone in a multi-zone route goes blank.
- Keep the 8-node default after the multi-waypoint comparison; 12/20 add too
  much wandering for the intended UX.

## 0.9.19 - 2026-11-05

- Allow rolling re-planning again once a completed node frees a slot, without
  reshuffling a still-full leg. The route stays stable while full and can add
  a new nearby node after a pickup.
- Add `docs/ROUTE_EVALUATION.md` with the multi-waypoint comparison and
  max-node tradeoff used to choose the current defaults.

## 0.9.18 - 2026-11-05

- Draw a fallback node line for legs with no generated corridor, including
  transport legs and zones not covered by the corridor data. This fixes blank
  destination zones after a zeppelin/boat route.
- Stop rolling re-planning once the current leg reaches `/nt max`, so a full
  route no longer swaps its selected nodes as the player moves.
- Add a regression test for the no-corridor fallback line.

## 0.9.17 - 2026-11-05

- Add rolling corridor re-planning. As you move, the current leg is trimmed
  at your projection onto the corridor and unvisited nodes ahead are
  re-clustered with the 100-yard branch rule.
- Newly nearby nodes can join the route while travelling, not just when the
  route was first built.
- Completed nodes are excluded from the rolling re-plan.

## 0.9.16 - 2026-11-05

- Smooth the displayed route polyline with Catmull-Rom interpolation on the
  world map and minimap, so corridor bends and branch joins are curves instead
  of right angles.
- Rendering-only change: node selection, branch logic, and detour limits are
  unchanged.

## 0.9.15 - 2026-11-05

- Replace first-come branch selection with cluster scoring: nodes within the
  100-yard branch radius form clusters, ranked by node density versus corridor
  span.
- 2-opt each cluster's internal node order.
- Skip clusters whose corridor span overlaps an already selected cluster, so
  the route never backtracks along the corridor to reach a newer cluster.
- The per-zone `/nt max` cap still applies; raise it for dense fields.

## 0.9.14 - 2026-11-05

- Fix the branch pool: once a branch starts near the corridor, every unvisited
  node within 100 yards of the current node is eligible, even if it is farther
  than 100 yards from the corridor itself.
- Branch starts still require a node within the corridor deviation limit.
- This lets a cluster extend away from the road until no nearby node remains,
  then merge back.

## 0.9.13 - 2026-11-05

- Replace one-node-per-band selection with a branch walk: after reaching a
  node, take every unvisited node within 100 yards of it, chaining the whole
  cluster, then merge back to the furthest corridor point reached.
- This means a tight cluster like the three nodes in Elwynn is walked as one
  branch instead of being split across bands.
- `/nt spur` controls both corridor deviation and the node-to-node branch
  radius (default 100 yards).

## 0.9.12 - 2026-11-05

- Set the default node deviation/sweep cap to **100 yards**, matching the
  minimap's typical 80-100 yard render band.
- Migrate the old 75-yard default for existing installs; custom values are
  preserved.
- Keep `/nt ring 100` as the close-marker threshold.

## 0.9.11 - 2026-11-05

- Draw the Tirisfal entry leg even when no resource node fits the 75-yard
  sweep band. First and last legs always retain a visible route line.
- This fixes the empty map when the current zone happened to select zero
  nodes.

## 0.9.10 - 2026-11-05

- Remove the remaining blue transition/gap lines. The map now draws only the
  node-to-node journey line and resource icons; no `crossPath` fallback or
  inter-leg cyan dashes.

## 0.9.9 - 2026-11-05

- Replace the straight out-and-back node spur with a smooth sweep: leave the
  corridor at the node projection, curve through the selected node(s), and
  rejoin the corridor at the next point ahead.
- Keep the 75-yard deviation limit and the whole-map node field.

## 0.9.8 - 2026-11-05

- Cap node deviations at 75 yards from the corridor by default. Nodes farther
  out remain visible in the all-node field but are not added to the route.
- Visit a selected node as a short out-and-back to the same road point, then
  continue forward, instead of drawing a long diagonal to the next corridor
  point.
- `/nt spur <yards>` tunes the limit.
- Keep the whole-map node field and corridor-shaped route.

## 0.9.7 - 2026-11-05

- Follow the corridor forward between nodes instead of drawing straight
  shortcuts. Each node is inserted once at its projection; the line never
  returns to an earlier projection or corridor vertex.
- Keep the whole-map node field from 0.9.6, including unexplored zones and
  no-route browsing.
- Remove the 2-opt shortcutting that was cutting across the reference.

## 0.9.6 - 2026-11-05

- Show all known nodes for the whole displayed map, not only the current zone
  or route zones: zone view shows that zone, continent view every zone under
  it, and the world view every known zone.
- Nodes are read directly from seed/learned data with no exploration check, so
  unexplored zones still show their resource field.
- Raise the world overlay above the fog/exploration layer.
- Show the node field even when there is no active route.
- Cache the per-map node lists and invalidate them when nodes change.

## 0.9.5 - 2026-11-05

- Draw every known node in each zone on the route as a small resource icon.
  Selected route nodes remain bright and connected by the node-to-node line.
- Add `/nt allnodes on|off` (default on) to show or hide the full node field.
- Tracking filtering still applies, so a miner sees ore and a herbalist sees
  herbs.

## 0.9.4 - 2026-11-05

- Fix corridor node filtering: normalized map distance was being compared
  against a yard value, so a 300 yd setting effectively accepted the whole
  zone. It now converts to yards before filtering.
- Select one node per progress band instead of taking the first eight near
  the entrance, so nodes are spread through the zone (Silverpine now gets
  nodes along the whole southbound leg).
- Run a bounded 2-opt pass on the selected nodes so the drawn line is one
  efficient forward chain without crossings or backtracks.

## 0.9.3 - 2026-11-05

- Make the drawn route one forward chain: start, selected nodes in corridor
  order, destination. Remove corridor vertices and the return-to-projection
  step that caused giant circles and double-backs.
- The hidden corridor now only selects and orders nodes.
- Keep the single taxi-yellow dashed style for current and later legs.

## 0.9.2 - 2026-11-05

- Fix the radial "star" around nodes that shared one corridor projection:
  the route now walks the corridor once and chains same-progress nodes
  directly node-to-node.
- Make all visible journey legs the same taxi-yellow dashed style; later legs
  are dimmed instead of switching to cyan.
- Keep the corridor itself hidden; only the node-to-node line is drawn.

## 0.9.1 - 2026-11-05

- Keep the original dashed node-to-node taxi line. The corridor is now only
  a hidden reference: nodes are selected/ordered along it, and the visible
  line detours through each node before continuing along the reference.
- Do not paint the corridor spine as its own line on the world map or
  minimap.
- Corridor-ordered nodes are stable; `/nt replan` no longer re-orders them
  along a straight line.

## 0.9.0 - 2026-11-05

- Add `corridors.lua`: 121 compact zone entrance→exit walking backbones
  generated offline from Shortest Path Forever's public navigation maps.
- Replace straight node-to-node lines on the world map and minimap with the
  corridor spine. Nodes remain side-trip icons; they are no longer joined.
- Use the nearest published endpoint with a short connector for the first and
  last leg; no runtime navmesh and no 12 MB dependency.
- Corridor data is GPLv3 and attributed separately from the MIT code.

## 0.8.0 - 2026-11-04

- Plan and display resource nodes for **every zone** on a cross-zone route,
  not just the current leg. Each leg starts at the previous crossing's real
  entry point, ends at the next real exit, and selects nodes within the same
  corridor/detour budget.
- World map: current leg bright, later legs dim, with all future node icons and
  their paths visible when the continent map is open.
- Minimap and next-node guidance remain current-leg only.
- Chat reports both the current leg and the total nodes/zones planned.
- `/nt replan` keeps the current leg and future display legs in sync.

## 0.7.0 - 2026-11-04

- Bake Carbonite's Classic `ZoneConnections` dataset into `transitions.lua`:
  63 paired, real coordinates for land passes, portals, boats, zeppelins and
  the tram, using Forever's `UiMap` IDs.
- Cross-zone routing now works immediately across the old world without
  needing to learn each border first. `/nt crossings` lists the exact points.
- Prefer land connections over transports when choosing a cross-zone path;
  boats, zeppelins and portals remain available for cross-continent trips.
- Keep learned crossings and client map links as overrides/new-zone coverage.
- Attribute the GPLv3 Carbonite data separately from NodeTaxi's MIT code.

## 0.6.1 - 2026-11-04

- Fix false cross-zone legs (for example a 0 yd "Silverpine exit" while
  standing in central Tirisfal). Zone transitions are no longer derived from
  map rectangles or a straight-line border sample.
- Use only real transition points: crossings learned from actual
  `ZONE_CHANGED_NEW_AREA` transitions (both sides recorded) and client
  `C_Map.GetMapLinksForMap` pins. If no real crossing is known, the leg is
  refused with an explanation.
- Add `/nt crossings` to list known crossings and map links from the current
  zone.
- Skip hearth/teleport/flight jumps when learning a crossing.

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
