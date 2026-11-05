# NodeTaxi 0.9.15

Cluster-scored routing.

- Nodes within the 100-yard branch radius form clusters.
- Clusters are ranked by node density versus corridor span instead of being
  consumed in arrival order.
- Each cluster's internal order gets a bounded 2-opt pass.
- Clusters whose corridor spans overlap an already selected cluster are
  skipped, keeping the route forward.
- `/nt max` still caps selected nodes per zone; raise it for dense fields.

Requires TomTom. Install into `_forever_/Interface/AddOns/NodeTaxi`.
Source: https://github.com/rmburgess-dev/NodeTaxi
