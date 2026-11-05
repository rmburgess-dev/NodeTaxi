# NodeTaxi 0.7.0

Published, paired zone-transition coordinates for **WoW Forever 1.60.1**.

- Bundles 63 real connections from Carbonite's Classic `ZoneConnections`
  dataset: land passes, portals, boats, zeppelins and the tram, with coordinates
  on both sides of every connection.
- Cross-zone routing works immediately across the old world; no need to learn
  each border first. Land connections are preferred over transports.
- `/nt crossings` lists the exact points known from your current zone.
- Learned crossings and client map-link pins remain as overrides and for new
  zones not covered by the baked table.
- Example: Tirisfal 54.14,75.77 -> Silverpine 67.56,5.45; the full
  Tirisfal-to-Elwynn land chain is in the README.
- The Carbonite data file is GPLv3 and attributed separately; NodeTaxi's code
  remains MIT. See ATTRIBUTION.md and LICENSE-GPL-3.0.txt.

Requires TomTom. Install into `_forever_/Interface/AddOns/NodeTaxi`.
Source: https://github.com/rmburgess-dev/NodeTaxi
