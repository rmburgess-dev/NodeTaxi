# NodeTaxi 0.9.32

Cleaner world map by default.

- World-map known-node field now defaults to **off**; the map shows the route
  and selected nodes unless `/nt allnodes on` is enabled.
- Minimap known-node field remains **on** by default.
- New `/nt minimapnodes on|off` command and separate settings checkbox.
- Existing installs with the old world-map field enabled migrate to the new
  default.
- Route behavior, Blizzard item icons and node data are unchanged.

Requires TomTom. Install into `_forever_/Interface/AddOns/NodeTaxi`.
Source: https://github.com/rmburgess-dev/NodeTaxi
