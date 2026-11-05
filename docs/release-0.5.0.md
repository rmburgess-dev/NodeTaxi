# NodeTaxi 0.5.0

First public release for **WoW Forever 1.60.1 (Interface 16001)**.

- 23,818 baked Forever herb/ore nodes across 44 zones.
- Follows your active tracking: Find Minerals shows ore only, Find Herbs shows
  herbs only. `/nt kind auto|herb|ore|both`.
- Per-node resource icons: Copper Vein, Tin Vein, Peacebloom, and 43 more,
  using GatherMate2 node IDs and bundled artwork.
- Learned nodes inherit the nearest snapshot node ID; imports preserve IDs.
- Re-plans the remaining route every 30 yards; collected nodes are not
  revisited.
- Hollow rings within 100 yards keep the game's tracking dot visible.
- Persistent `/nt log` and `/nt validate` for checking snapshot accuracy.

**Requires TomTom.** Install into `_forever_/Interface/AddOns/NodeTaxi`.

Source: https://github.com/rmburgess-dev/NodeTaxi
