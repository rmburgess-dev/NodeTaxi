# NodeTaxi 0.9.2

Fix the node-to-node journey line.

- Fix nodes that projected onto one corridor point: the line no longer emits
  repeated `projection -> node` spurs (the Brill star).
- Same-progress nodes are ordered and chained directly, so the yellow dashed
  line passes through each node in sequence.
- All visible journey legs now use the same taxi-yellow dashed style; later
  legs are dimmed, not recolored cyan.
- The corridor remains hidden. Only the node-to-node line is drawn.

Requires TomTom. Install into `_forever_/Interface/AddOns/NodeTaxi`.
Source: https://github.com/rmburgess-dev/NodeTaxi
