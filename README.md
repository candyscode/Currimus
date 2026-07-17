# CURRIMUS

Minimalist running app — **running lives on the Apple Watch; the iPhone only
reads** (log, stats, settings). Implemented from the Claude Design project
"Minimalistische Running App Design" (`Watch Screens.dc.html`,
`iPhone Screens.dc.html`).

## Structure

| Folder | Target | Contents |
|---|---|---|
| `Watch/` | `CurrimusWatch` (watchOS app, embedded in the iOS app) | Home (Start / Trail / Pacer), countdown, run glance with HR-zone bar, kilometer alert, pause, summary, pacer setup (digital crown) + live pacer gauge, trail run + elevation page + trail summary |
| `iOS/` | `Currimus` (iOS app) | Home (week, day bars, last run), Log (by month) → Run detail (map placeholder, splits, zones), Progress (pace trend, monthly km) → Records, Settings → Pacer target, first-launch empty state |
| `WatchWidgets/` | `CurrimusWatchWidgets` (WidgetKit extension) | Circular complication, Smart Stack card, inline — week km vs goal |
| `Shared/` | all targets | Theme (colors/type), models, formatters, zone model, sample data, `RunStore` |
| `Assets/make_icon.swift` | — | Renders the app icon (C-track + runner dot); `swift Assets/make_icon.swift out.png` |

The project file is generated: `xcodegen generate` (config in `project.yml`).

## Run

Open `Currimus.xcodeproj`, scheme **Currimus** on an iPhone simulator, or
**CurrimusWatch** on a watch simulator.

## Demo routing (DEBUG)

The run engine is simulated (pace/HR/climb follow plausible curves) and the
log is seeded with generated sample runs. Launch arguments jump to any screen:

- iOS: `-tab log|progress`, `-push detail|settings|pacer|records`, `-empty 1`
- watchOS: `-screen run|kmalert|paused|summary|pacer-set|pacer-run|trail|trail-summary`

## Going live (not yet wired)

- `RunSession.tick()` → replace simulation with `HKWorkoutSession` +
  `CLLocationManager` (HR, GPS distance, altitude).
- `RunStore` ↔ WatchConnectivity to sync finished runs and the pacer target
  (the UI copy already assumes this).
- `MapCard` → MapKit once real GPS traces exist.
