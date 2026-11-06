# NodeTaxi 0.9.25

All nearby nodes become circles.

- Every known node inside `/nt ring` now switches to the hollow circle on the
  world map and minimap, whether it is route-selected or only part of the
  all-node field.
- This fixes the small GatherMate-style icon remaining where the circle should
  be.
- Ring color still follows the node type; the next route node pulses.

Requires TomTom. Install into `_forever_/Interface/AddOns/NodeTaxi`.
Source: https://github.com/rmburgess-dev/NodeTaxi
