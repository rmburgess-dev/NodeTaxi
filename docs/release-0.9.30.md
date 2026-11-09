# NodeTaxi 0.9.30

Blizzard icons, no bundled artwork.

- Node icons now come from Blizzard item IDs resolved at runtime through
  `GetItemIcon`; the `Media/` artwork tree is no longer shipped.
- Removed the local gather-data import command and its settings-page button.
- Current code, seed headers, README, license, attribution and CurseForge copy
  now describe the data as standardized public Classic node coordinates with
  Blizzard item icons.
- The baked snapshot remains 23,842 herb/ore nodes and route behavior is
  unchanged.

Requires TomTom. Install into `_forever_/Interface/AddOns/NodeTaxi`.
Source: https://github.com/rmburgess-dev/NodeTaxi
