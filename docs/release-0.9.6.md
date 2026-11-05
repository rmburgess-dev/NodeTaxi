# NodeTaxi 0.9.6

Whole-map node field, explored or not.

- Zone view: every known node in that zone.
- Continent view: every known node in every zone under that continent.
- World view: every known zone.
- Nodes come from seed/learned data directly; no exploration check, so
  unexplored zones still show their resource field.
- The overlay sits above the fog/exploration layer.
- The field is visible with no active route.
- `/nt allnodes on|off` toggles it; tracking filter still applies.

Requires TomTom. Install into `_forever_/Interface/AddOns/NodeTaxi`.
Source: https://github.com/rmburgess-dev/NodeTaxi
