# Attribution

NodeTaxi's original code is by rmburgess-dev (MIT, see LICENSE). It stands on
several community projects:

## TomTom

Waypoint target, distance and map data are read through TomTom's public
callback API. TomTom is a required dependency and is not bundled.

- TomTom by Cladhaire, Ludovicus and contributors
- https://github.com/Nevcairiel/TomTom

## HereBeDragons

Zone/world coordinate conversion, map sizes and minimap projection use
HereBeDragons, which ships inside TomTom.

- HereBeDragons-2.0 by Nevcairiel and contributors

## Node data

`data.lua` contains normalized herb and ore coordinates compiled from public
public Classic coordinate data and standardized by NodeTaxi. It also includes
24 unique nodes observed by NodeTaxi players in Forever.

The coordinate values are factual map positions. Node icons are Blizzard item
icons resolved at runtime; no third-party artwork is bundled.

## Zone connection coordinates

`transitions.lua` is a coordinate table derived from Carbonite's Classic
`ZoneConnections` dataset:

- Carbonite, IrcDirk and contributors
- https://github.com/IrcDirk/Carbonite-All-in-One-Retail-Classic
- file: `Carbonite/Data/classic/ZoneConnections.lua` (commit `edc6226`)
- Carbonite is GPLv3. `transitions.lua` is distributed under GPLv3, not MIT;
  see LICENSE.

The table stores the paired zone-map coordinates Carbonite publishes for 63
land crossings, portals, boats, zeppelins and the tram. NodeTaxi uses those
points directly, converts the 0..100 zone percentages to normalised map
coordinates, and prefers land connections when choosing a route.

## Zone corridor polylines

`corridors.lua` is generated offline from the public navigation maps of
Shortest Path Forever:

- Shortest Path Forever by Cillian Berragan and contributors
- https://github.com/cjber/shortest-path-forever
- GPL-3.0-or-later
- The navmesh itself is **not** included; only derived entrance-to-exit
  walking polylines are shipped.

`corridors.lua` is distributed under GPLv3, not MIT; see LICENSE.

## Resource icons

Node icons are resolved at runtime from Blizzard item icons through
`GetItemIcon`. `tools/node_icons.json` maps NodeTaxi node IDs to Blizzard item
IDs. No icon files are redistributed with NodeTaxi.

## World of Warcraft

World of Warcraft, its icons and map data are property of Blizzard
Entertainment. NodeTaxi is an unofficial fan addon and is not affiliated with
or endorsed by Blizzard.
