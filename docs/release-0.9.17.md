# NodeTaxi 0.9.17

Rolling node inclusion.

- As you move, NodeTaxi projects you onto the current corridor, trims the
  corridor behind you, and re-clusters the unvisited nodes ahead.
- Nodes that become nearby while travelling can join the current leg.
- Completed nodes are excluded.
- Uses the same 100-yard branch/cluster rules and `/nt max` cap.

Requires TomTom. Install into `_forever_/Interface/AddOns/NodeTaxi`.
Source: https://github.com/rmburgess-dev/NodeTaxi
