# nightscout-go-systray — Omarchy plugin

An [Omarchy](https://omarchy.org/) shell plugin that shows live [Nightscout](https://nightscout.github.io/)
CGM (glucose) readings in the bar: current value, trend arrow, range
coloring, and a popup with the previous reading and low/in-range
predictions.

This is a fork of [harmen91/nightscout-go-systray](https://github.com/harmen91/nightscout-go-systray),
itself a fork of the original [brettcodling/nightscout-go-systray](https://github.com/brettcodling/nightscout-go-systray)
(archived). See [Attribution](#attribution) below.

## What changed in this fork

The original project is a standalone Linux system-tray app (using
[`getlantern/systray`](https://github.com/getlantern/systray)) meant to be
launched via an XDG autostart entry. Omarchy's shell (`omarchy-shell`, built
on [Quickshell](https://quickshell.org/)) doesn't host arbitrary GUI toolkits
like that — third-party bar content runs as QML plugins inside the shell
process instead.

So this fork splits the app in two, both new to this fork:

- **`main.go`** — trimmed down to just the Nightscout-polling and BG-range
  math from the original `main.go`, with the tray UI, desktop notifications,
  and BoltDB-backed settings removed. It's now a stateless CLI: one
  invocation fetches the two latest Nightscout entries, computes range,
  trend, and low/in-range predictions, prints one JSON object to stdout, and
  exits. See [`main.go`](./main.go) for the JSON shape.
- **`manifest.json`, `BarWidget.qml`, `Panel.qml`, `Model.js`** — a native
  Omarchy `bar-widget` plugin, new in this fork, that invokes the CLI above
  on a timer and renders its output as the bar pill and detail popup. It
  follows the same structure as Omarchy's shipped `bar-widget` plugins
  (`Panel`/`KeyboardPanel`/`BarWidget` from `qs.Ui`, a `Process` +
  `StdioCollector` poll loop) — see [`Panel.qml`](./Panel.qml) for the
  reference plugins this was modeled on.

The standalone tray app (systray icon, desktop notifications, persisted
alert toggles) is **not preserved in this fork** — this fork is specifically
for Omarchy users. If you want the original standalone tray app, use
[harmen91/nightscout-go-systray](https://github.com/harmen91/nightscout-go-systray)
or the [original upstream](https://github.com/brettcodling/nightscout-go-systray).

## Install as an Omarchy plugin

```bash
omarchy plugin add https://github.com/loudestnoise/nightscout-go-systray.git --enable
```

Then build the CLI once (Omarchy plugins are installed via plain `git clone`,
with no build step, so this is a one-time manual step — same `go build`
command the original project's README always documented, just aimed at the
plugin's own `bin/` directory):

```bash
cd ~/.config/omarchy/plugins/loudestnoise.nightscout-cgm
go build -o bin/cgm .
```

Requires Go 1.16+ (`go version` to check; install via your distro or
`mise use go` if you use [mise](https://mise.jdx.dev/)).

Finally, open the plugin's settings from Omarchy's Setup > Plugins screen
and set your Nightscout URL (required), low/high/urgent-high targets in
mmol/L, whether to show mg/dL instead of mmol/L as the primary value (both
are always shown in the popup), and refresh interval. The bar pill shows a
loading/warning glyph until a URL is set.

## JSON contract

`cgm -url <nightscout-url> [-low N] [-high N] [-urgent-high N]` prints one
JSON object and exits 0 (or 1 with an `"error"` field on failure — always
valid JSON either way, so the plugin never has to parse malformed output).
Example:

```json
{
  "mmol": 5.3, "mgdl": 95, "timestampMs": 1737641400000,
  "direction": "FortyFiveDown", "directionArrow": "↘",
  "previousMmol": 6.1, "previousMgdl": 110, "previousTimestampMs": 1737641100000,
  "isLow": false, "isHigh": false, "isUrgentHigh": false,
  "predictedLowAtMs": 1737641872311,
  "alerts": ["Predicted low at 15:54!"]
}
```

## Known limitations / follow-ups

- No desktop notifications for alerts yet (original used `beeep`); the
  popup lists active alerts, but nothing pushes a notification when the bar
  isn't visible.
- QML was written against and tested against Omarchy 4.0.0 (alpha,
  "Quattro") via `qs -p <path>` headless runs against real Nightscout-shaped
  JSON; it has not been exercised in a live desktop session.

## Attribution

- Original app: [brettcodling/nightscout-go-systray](https://github.com/brettcodling/nightscout-go-systray) (archived)
- Fork this repo is based on: [harmen91/nightscout-go-systray](https://github.com/harmen91/nightscout-go-systray)
- Omarchy plugin work in this fork: [loudestnoise](https://github.com/loudestnoise), with implementation assistance from [Claude Code](https://claude.com/claude-code)

Neither upstream repo declares a license. This fork doesn't add one either
— rather than assert rights the fork doesn't clearly have, it's published
as-is for personal Omarchy use, tracking the same no-stated-license status
as its upstream. If you're the original author and want a license added or
want this handled differently, please open an issue.

## Original screenshots (standalone tray app, for history)

<img src="./screenshots/screenshot.png">
<img src="./screenshots/screenshot_dropdownmenu.png">
