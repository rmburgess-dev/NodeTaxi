# NodeTaxi 0.9.0

Road/walk corridor spines for **WoW Forever 1.60.1**.

- Adds `corridors.lua`: 121 compact entrance→exit walking polylines for 46
  zones, generated offline from Shortest Path Forever's public navigation maps.
- The world map and minimap now draw the corridor spine instead of joining
  resource nodes with straight lines. Nodes remain detour icons.
- First and last legs use the nearest published endpoint plus a short
  connector. Covered intermediate legs use their exact entrance/exit pair.
- No runtime navmesh, no Polestar dependency, and no 12 MB data pack: the
  corridor table is 94 KB.
- Uncovered zone legs show node icons and real transition points only; no
  invented straight line.
- Corridor data is GPLv3 and attributed separately; NodeTaxi's code remains MIT.

Requires TomTom. Install into `_forever_/Interface/AddOns/NodeTaxi`.
Source: https://github.com/rmburgess-dev/NodeTaxi
