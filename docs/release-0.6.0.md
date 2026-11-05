# NodeTaxi 0.6.0

Cross-zone routing for **WoW Forever 1.60.1**.

- Targets in another zone on the same continent now get a border leg:
  NodeTaxi samples the world-space line, finds the zone crossing, routes
  through the current zone's nodes to that exit, and rebuilds the next leg
  after you cross.
- A faint continuation line on the world map shows the following zones.
- Falls back to the current zone's map-rectangle edge when zone sampling is
  unavailable.
- Cross-continent targets (ships, zeppelins, portals) are reported as
  unsupported instead of drawing an ocean line.
- Per-zone re-planning, tracking filtering, ring markers and the persistent log
  keep working on each leg.

Requires TomTom. Install into `_forever_/Interface/AddOns/NodeTaxi`.

Source: https://github.com/rmburgess-dev/NodeTaxi
