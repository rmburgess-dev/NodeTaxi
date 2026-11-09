# NodeTaxi

**Tracking-aware gathering routes for WoW Forever — follow your TomTom path, with short detours through nearby herbs and ore.**

## English

### Overview

NodeTaxi is a companion for **TomTom** that turns your current arrow target into a gathering-friendly journey. Instead of only showing the next waypoint, it draws a dashed yellow route from your position toward that target, follows a hidden zone-to-zone travel corridor, and makes short side-trips to nearby resource nodes before rejoining the path.

It is designed for players who want to keep moving toward a destination while picking up herbs and ore along the way. NodeTaxi never moves the TomTom arrow, replaces the destination, or changes your TomTom waypoints.

### Main features

- **TomTom-native, read-only routing.** Your arrow and destination stay exactly where TomTom put them. NodeTaxi only reads the active arrow target.
- **Follows your gathering tracking.** With Find Minerals active, the route targets ore. With Find Herbs, it targets herbs. Switching tracking rebuilds the route. You can override this with `/nt kind auto|herb|ore|both`.
- **23,842 baked herb and ore nodes** across 44 WoW Forever zones, including Zephras Isle and Riverglades.
- **Every known node is shown.** The world map and minimap draw the full known-node field, whether the zone is explored or not, and even with no active route.
- **Blizzard item icons.** Node-specific icons at 12 px on the world map and 9 px on the minimap, resolved at runtime from Blizzard item IDs; no third-party artwork is bundled.
- **Hollow rings up close.** Inside `/nt ring` — 100 yards by default — every nearby node changes from an icon to a hollow circle, keeping the game's own tracking dot visible in the middle. This applies to the whole node field, not only the selected route.
- **Full minimap field.** All known nodes in the current zone appear on the minimap, including faded rim markers for nodes just outside the view. The overlay refreshes at 20 FPS.
- **Real cross-zone travel.** NodeTaxi uses 63 paired Carbonite transition coordinates for land borders, portals, boats, zeppelins and the tram, rather than guessing at geometric map edges.
- **Multi-zone node selection.** Every zone along the route can contribute nodes, not just your current zone. The current leg is bright; later legs are paler.
- **Short resource side-trips.** When the route reaches a nearby node, it chains other nodes within 100 yards, then merges back to the travel corridor. Up to 4 nodes are selected from one cluster and 8 per leg by default; both are configurable.
- **Forward-moving route shape.** The visible line is smoothed and follows the corridor. It does not paint a separate corridor spine or blue transition bars.
- **Stable while moving.** A full leg keeps its selected nodes instead of reshuffling as you walk. When a pickup frees a slot, the rolling re-plan can add a newly nearby node.
- **In-game settings page.** Configure routing, display, tracking and quiet chat at **Settings → AddOns → NodeTaxi**, or open it with `/nt options`.
- **Quiet by default.** Automatic node-reached, crossing and gather messages are suppressed, but one short **route updated** line still confirms each automatic target/zone rebuild. The route updates when the TomTom target changes; enable optional rolling updates with `/nt replan 30`.
- **Learns from you.** Successful Herb Gathering and Mining casts are remembered, and `/nt here` records a manual node.

### How the route is built

NodeTaxi separates the journey into two layers:

1. **A hidden travel corridor** between the real zone entrance and exit points.
2. **Local resource branches** that leave the corridor, visit a compact group of nodes, and merge back at a forward point.

The corridor is a reference for direction and zone transitions; it is not drawn as a separate line. The visible line is the resource journey itself: corridor segments, node visits, and short return merges, smoothed for readability.

The default limits are:

- 100-yard node deviation from the corridor
- 4 nodes per nearby cluster
- 8 selected nodes per leg
- Rolling re-plan off by default (updates when the TomTom target changes)
- Routine automatic chat quiet; one route-update line remains
- 100-yard ring distance

All of these are adjustable in game.

### Node display

The display is consistent across the world map and minimap:

- **World map:** 12 px node-specific icon at full alpha.
- **Minimap:** 9 px icon at full alpha for every known node in the zone.
- **Nearby nodes:** hollow circle inside the ring distance; all nearby nodes, not only the selected route.
- **Rim nodes:** nodes just outside the minimap view fade onto the rim rather than disappearing abruptly.
- **Route nodes:** the next node pulses; selected nodes stay visually connected to the dashed journey line.

If the full node field feels too dense for a particular session, `/nt allnodes off` switches to a route-only view. Tracking filtering still applies.

### Multi-zone travel

Routes can cross continents and use real transport links. NodeTaxi stores the paired transition points and plans a leg for each zone along the route. If a zone has no generated corridor, or the leg is a transport link, it falls back to a visible start → selected nodes → destination line instead of leaving the zone blank.

The route indicator always points toward the real exit for the current zone, then rebuilds after the zone change.

### Requirements

- **TomTom** — required dependency.
- **WoW Forever 1.60.1**, Interface **16001**.
- HereBeDragons is included with TomTom; no separate installation is needed.

### Installation

1. Install TomTom.
2. Install NodeTaxi into `_forever_/Interface/AddOns/NodeTaxi`.
3. Restart or `/reload`.
4. Run `/nt` in game for the command list.

