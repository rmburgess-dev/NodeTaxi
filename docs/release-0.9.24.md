# NodeTaxi 0.9.24

Merged data and GatherMate2-style node display.

- Rebuilt from the updated Wowhead-derived GatherMate2 Forever package.
- Base package coordinates are unchanged (13,332 herbs + 10,486 ore); the nine
  extra Tirisfal veins from the saved NodeTaxi import are merged, for 23,827
  nodes total.
- World map: 12 px, full-alpha, node-specific GatherMate2 artwork.
- Minimap: 9 px, full-alpha icons for every known node in the current zone,
  even with no active route; out-of-range nodes fade onto the rim.
- Tracking filtering and `/nt allnodes` still apply.

Requires TomTom. Install into `_forever_/Interface/AddOns/NodeTaxi`.
Source: https://github.com/rmburgess-dev/NodeTaxi
