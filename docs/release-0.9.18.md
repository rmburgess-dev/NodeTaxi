# NodeTaxi 0.9.18

Visible transport/uncovered legs.

- Legs without a generated corridor now draw a fallback line through the
  selected nodes, or the direct leg endpoints when there are none.
- This fixes blank destination zones after zeppelin/boat routes and zones not
  covered by the corridor snapshot.
- A current leg already at `/nt max` no longer reshuffles its selected nodes
  while the player moves.
- The no-corridor behavior has a regression test.

Requires TomTom. Install into `_forever_/Interface/AddOns/NodeTaxi`.
Source: https://github.com/rmburgess-dev/NodeTaxi
