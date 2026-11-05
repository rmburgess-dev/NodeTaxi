# NodeTaxi 0.9.1

Keep the node-to-node journey line, hide the corridor reference.

- The world map and minimap again show the original dashed taxi line from
  player through resource nodes to the destination.
- The corridor is now only an underlying reference: nodes are selected and
  ordered by their progress along it, and the visible line follows the
  corridor between nodes while detouring to each node.
- The corridor spine is no longer painted as a separate line.
- `/nt replan` no longer re-orders corridor-planned nodes along a straight line.
- Uncovered zone legs still show only real transition points/node icons; no
  invented straight line.

Requires TomTom. Install into `_forever_/Interface/AddOns/NodeTaxi`.
Source: https://github.com/rmburgess-dev/NodeTaxi
