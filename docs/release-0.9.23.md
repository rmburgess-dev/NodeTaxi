# NodeTaxi 0.9.23

Per-cluster side-trip cap.

- Default `/nt cluster 4`: at most four nodes are taken from one nearby
  cluster, so the route can still total eight across two clean side-trips
  instead of one large zig-zag.
- `/nt cluster <n>` tunes the cap.
- Documented `/nt spur` and `/nt cluster`.
- Added regression coverage for a five-node cluster capped at four.

Requires TomTom. Install into `_forever_/Interface/AddOns/NodeTaxi`.
Source: https://github.com/rmburgess-dev/NodeTaxi
