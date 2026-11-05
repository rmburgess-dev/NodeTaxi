# NodeTaxi 0.9.14

Branches can extend away from the road.

- The branch starts at a node within the corridor deviation limit.
- After that, every unvisited node within 100 yards of the current node is
  eligible, regardless of its distance from the corridor.
- The branch continues until no nearby node remains, then merges back at the
  furthest corridor point reached.
- `/nt max` still caps the selected nodes per zone; raise it for dense fields.

Requires TomTom. Install into `_forever_/Interface/AddOns/NodeTaxi`.
Source: https://github.com/rmburgess-dev/NodeTaxi
