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
| `TV/` | `CurrimusTV` (tvOS app) | Read-only 10-foot dashboard: week volume, log, progress, run detail with route + elevation. Reads the log from CloudKit (`RunCloudSync`), reusing every `RunStore` aggregate the phone computes |
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

### The Apple TV (read-only)

`CurrimusTV` shows the same log on a television. tvOS is **not** a watch-style
companion — it is a standalone app that shares nothing device-local with the
phone (App Groups do not cross devices, and tvOS has neither HealthKit nor
WatchConnectivity). So the phone mirrors its log into the user's **private
CloudKit database** and the TV reads it: same iCloud account, no server, no
data leaves the account.

- **Phone (writer):** `RunStore` publishes through `RunCloudSync` — `upsert` on
  every added run, `delete` on removal, a one-time `backfillCloud()` to seed the
  existing log. It syncs `allRuns` (Currimus' own runs *and* the ones it
  imported from Health) so the TV's totals match the phone, which the TV cannot
  derive itself. A run is stored as a JSON blob of its metadata plus a `CKAsset`
  for the GPS track and altitude series — the same split as `RunSampleStore`.
- **TV (reader):** `TVSync` fetches on launch/foreground and hands the runs to a
  `RunStore` via `replaceAllFromCloud`, so every aggregate, record and chart is
  the phone's logic unchanged — the TV owns only its 10-foot SwiftUI layer.

The shared bundle id (`com.currimus.app`) puts iOS and tvOS under one App Store
record (Universal Purchase). `RunSync` (WatchConnectivity), `HealthImport` and
`HeartRateProfile` (HealthKit) are `#if canImport(...)`-guarded so `Shared/`
compiles on tvOS, which links neither framework.

### When recording cannot work

Distance and heart rate both come out of the workout builder, so **a run needs
Apple Health**. If the workout write is denied, the run does not start: a
screen names the problem and spells out the Settings path (watchOS has no URL
that opens Settings). Location is different — without it a run loses its route,
climb and elevation but keeps distance, pace and zones, so it only degrades and
never blocks. `RecordingIssue.blocksRecording` is where that line is drawn.

One denial cannot be caught at the door. Health hides *read* authorization by
design, so someone can allow "save workouts" — all the gate can observe — and
refuse Distance separately. That shows up only once the run is moving and the
number stays at zero, which `checkDistanceIsArriving` reports as a live banner
after two minutes. A run that ends without distance is shown on the summary and
then dropped rather than filed as a 0.00 km entry.

Everything else that used to be swallowed goes to `os.Logger` under the
`com.currimus.app` subsystem.

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
  elevation-noroute | trail-summary | blocked-health | blocked-workout |
  blocked-unavailable | issue-nodistance | issue-location | issue-summary |
  summary-empty`
- iOS: `-tab log|progress`, `-push detail|settings|pacer|records`, `-empty 1`

Release builds contain none of this — the engine always records for real.

## Next

- GPX route import on the iPhone → planned-route elevation on the watch.
- MapKit in the iPhone run detail, now that GPS traces are stored per run.
- Translations: the catalogue is wired up and extracts, but English is the
  only language in it. Xcode repopulates it on build; from the command line,
  `xcrun xcstringstool sync Resources/Localizable.xcstrings --stringsdata …`.
- Nothing for a run without Health access: recording it from GPS alone was
  considered and rejected — it would mean a second distance pipeline with its
  own noise filtering and calibration, for a mode the app does not offer.
