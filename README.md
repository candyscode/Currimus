# CURRIMUS

Minimalist running app — **running lives on the Apple Watch; the iPhone only
reads** (log, stats, settings). The watch UI is a pixel-faithful build of the
Claude Design page **"Watch Screens - Readability"** (Space Grotesk, signal
`#FF4D00` on ink `#0A0A0A`, bright metric labels `#A8A8A8`); the iPhone follows
`iPhone Screens.dc.html`.

## Recording is real

The watch records actual workouts:

- `HKWorkoutSession` + `HKLiveWorkoutBuilder` — live heart rate, distance,
  energy; the finished run is saved to Apple Health as a running workout.
- `CLLocationManager` — GPS route (saved via `HKWorkoutRouteBuilder`) and
  altitude (climb / descent / elevation profile for trail mode).
- HR zones from max HR, rolling last-kilometer pace, per-km splits with the
  5-second kilometer alert, 10-minute climb-rate window.
- The both-buttons hardware gesture pauses/resumes (session state is mirrored);
  tapping the run screen pauses too.
- Finished runs sync to the iPhone log via WatchConnectivity
  (`transferUserInfo`, queued while the phone is unreachable) and persist on
  both sides.

## Flows (all interactive)

- **Quick run**: Start → countdown → run glance (time / km / pace / zone bar)
  → km alerts → pause (End / Resume) → summary, crown scrolls to Done → Home.
- **Pacer**: Pacer → step 1 target pace (crown wheel, required) → Next →
  step 2 distance (crown wheel, `Off` = open-ended) → Start → live pacing
  (deviation gauge; with distance: `/ 10 KM` counter + finish forecast;
  without: plain KM + cumulative delta) → pacer summary (target vs. actual)
  → Done → Home.
- **Trail**: Trail → trail glance (climb + m/h) ⇄ swipe: elevation page
  (planned-route profile with "M TO TOP", or profile-so-far without a route)
  → trail summary (vert equal billing, profile) → Done → Home.

## Structure

| Folder | Target | Contents |
|---|---|---|
| `Watch/` | `CurrimusWatch` (watchOS app, embedded) | All screens above; `RunSession` is the recording engine (HealthKit + CoreLocation, simulation only in DEBUG screenshot routes) |
| `iOS/` | `Currimus` (iOS app) | Home (week, day bars, last run), Log → Run detail, Progress → Records, Settings → Pacer target, first-launch state |
| `WatchWidgets/` | `CurrimusWatchWidgets` (WidgetKit) | Circular complication, Smart Stack card, inline |
| `Shared/` | all targets | Theme, models, formatters, zones, `RunStore` (persisted), `RunSync` (WatchConnectivity) |
| `Assets/make_icon.swift` | — | Renders the app icon; `swift Assets/make_icon.swift out.png` |
| `DesignRefs/` | — | Imported Claude Design HTML used as the pixel reference |

Project file is generated: `xcodegen generate` (config in `project.yml`).
Watch target carries the HealthKit entitlement, usage descriptions and the
`workout-processing` background mode. **For device builds / App Store**: set
your development team in Signing & Capabilities (HealthKit needs a real
provisioning profile).

## Demo / screenshot routing (DEBUG builds only)

`-demo 1` seeds sample data; `-screen …` jumps into a simulated state:

- watchOS: `run | kmalert | paused | summary | pacer-set | pacer-distance |
  pacer-run | pacer-run-nodist | pacer-summary | trail | elevation |
  elevation-noroute | trail-summary`
- iOS: `-tab log|progress`, `-push detail|settings|pacer|records`, `-empty 1`

Release builds contain none of this — the engine always records for real.

## Next

- GPX route import on the iPhone → planned-route elevation on the watch
  (`RunSession.RoutePlan` is ready for it).
- MapKit in the iPhone run detail once synced GPS traces are stored.
