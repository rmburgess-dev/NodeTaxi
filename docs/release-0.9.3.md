# NodeTaxi 0.9.3

One forward node line.

- The route is now exactly `start -> selected nodes in corridor order ->
  destination`.
- Removed corridor vertices from the drawn line and removed the
  return-to-projection step that created giant circles and double-backs.
- The corridor remains the hidden reference that selects and orders nodes.
- Same taxi-yellow dashed style for the current and later legs.

Requires TomTom. Install into `_forever_/Interface/AddOns/NodeTaxi`.
Source: https://github.com/rmburgess-dev/NodeTaxi
