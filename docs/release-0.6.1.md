# NodeTaxi 0.6.1

Real-crossing fix for **WoW Forever 1.60.1**.

- Removes the geometric border and map-rectangle fallback that could send you
  at a mountain (including the reported 0 yd "Silverpine exit" in Tirisfal).
- Cross-zone legs now use only real points:
  - crossings learned automatically from an actual `ZONE_CHANGED_NEW_AREA`
    transition, recording both sides of the pass; or
  - the client's `C_Map.GetMapLinksForMap` transition pins.
- If no real crossing is known for the next zone, NodeTaxi refuses the leg and
  tells you; walk through the border or portal once and it learns the point.
- `/nt crossings` lists known crossings/map links from the current zone.
- Skips hearth/teleport/flight jumps when learning crossings.

Requires TomTom. Install into `_forever_/Interface/AddOns/NodeTaxi`.
Source: https://github.com/rmburgess-dev/NodeTaxi
