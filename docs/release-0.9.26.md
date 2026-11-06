# NodeTaxi 0.9.26

Smooth minimap updates.

- Minimap overlay refresh raised from 0.35 s (~3 FPS) to 0.05 s (~20 FPS).
- The minimap continues updating with no active route.
- Node lists and zone-to-world conversions are cached per zone.
- Near/far ring transitions and movement now track at the higher rate.
- World-map redraw cadence is unchanged.

Requires TomTom. Install into `_forever_/Interface/AddOns/NodeTaxi`.
Source: https://github.com/rmburgess-dev/NodeTaxi
