# Route evaluation

This is the working comparison used to choose the current defaults. It is not
a promise that every path is optimal; it is the evidence for the current
heuristic and the list of remaining compromises.

## Waypoint comparison

Starting point unless noted: Tirisfal Glades (1420), `0.618, 0.523`, mining
tracking, 100-yard node/neighbor radius, 8 nodes per leg.

| Target | Legs | Corridor legs | No-corridor legs | Selected nodes |
|---|---:|---:|---:|---:|
| Elwynn Forest, Goldshire | 11 | 11 | 0 | 88 |
| Stranglethorn Vale, Grom'gol | 2 | 1 | 1 | 9 |
| Hillsbrad, Tarren Mill | 3 | 3 | 0 | 24 |
| Hinterlands, Aerie Peak | 3 | 3 | 0 | 24 |
| Western Plaguelands, Chillwind | 2 | 2 | 0 | 16 |
| Ashenvale, Astranaar | 4 | 2 | 2 | 29 |
| Tanaris, Gadgetzan | 5 | 3 | 2 | 33 |
| Winterspring, Everlook | 6 | 4 | 2 | 45 |

The land routes are corridor-backed end to end. The zeppelin/boat and
uncovered destination legs use the fallback line (leg start → selected nodes
→ leg destination) rather than going blank.

## Max nodes per leg

For Elwynn Forest from Tirisfal:

| `/nt max` | Selected nodes | Raw line length | Character |
|---:|---:|---:|---|
| 8 | 88 | ~12.7k yd | Short, clustered side trips |
| 12 | 132 | ~14k yd | More stops, still local |
| 20 | 220 | significantly longer | Too much wandering for the intended UX |

The 8 default is the best fit for “known path with little journeys.” Users who
want denser coverage can raise it explicitly.

## Rolling stability

With a full 8-node leg, repeated `RefreshCurrentLeg` calls at sampled positions
along the leg kept the same selected node set (0 changes in the test run).
Previously the same walk changed the set 3 times, which would visibly reorder
the route while walking.

## Remaining compromises

- Branches use straight-line neighbor distance and smoothing, not a local
  walkability graph.
- Transport and uncovered-zone legs use fallback lines; they are not road
  paths.
- The whole-map all-node field is intentionally dense.
