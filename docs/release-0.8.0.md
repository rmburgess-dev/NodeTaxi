# NodeTaxi 0.8.0

Full multi-zone resource path for **WoW Forever 1.60.1**.

- Plans selected nodes and a path for **every zone** on a cross-zone route, not
  just the player's current zone.
- Each future leg starts at the previous crossing's real entry point, ends at
  the next real exit, and uses the same corridor/detour/max-node settings.
- World map: current leg bright, later legs dim, with all future node icons and
  their dashed paths. Zoom out to the continent to see them.
- Minimap and next-node guidance stay on the current leg.
- Chat reports current-leg nodes plus the total nodes and zones planned.
- `/nt replan` keeps the current and future display legs in sync.

Requires TomTom. Install into `_forever_/Interface/AddOns/NodeTaxi`.
Source: https://github.com/rmburgess-dev/NodeTaxi
