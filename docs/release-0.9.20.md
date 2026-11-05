# NodeTaxi 0.9.20

Forward branch merges and complete leg lines.

- Each cluster merges at its furthest corridor projection; 2-opt only reorders
  the middle nodes, so a branch cannot end behind its entry and loop back.
- Every corridor leg now draws its line even when zero resource nodes fit the
  band. Middle zones no longer go blank.
- The 8-node default remains after comparing 8/12/20 across multiple waypoints;
  12/20 produce too much wandering for the intended UX.

Requires TomTom. Install into `_forever_/Interface/AddOns/NodeTaxi`.
Source: https://github.com/rmburgess-dev/NodeTaxi
