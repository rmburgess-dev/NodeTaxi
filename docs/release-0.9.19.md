# NodeTaxi 0.9.19

Stable rolling re-plan.

- A full current leg stays frozen instead of swapping nodes as you walk.
- Once a completed node frees a slot, rolling re-planning can add a new nearby
  node.
- Added route-evaluation notes covering multiple waypoints, transport legs,
  fallback lines, and the 8/12/20 max-node tradeoff.

Requires TomTom. Install into `_forever_/Interface/AddOns/NodeTaxi`.
Source: https://github.com/rmburgess-dev/NodeTaxi