### Quick start

Set a TomTom waypoint in the destination zone, make sure your gathering tracking is active, then run:

```
/nt route
```

Example:

```
/way #1429 42.0 65.0 Goldshire
/nt route
```

Open the world map and zoom out to see the full route. The current leg is bright; future legs are paler.

Useful first commands:

```
/nt preview      -- synthetic route to test the overlay
/nt allnodes on  -- show every known node (default)
/nt debug        -- position, tracking, snapshot, overlay diagnostics
```

### Configuration

Most options are available in **Settings → AddOns → NodeTaxi** (`/nt options`). Slash commands remain available for quick changes.

| Command | Effect |
| --- | --- |
| `/nt route` | Build or rebuild the route to TomTom's active target |
| `/nt stop` | Clear the route overlay |
| `/nt dest` | Show the current TomTom target |
| `/nt allnodes on\|off` | Toggle the full known-node field |
| `/nt kind auto\|herb\|ore\|both` | Resource filter; `auto` follows active tracking |
| `/nt max 8` | Maximum selected nodes per leg |
| `/nt cluster 4` | Maximum nodes from one nearby cluster |
| `/nt spur 100` | Maximum node deviation from the route |
| `/nt width 300` | Corridor search half-width |
| `/nt replan 0` | Rolling update distance (0 = only new TomTom target; default) |
| `/nt quiet on\|off` | Suppress automatic route/gather/crossing chat |
| `/nt options` | Open the in-game settings page |
| `/nt ring 100` | Distance where icons become hollow circles |
| `/nt detour 1.8` | Route-length budget relative to direct distance |
| `/nt here [herb\|ore]` | Record a node at your position |
| `/nt near [yd]` | List nearby known nodes and their source |
| `/nt seed` | Show the baked snapshot version |
| `/nt debug` | Print diagnostic information |

Run `/nt` for the complete list, including log, validation, crossing and preview commands.

### Data sources

The baked snapshot is compiled from public Classic node coordinates and standardized by NodeTaxi.

- **13,332 herbs + 10,510 ore = 23,842 nodes** across 44 zones.
- Nine Tirisfal veins from the player's saved NodeTaxi scan are merged through `tools/extra_nodes.json`.
- Mount Hyjal and Shen'dralas currently have no baked nodes.
- Coordinates are user submissions at roughly two-decimal precision. Treat markers as approximate and confirm live nodes with the tracking dot and rings.

Node IDs select Blizzard item icons at runtime through `GetItemIcon`. No icon files are redistributed.

### Limitations

- **Not an autopilot.** The route is a suggestion. Terrain between published points is not fully modelled; cliffs, water, walls and flight paths are not avoided.
- **Side-trips use local distance**, not a complete walkability mesh. Transport legs and zones without a generated corridor use fallback lines.
- **The snapshot can be stale.** Let NodeTaxi learn from your casts and update the baked snapshot when needed.
- **The all-node field is intentionally dense.** Turn it off or lower the ring distance if it feels busy.
- **Herb and ore only.** NodeTaxi does not route to fishing pools or treasure.
- **No TomTom changes.** NodeTaxi never adds, removes, or retargets TomTom waypoints.

### Troubleshooting

- `/nt debug` prints client build, tracking state, position, snapshot version, and overlay status.
- `/nt seed` confirms the baked data version.
- `/nt near 100` lists what NodeTaxi knows around you and whether each node came from the snapshot, an import, or a scan.
- `/nt allnodes off` gives a route-only view.
- If a route is empty, set the TomTom target to a zone map and run `/nt route` again.
- If the route shape is wrong, include the zone, tracking type and a screenshot in a GitHub issue.

### Privacy

NodeTaxi has no network code. It does not send data anywhere. Node data and settings live in your local SavedVariables.

### Support

Source, issue tracker and release history: https://github.com/rmburgess-dev/NodeTaxi

When reporting a problem, include the NodeTaxi version, `/nt debug` output, the zone, your active tracking type, and whether the route was cross-zone.

### Credits

TomTom (Cladhaire, Ludovicus), HereBeDragons (Nevcairiel), Carbonite transition data, the Shortest Path Forever navmesh work, and Blizzard's world data and item icons.

**License:** NodeTaxi code is MIT. Route data files retain their GPLv3 terms; Blizzard icons are referenced at runtime, not redistributed. See `LICENSE` and `ATTRIBUTION.md`.

**Current release:** 0.9.30.

## Deutsch

NodeTaxi ist eine Ergänzung für **TomTom**, die aus dem aktuellen Pfeilziel eine sammlerfreundliche Route macht. Statt nur den nächsten Wegpunkt anzuzeigen, zeichnet NodeTaxi eine gestrichelte gelbe Linie vom Spieler zum Ziel, folgt einem verborgenen Zonenkorridor und macht kurze Abstecher zu Kräutern und Erzen in der Nähe.

Wichtigste Funktionen:

