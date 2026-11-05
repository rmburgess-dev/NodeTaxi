# NodeTaxi 0.9.8

Short node spurs capped at 75 yards.

- Default maximum deviation from the corridor is 75 yards.
- A selected node is visited by an out-and-back to its projection on the
  corridor, then the route continues forward. No long diagonal spike to the
  next corridor point.
- `/nt spur <yards>` changes the limit; `/nt spur 50` makes an even tighter
  route, `/nt spur 0` disables node detours.
- Nodes outside the limit remain visible in the all-node field but are not
  selected for the route.
- Whole-map node display and forward corridor path remain.

Requires TomTom. Install into `_forever_/Interface/AddOns/NodeTaxi`.
Source: https://github.com/rmburgess-dev/NodeTaxi
