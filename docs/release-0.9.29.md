# NodeTaxi 0.9.29

Updated node snapshot.

- Rebuilt from the current GatherMate2/Wowhead Forever package.
- Base package remains 13,332 herbs and 10,486 ore.
- Merged 24 genuinely new nodes after a 12-yard duplicate check:
  - 23 Durotar ore nodes from the saved NodeTaxi scan
  - 1 new Tirisfal ore node from GatherMate2
- Baked total: **13,332 herbs + 10,510 ore = 23,842 nodes**.
- Existing route/settings/presentation behavior is unchanged.
- Fix a Lua 5.4 loop-variable reassignment in the GatherMate2 import path.

Requires TomTom. Install into `_forever_/Interface/AddOns/NodeTaxi`.
Source: https://github.com/rmburgess-dev/NodeTaxi