- TomTom bleibt unverändert: kein neuer Wegpunkt, kein bewegter Pfeil, kein geändertes Ziel.
- Die Route folgt dem aktiven Sammel-Tracking: Find Minerals für Erz, Find Herbs für Kräuter.
- 23.827 gebackene Knoten in 44 Forever-Zonen.
- Alle bekannten Knoten auf Weltkarte und Minimap, auch ohne aktive Route.
- Blizzard-Item-Symbole: 12 px auf der Weltkarte, 9 px auf der Minimap, volle Deckkraft.
- Knoten innerhalb von 100 Yards werden zu hohlen Kreisen, damit der eigene Tracking-Punkt sichtbar bleibt.
- Echte Zonenübergänge über 63 Carbonite-Paare; ausgewählte Knoten in jeder Zone.
- Kurze Nebenwege mit maximal 4 Knoten pro Cluster und 8 pro Etappe.

Die meisten Optionen stehen unter **Einstellungen → AddOns → NodeTaxi** oder über `/nt options` bereit. Standardmäßig ist der automatische Chat ruhig; die Route aktualisiert sich bei einem neuen TomTom-Ziel, nicht bei jeder Bewegung.

Voraussetzungen: **TomTom**, **WoW Forever 1.60.1 / Interface 16001**. Installation nach `_forever_/Interface/AddOns/NodeTaxi`, danach `/reload` und `/nt`.

Grenzen: keine vollständige Navigation, keine Geländevermeidung, Fallback-Linien für Transport- und unvollständige Zonen, Daten-Snapshot kann veraltet sein. Keine Netzwerkverbindung; alle Daten bleiben lokal.

Quelle und Support: https://github.com/rmburgess-dev/NodeTaxi

## Français

NodeTaxi est un compagnon de **TomTom** qui transforme votre destination actuelle en un trajet de récolte. Il trace une ligne jaune pointillée vers la cible TomTom, suit un corridor de déplacement masqué entre les zones et fait de courts détours vers les herbes et minerais proches.

Points principaux :

- TomTom reste intact : aucun waypoint ajouté, aucune flèche déplacée, aucune destination remplacée.
- La route suit le pistage actif : Find Minerals pour le minerai, Find Herbs pour les herbes.
- 23 827 nœuds intégrés dans 44 zones de WoW Forever.
- Tous les nœuds connus sur la carte du monde et la minicarte, même sans route active.
- Icônes d’objets Blizzard : 12 px sur la carte, 9 px sur la minicarte, alpha complet.
- Les nœuds à moins de 100 yards deviennent des cercles creux pour laisser visible le point de pistage du jeu.
- Vrais passages entre zones via 63 paires Carbonite ; sélection de nœuds dans chaque zone.
- Détours courts : 4 nœuds maximum par groupe, 8 par étape.

La plupart des options sont dans **Options → AddOns → NodeTaxi** ou via `/nt options`. Le chat automatique est silencieux par défaut ; la route se met à jour lors d’une nouvelle cible TomTom, pas à chaque déplacement.

Prérequis : **TomTom**, **WoW Forever 1.60.1 / Interface 16001**. Installez dans `_forever_/Interface/AddOns/NodeTaxi`, puis `/reload` et `/nt`.

Limites : pas d'autopilote, pas d’évitement complet du terrain, lignes de secours pour les transports et zones sans corridor, instantané de données potentiellement ancien. Aucun accès réseau ; les données restent locales.

Source et support : https://github.com/rmburgess-dev/NodeTaxi

## Español

NodeTaxi es un complemento para **TomTom** que convierte tu destino actual en una ruta de recolección. Dibuja una línea amarilla discontinua hacia el objetivo de TomTom, sigue un corredor oculto entre zonas y hace pequeños desvíos hacia hierbas y minerales cercanos.

Características principales:

- TomTom permanece intacto: no se añaden waypoints, no se mueve la flecha y no se cambia el destino.
- La ruta sigue el rastreo activo: Find Minerals para mineral, Find Herbs para hierbas.
- 23.827 nodos incluidos en 44 zonas de WoW Forever.
- Todos los nodos conocidos en el mapa del mundo y el minimapa, incluso sin ruta activa.
- Iconos de objetos de Blizzard: 12 px en el mapa, 9 px en el minimapa, alpha completo.
- Los nodos a menos de 100 yardas se convierten en círculos huecos para dejar visible el punto de rastreo del juego.
- Transiciones reales entre zonas mediante 63 pares de Carbonite; nodos seleccionados en cada zona.
- Desvíos cortos: máximo 4 nodos por grupo y 8 por tramo.

La mayoría de las opciones están en **Opciones → AddOns → NodeTaxi** o con `/nt options`. El chat automático está silenciado por defecto; la ruta se actualiza al cambiar el objetivo de TomTom, no con cada movimiento.

Requisitos: **TomTom**, **WoW Forever 1.60.1 / Interface 16001**. Instala en `_forever_/Interface/AddOns/NodeTaxi`, luego `/reload` y `/nt`.

Limitaciones: no es un piloto automático, no evita todo el terreno, usa líneas de respaldo para transportes y zonas sin corredor, y la instantánea de datos puede estar desactualizada. Sin conexión de red; los datos permanecen locales.

Fuente y soporte: https://github.com/rmburgess-dev/NodeTaxi
