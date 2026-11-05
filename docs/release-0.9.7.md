# NodeTaxi 0.9.7

Forward corridor path, no shortcuts and no return spurs.

- Follow the corridor forward between selected nodes.
- Insert each node once at its projection onto the reference; never return to
  an earlier projection or corridor vertex.
- Remove the 2-opt shortcutting that cut across the reference.
- Keep the whole-map node field, including unexplored zones and browsing with
  no active route.

Requires TomTom. Install into `_forever_/Interface/AddOns/NodeTaxi`.
Source: https://github.com/rmburgess-dev/NodeTaxi
