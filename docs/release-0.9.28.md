# NodeTaxi 0.9.28

Automatic updates stay visible.

- Quiet mode keeps routine node-reached, crossing and gather messages off, but
  automatic target/zone rebuilds print one short **route updated** line.
- The route-update line has its own settings-page checkbox.
- A one-second TomTom target watcher acts as a fallback if the callback is
  missed, so arrow changes still rebuild without a manual `/nt route`.
- Regression coverage confirms a second TomTom target change rebuilds
  automatically and emits the short notice.

Requires TomTom. Install into `_forever_/Interface/AddOns/NodeTaxi`.
Source: https://github.com/rmburgess-dev/NodeTaxi
