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
| `Watch/` | `CurrimusWatch` (watchOS app, embedded) | All screens above; `RunSession` drives the recording lifecycle (HealthKit + CoreLocation, simulation only in DEBUG screenshot routes) |
| `iOS/` | `Currimus` (iOS app) | Home (week, day bars, last run), Log → Run detail, Progress → Records, Settings → Pacer target, first-launch state |
| `WatchWidgets/` | `CurrimusWatchWidgets` (WidgetKit) | Circular complication, Smart Stack card, inline |
| `Shared/` | all targets | Theme, models, formatters, zones, `RunStore` (persisted), `RunSync` (WatchConnectivity), `RunMetrics` (the run's arithmetic), `RunSampleStore` (GPS tracks + altitude series) |
| `Tests/` | `CurrimusTests` | `RunAnalytics`, `RunMetrics` and `RunStore` — 44 cases, each on a throwaway defaults suite |
| `Resources/` | both apps | `Localizable.xcstrings` — the string catalogue |
| `Assets/make_icon.swift` | — | Renders the app icon; `swift Assets/make_icon.swift out.png` |
| `DesignRefs/` | — | Imported Claude Design HTML used as the pixel reference |

### How a run is stored

The log lives in App-Group `UserDefaults` so the widget can read it, and
`UserDefaults` faults its whole backing plist into memory in every process
that opens the suite. So the log holds **metadata only**; the GPS track and
altitude series of each run go to one file per run under the app group
(`RunSampleStore`). `RunStore.hydrated(_:)` puts them back for the two callers
that need them — the run detail screen and the GPX export. Logs written before
this migrate on first load.

`RunMetrics` is the arithmetic of a run in flight — rolling pace, splits,
climb, time in zones, and the sampling of altitude and route. It is pure, so
it is unit-tested; `RunSession` is the HealthKit and CoreLocation lifecycle
around it. When a sample buffer fills it halves its resolution rather than
dropping from the front, so a four-hour run keeps its start.

Anything the recording cannot do — a declined Health prompt, location off, a
workout session that would not start — surfaces as a `RunSession.RecordingIssue`:
a line above the footer while running, a card on the summary. Nothing fails
silently; the rest goes to `os.Logger` under the `com.currimus.app` subsystem.

Project file is generated: `xcodegen generate` (config in `project.yml`).
The project builds in the **Swift 6 language mode** with complete strict
concurrency; `RunStore` and `RunSession` are `@MainActor`.
Watch target carries the HealthKit entitlement, usage descriptions and the
`workout-processing` background mode. **For device builds / App Store**: set
your development team in Signing & Capabilities (HealthKit needs a real
provisioning profile).

## Demo / screenshot routing (DEBUG builds only)

`-demo 1` seeds sample data; `-screen …` jumps into a simulated state:

- watchOS: `run | kmalert | paused | summary | pacer-set | pacer-distance |
  pacer-run | pacer-run-nodist | pacer-summary | trail | elevation |
  elevation-noroute | trail-summary | issue-health | issue-location |
  issue-summary`
- iOS: `-tab log|progress`, `-push detail|settings|pacer|records`, `-empty 1`

Release builds contain none of this — the engine always records for real.

## Next

- GPX route import on the iPhone → planned-route elevation on the watch.
- MapKit in the iPhone run detail, now that GPS traces are stored per run.
- Translations: the catalogue is wired up and extracts, but English is the
  only language in it. Xcode repopulates it on build; from the command line,
  `xcrun xcstringstool sync Resources/Localizable.xcstrings --stringsdata …`.
- A distance fallback for a run recorded without Health access: GPS is
  running and the route is kept, but distance still comes from the workout
  builder alone, so a declined prompt means the run has no distance.
