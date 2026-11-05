# NodeTaxi 0.9.13

Branch through nearby node clusters.

- At each reached node, take every unvisited node within 100 yards of it and
  chain the cluster.
- When no nearby node remains, merge back to the furthest corridor point
  reached by the branch and continue along the corridor.
- A tight cluster like the three Elwynn nodes is now visited together instead
  of one being chosen per progress band.
- The 100-yard `/nt spur` limit controls both corridor deviation and node-to-node
  branch distance.

Requires TomTom. Install into `_forever_/Interface/AddOns/NodeTaxi`.
Source: https://github.com/rmburgess-dev/NodeTaxi
