# NodeTaxi 0.9.22

Exact cluster branch order.

- Normal clusters (up to 8 nodes) use an exact open-path order from entry to
  the forward merge point.
- Large clusters keep the bounded heuristic.
- The merge endpoint remains pinned forward, so the branch cannot loop behind
  its entry.
- Same 100-yard candidate band, 8-node default, and fallback lines.

Requires TomTom. Install into `_forever_/Interface/AddOns/NodeTaxi`.
Source: https://github.com/rmburgess-dev/NodeTaxi
