# NodeTaxi 0.9.12

100-yard node deviation.

- Default maximum node deviation/sweep is now 100 yards, matching the
  minimap's typical 80-100 yard render band.
- Existing 75-yard defaults migrate to 100; custom `/nt spur` values are kept.
- `/nt ring 100` remains the close-marker threshold.
- The whole-map node field and forward sweep route remain.

Requires TomTom. Install into `_forever_/Interface/AddOns/NodeTaxi`.
Source: https://github.com/rmburgess-dev/NodeTaxi
