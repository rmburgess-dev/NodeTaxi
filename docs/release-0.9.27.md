# NodeTaxi 0.9.27

In-game settings and quiet defaults.

- Add **Settings → AddOns → NodeTaxi** with routing, display, tracking,
  quiet-chat and action controls.
- `/nt options` opens the page.
- Automatic chat is now quiet by default: no node-reached, crossing, gather or
  automatic route-summary messages. Manual commands still respond.
- Rolling re-plan is off by default. The route updates when the TomTom target
  changes or you enter a new zone; `/nt replan 30` enables rolling updates.
- Existing 30-yard re-plan and gather-chat defaults migrate to the quiet
  defaults; explicit non-default values are preserved.

Requires TomTom. Install into `_forever_/Interface/AddOns/NodeTaxi`.
Source: https://github.com/rmburgess-dev/NodeTaxi
