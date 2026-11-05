# NodeTaxi 0.9.4

Efficient, zone-wide node selection.

- Fix a units bug in the corridor filter: it was comparing normalized map
  distance against a yard setting, effectively accepting the whole zone.
  Silverpine now has 121 ore nodes within 300 yards of the southbound
  corridor, and the selector spreads picks across them.
- Pick one node per progress band instead of taking the first eight near the
  entrance, so nodes are represented through the whole zone.
- Run a bounded 2-opt pass so the visible node chain is one efficient forward
  line without crossings or backtracks.
- Corridor remains hidden; only the node-to-node taxi line is drawn.

Requires TomTom. Install into `_forever_/Interface/AddOns/NodeTaxi`.
Source: https://github.com/rmburgess-dev/NodeTaxi
