# Agent notes

Things that cost time to work out once, written down so they cost nothing the
next time. Process lives in `Claude.md`, open tickets in
`Management/Features.md`, finished ones in `Management/Features-completed.md`.

## Build, test, run

```bash
xcodegen generate                       # after ANY new/renamed/removed source file
xcodebuild build -scheme Currimus      -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild build -scheme CurrimusWatch -destination 'platform=watchOS Simulator,name=Apple Watch Ultra 3 (49mm)'
xcodebuild test  -scheme CurrimusTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild test  -scheme CurrimusWatchTests -destination 'platform=watchOS Simulator,name=Apple Watch Ultra 3 (49mm)'
```

`CurrimusWatchTests` compiles `Shared` and **only `Watch/RunSession.swift`** — not the
`Watch` folder. Everything else there is views, and `WatchApp.swift` carries
`@main`, which a test bundle must not contain. `RunSession` happens to reference
nothing Watch-local, which is what makes that possible; if it ever does, exclude
`WatchApp.swift` rather than adding the whole folder.

Drive a run in those tests with `debugJumpScenario`, never `begin()`:
`begin` starts a real 1 Hz `Timer` on the main run loop, and every assertion
after it becomes a race. `debugJumpScenario` plays a `RunScenario` second by
second with no timer and no randomness.

Filter the output — `xcodebuild` prints thousands of lines and a failure is one
of them:

```bash
xcodebuild build … 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

`-quiet` is worse than useless here: it can swallow the failure line too. Grep
the full output instead.

**A new file will not compile until `xcodegen generate` has run.** Sources are
declared by directory in `project.yml`, but the generated `.xcodeproj` lists
files individually. The error is `Cannot find 'X' in scope` for a type that
plainly exists.

SourceKit diagnostics that appear while editing (`Cannot find type 'Run' in
scope`, one per line) are noise — the editor indexes single files without the
module. Trust `xcodebuild`, not those.

## Looking at a screen without the snapshot harness

The fastest way to see one screen, and the only way to see a state the harness
has no route for:

```bash
UDID=$(xcrun simctl list devices available | grep -F "iPhone 17 Pro (" | head -1 | grep -oE '[0-9A-F-]{36}')
APP=$(xcodebuild -showBuildSettings -scheme Currimus -destination "platform=iOS Simulator,name=iPhone 17 Pro" 2>/dev/null \
      | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{d=$2} / FULL_PRODUCT_NAME/{n=$2} END{print d"/"n}')
xcrun simctl install $UDID "$APP"          # xcodebuild does NOT install
xcrun simctl terminate $UDID com.currimus.app
xcrun simctl launch $UDID com.currimus.app -demo 1 -push detailRoad
sleep 3 && xcrun simctl io $UDID screenshot /tmp/shot.png
```

`xcodebuild build` only builds. Without the `install` step the simulator keeps
running the previous binary and the screenshot quietly shows the old UI.

Launch arguments live in `Shared/DebugFlags.swift`; the routes they reach are in
`CurrimusApp.debugHomePath` (iOS) and `WatchApp` (watch). A screenshot only ever
captures what is **above the fold** — there is no way to scroll, so a change at
the bottom of a long screen has to be verified another way (usually a test).

## UI snapshots — the current policy

**Do not run `scripts/ui-snapshot.sh verify` routinely.** Andi's call
(2026-07-27): the run itself is cheap, but it is only useful if the diff images
get read, and reading a diff PNG is expensive. Date-relative demo data and a
live MapKit map make failures common and mostly meaningless.

Do run `record` after deliberately changing or adding a screen, so the committed
references do not rot:

```bash
scripts/ui-snapshot.sh record ios       # text output only, no images to read
```

If a reference comes back byte-identical after you deliberately changed that
screen, the screenshot did not happen. `simctl io screenshot` refuses to capture
while the simulator is busy, and the first route after an install is exactly
that busy — the harness used to swallow the error and copy the *previous run's*
candidate over the reference, reporting `rec`. It now deletes the candidate
first, retries, warms the app up once after installing, and fails loudly. Two
`record` runs went into a reference that had not moved before this was found
(CUR-37).

`record` **overwrites the references for whichever simulator it runs on**. The
baseline is pinned to iPhone 17 Pro / Apple Watch Ultra 3 (49mm) — running it
with `WATCH_SIM` pointed elsewhere silently replaces the baseline with captures
from the wrong device. Recover with `git checkout -- Tests/UISnapshots/reference`.

## Gestures need the UI-test target

`CurrimusUITests` exists because the log's swipe-to-delete broke twice and
nothing could catch it: a unit test cannot express a drag, `simctl` cannot
inject one, and a screenshot only shows a resting state.

```bash
xcodebuild test -scheme CurrimusUITests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Run it after touching anything in `iOS/RunDeletion.swift` or the log's rows.
Two things it has already caught:

- **A `Button` inside a swipeable row is a trap.** A horizontal drag never
  leaves a full-width button's bounds, so SwiftUI does not cancel its tap and
  lifting the finger fires it. Use a `TapGesture` alongside the drag instead —
  a tap does not fire once the finger has travelled.
- **A `LazyVStack` breaks the swipe.** The action tile lives in the row's
  background and loses its definite height under a lazy container, so the
  button renders but stops being hittable. The log stays eager on purpose.

Elements need identifiers to be addressable: rows carry `log-row`, the swipe
tile carries `swipe-action`. Matching on visible text is fragile — the log's
own header ends in " km" just like every row does.

**The resting open state guards nothing about the middle of the gesture.** The
gap between the row and the tile used to live in `openOffset` alone, so
`-swipe 1` looked right while every partial offset had the tile drawn over the
pace (CUR-47). It is expressed as an overhang on the row's own background fill
now — `Theme.bg.padding(.trailing, -actionGap)` — which holds at every offset.
`-swipe half` stops the row partway so that state can be screenshotted at all;
a drag cannot be injected into `simctl`.

## HealthKit, learned the hard way

- **Deleting** a workout is a *write*: it needs share authorization for
  `HKObjectType.workoutType()`, asked for at the moment of the first delete
  (`HealthImport.deleteWorkouts`). Deleting a workout does **not** remove the
  `HKWorkoutRoute` attached to it — query and delete those in the same call.
- An app can only delete samples **it** saved. Another app's workout cannot be
  removed, which is why imported runs are never offered a delete.
- **Steps are not collected by default** for a running workout.
  `HKLiveWorkoutDataSource.enableCollection(for: HKQuantityType(.stepCount),
  predicate: nil)` is what makes cadence possible at all.
- Read authorization is never observable — a denied type returns an empty
  result. Only *share* denial can be detected.
- **Adding a type to `readTypes` does nothing on its own.** Installs that have
  already answered the prompt leave the new type undetermined, and it returns
  empty forever until `requestAuthorization` is called again. That is what hid
  the workout routes of imported runs. Re-requesting is cheap: the sheet only
  appears for types that are new.
- There is **no API for a person's heart-rate zones before iOS 27**
  (`zoneGroupsByType`, WWDC26 session 207). Until the target moves, "the same
  zones as Apple Fitness" can only mean the same model and the same inputs.
- Read authorization cannot be *asked about* either, which is why the first
  launch reports evidence instead of permission: an import that comes back with
  nothing means "declined **or** empty", and the UI has to say both (CUR-37).
- The simulator has no Health data whatsoever. Anything derived from Health
  (zones, cadence, imported runs) needs a DEBUG injection to be seen at all —
  see the `-zones derived|updated|coach` flags, and `-import
  reading|filling|done|nothing` / `-noimport 1` for the first-launch import,
  which on a simulator is over before its progress bar has drawn once.

## Elevation, and why it is not GPS

Climb comes from the **barometer** (`CMAltimeter`), not from
`CLLocation.altitude`. GPS altitude error is two to three times the horizontal
one and it wanders while standing still; summing it over a run read 20–25 %
high against Apple Fitness (CUR-40). Apple Fitness uses the barometer.

- `NSMotionUsageDescription` is **required**. Without it, touching `CMAltimeter`
  is a crash, not a denial. It lives in `project.yml` as an
  `INFOPLIST_KEY_`.
- **Two tiers of barometer, and the difference matters if the target ever
  moves.** `isAbsoluteAltitudeAvailable()` needs the *always-on* altimeter —
  Series 6 and later, SE 2, Ultra. Every watchOS 11 device has one. Series 3–5
  have a plain barometer and report *relative* altitude only, and watchOS 10
  (which CUR-11 proposes) brings them back. `BarometricAltimeter` handles both:
  relative readings are ingested from an arbitrary zero and the first usable
  GPS fix shifts the whole series onto sea level via
  `RunMetrics.shiftAltitudeBaseline`. A uniform shift changes no difference, so
  no metre of climb waits on a fix that may never come. The offset then has to
  be added to every *later* reading too — `RunSession.altitudeBaseline`.
- No barometer at all (Series 1–2, the simulator) → `isAvailable == false` →
  the GPS altitude path in `integrate`, as before.
- **`stop()` clears the reading, and it has to.** One `RunSession` — and so one
  altimeter — outlives every run in an app session. A reading left behind is
  the last run's altitude, and the next run takes it for a current one on its
  first tick: the drive to the trailhead gets banked as climb. It also deadens
  the grace period, since the reading is then never nil again.
- **`ingestAltitude` rejects a sample that goes backwards in time.** It used to
  take it and rewind the filter's clock with it, so the next genuine reading
  came with an alpha of one and no filtering at all — one GPS outlier through
  that hole is 8 m of climb, measured.
- **Never feed two sources into one series.** The handover leaves a step of
  tens of metres, and a step is banked as climb. The source is fixed at
  `resetMetrics`, and a run *waits* up to `RunSession.barometerGracePeriod`
  (30 s) for the barometer rather than starting on GPS and switching. If the
  wait runs out — a denied motion permission looks exactly like a slow sensor —
  it falls back and calls `resetAltitudeTracking()`, which banks the leg under
  way and forgets only the position.
- The simulator has no barometer, so nothing here can be tested there. The
  *arithmetic* is fully covered in `RunMetricsTests` — feed
  `RunMetrics.ingestAltitude` a synthetic profile with noise on it.
- The accumulation is per **leg**, not per sample: a rise stays one rise until
  the altitude falls `climbHysteresis` (3 m) off its high point. If a real run
  comes back reading *low* against Apple Fitness, that constant is the dial.
  `altitudeTimeConstant` (6 s) is deliberately light — a heavier filter rounds
  off summits, and that loss is paid twice at every reversal.

## The live clock's seconds

Read the elapsed time from the **frame's scheduled date**, never from
`workoutBuilder.elapsedTime` at the moment the frame arrives. A frame lands
tens of milliseconds either side of its boundary, and which side decides
whether a second is drawn twice or skipped — the total stays right, so this
looks like a rendering bug rather than a clock one. `RunTimeline` and
`RunSession.displayElapsed(at:)` share one anchor, `clockAnchor`; if you add a
live screen, go through `RunTimeline`.

## Sending a run to the phone

`transferUserInfo` refuses a payload past a limit Apple does not publish, and it
refuses it **asynchronously** — the call returns a transfer object either way.
Implement `didFinish(userInfoTransfer:error:)` or the failure is silent, which
is how a two-hour trail run disappeared between the watch and the phone
(CUR-40).

## What the watch's widgets can actually see

**The Apple Watch's HealthKit store is not a copy of the phone's.** It holds
what the watch itself recorded plus a short window synced from the iPhone —
*not* a history. So no query the watch can run will produce a correct year
total: everything older than that window is simply not on the device, along with
every run some phone-only app recorded. A clean install read 37 km for a year
that was many times that (CUR-46), with the recovery sweep working exactly as
written. This is the ceiling on anything computed watch-side, and it cannot be
raised by trying harder.

So **the iPhone works the totals out and pushes them**: `DistanceTotals` goes
over the `updateApplicationContext` channel beside the settings and lands in
`AppDefaults.totalsKey`. `DistanceTotals.current()` prefers that record and adds
only the runs the watch holds that are *newer* than its `pushedAt` — the near
edge the phone has not heard about yet — so nothing is counted twice and a run
finished on the walk home still shows. With no push at all (never paired, first
launch) it falls back to the watch's own log: short beats blank.

`updateApplicationContext` **replaces** the dictionary rather than merging, so
`RunSync` keeps the last settings and the last totals and always writes both
keys. Sending one alone erases the other.

A widget otherwise reads the **app group of the device it runs on**, and today
that is only ever the watch. So a locally computed total is `runs.v2 +
imported.v1` as the *watch* holds them.

Those two lists have a hole between them, and it is the whole of CUR-46:

- `runs.v2` on the watch is only what **this watch** recorded and still has. An
  app reinstall wipes the app group; a replaced watch never had the history.
- `imported.v1` is deliberately **everything except Currimus** —
  `fetchRuns` filters on `!bundleIdentifier.hasPrefix(ownBundlePrefix)`.

So a workout of ours that the local log has lost belongs to neither, and the
year total reads short while Apple Fitness lists every one of those runs. The
watch therefore runs `recoverOwnRuns` too, over `HealthImport.importWindowStart()`
(18 months) instead of `recoveryWindowDays` (90), and with `hydrating: false` —
there is no detail screen on the watch to fill.

**Two windows, two jobs, do not merge them.** `recoveryWindowDays` is a safety
net for a transfer that failed; `importWindowMonths` is how far back a total can
see. A year total needs at least thirteen months, since the month bucket also
compares against the month before.

**Nothing reloads a widget on its own** — and a reload per write is worse than
none. `RunStore.write` asks for one after the two log keys land, through
`reloadWidgets()`, which throttles to one a minute on the leading *and* trailing
edge. WidgetKit gives a widget a daily budget of timeline reloads and freezes it
for the rest of the day once that is spent, and the log is written **per run**
in three places (`hydrate`, and the two loops in `rebuildEverythingFromHealth` /
`startFirstImport`) — a first import of a few hundred runs would spend the whole
budget in one burst.

**`add` is for one run, not for three hundred.** Each call re-sorts the log and
rebuilds the imported list against it (`merging` is imported × own), and each of
its two `@Published` writes queues a full JSON encode. A recovery files its runs
through `file(recovered:)` instead: one sort, one merge, one save.

**A delete tombstone must outlive every sweep that could undo it.**
`deletedOutings` is pruned against `HealthImport.importWindowStart()`, not
`recoveryWindowDays` — pruned against ninety days, deleting a run older than
that recorded nothing at all, and the watch's eighteen-month pass filed it back.
Still open by design: tombstones are per device, so a run deleted on the phone
whose workout survives in Health (share access refused) can still return on a
reinstalled watch.

## The route in Apple Health is not saved with the workout

`finishWorkout` and `finishRoute` fail in different ways, and the difference is
the whole of CUR-44:

- **`finishWorkout` is an XPC call healthd carries out on its own.** Once made,
  the workout is saved whether or not this process ever runs again.
- **`finishRoute` is a call we still have to make afterwards** — it needs the
  saved workout — and a suspended process never makes it.

watchOS suspends the app within seconds of a run ending; the wrist drops the
moment the runner taps Finish. So the run appears in Apple Fitness with no map,
while Currimus draws one perfectly well from its own copy of the track. Two
things now stand against it:

1. The whole finish chain runs inside `ProcessInfo.performExpiringActivity`,
   held open by a semaphore the completion signals. The block is invoked a
   second time with `expired == true` if the time runs out — signal from there
   too, or the assertion is held for nothing.
2. `RouteRepair` sweeps on watch launch: for each recent run of ours whose
   workout has no `HKWorkoutRoute`, it rebuilds one from the stored track.
   **This has to run on the watch** — HealthKit only lets an app attach objects
   to a workout it saved itself, and the watch is what saved these. Answered
   runs are remembered in `AppDefaults`/`RouteRepair.settledKey` so a launch
   costs nothing.

`insertRouteData` rejects a location with a negative accuracy, and the stored
track carries none — `RouteRepair.locations` states
`RunMetrics.usableHorizontalAccuracy` back as an honest upper bound, since every
point in the track cleared that filter live.

## Sending a run to the phone

There are **two** independent paths home, on purpose:

1. `RunSync` keeps an outbox in the app group and only drops a run when the
   system confirms delivery; `flush()` runs on activation, on reachability and
   on the watch app becoming active. Under 60 KB a run goes as `transferUserInfo`,
   over it as `transferFile` — never thinned, because a marathon arriving with
   half its GPS points is the same silent failure in a different hat.
2. `RunStore.recoverOwnRuns()` reads Currimus' **own** workouts back out of
   Apple Health on every foreground and files anything the log is missing. The
   watch saves the workout *before* it attempts the sync, so this copy exists
   even when the crossing fails entirely — which is how the CUR-40 run was
   sitting in Apple Fitness while Currimus showed nothing.

Three rules keep the two from fighting:

- A recovered run carries `recovered = true` and a different identity (the
  workout's UUID). Pairing is therefore by **outing overlap**, never by id.
- When the watch's own copy arrives later it *replaces* the recovered
  stand-in — it has the splits, the live zone seconds and the measured climb.
- A run deleted on purpose is written to `AppDefaults.deletedOutingsKey` before
  Health is even asked, or the sweep would put it straight back.

The watch stamps `HealthImport.runTypeKey` / `runNameKey` on the workout so a
recovered trail run comes back as a trail run.

## Widgets, and the tinted watch face

A watch face in any colour but the full-colour one ("Bunt") renders its
complications in **accented** mode: watchOS replaces every colour with the
face's own and **keeps nothing but the alpha channel**. So two opaque colours —
say a `0x2E2E2E` track under an `0xFF4D00` fill — arrive as one flat line of
identical white. That is not a subtle shift; the week widget's progress bar was
simply invisible on every tinted face until CUR-42.

- **Express contrast as opacity, not as hue,** in anything a widget draws.
  `WidgetPalette` (in `WatchWidgets/WidgetSurfaces.swift`) is the one place
  that decides: it reads `\.widgetRenderingMode` and returns the design's greys
  in full colour, `.white.opacity(…)` when tinted.
- `.widgetAccentable()` puts a view in the accent group, which the system gives
  the face's vivid colour while the rest gets a dimmer shade. Useful, but not
  something to rely on alone — the opacity has to carry the meaning.
- **`\.widgetFamily` and `\.widgetRenderingMode` are read-only** environment
  keys. `.environment(\.widgetFamily, …)` does not compile, so a preview cannot
  inject either. Each rectangular surface is therefore its own view (addressable
  without a family) with an optional `mode:` that stands in for the environment;
  both are nil in the widgets themselves.

**Looking at a complication without putting it on a face:** `-screen widgets`
and `-screen widgets-tint` render both rectangular widgets inside the watch app
(`Watch/WidgetPreview.swift`), and both are pinned in the snapshot references.
The tinted pane emulates the flattening with `tint.mask(view)`, which is
literally the same operation — every pixel becomes the tint, alpha preserved.
It is the worst case, since the real thing has two shades, so a layout that
reads there reads on a face. Note the masked view needs a `.hidden()` copy
underneath to carry the size: a mask is as flexible as the colour it masks and
the pane otherwise collapses to nothing.

`WatchWidgets/WidgetSurfaces.swift` is compiled into **both** the widget
extension and the watch app — that is what makes the preview possible, and it is
declared file-by-file in `project.yml` under `CurrimusWatch`.

## Watch haptics

`WKInterfaceDevice.play(_:)` is the only haptic API on watchOS, and watchOS
pairs a sound with every type. An app **cannot** play a silent haptic; whether
anything is audible is the wearer's Silent Mode setting. `.notification` and
`.success` are the two that sound like a little tune — both were removed in
CUR-6. Patterns are built by repeating tap types (`.click`, `.directionUp`,
`.directionDown`) on a `Task` with `Task.sleep` between them.

## Main-thread work to avoid

Two that caused visible stutter on an iPhone 14 Pro Max, both fixed, both easy
to reintroduce:

- `RunStore.persistSettings()` / `pushSettings()` run on the io queue. A
  `JSONEncoder` pass, three `UserDefaults` writes and `updateApplicationContext`
  — a synchronous hop into another process — behind every toggle in Settings.
- The log rebuilds **every** row on every state change (eager `VStack`, see
  above), so a row must stay cheap. Date formatting, number formatting and
  `run.classification` (which walks the splits twice) are precomputed once per
  log change in `RunStore.logText`. Do not put formatting back into `LogRow`.

## Demo mode is sealed off from the app group (was not, until CUR-31)

A `-demo 1` store now reads nothing from the shared defaults and writes nothing
to them: its settings are the plain defaults, every time. So a demo screenshot
is a picture of the demo data and nothing else.

Worth knowing because the old behaviour cost real time. `persistSettings()` used
to write even in demo mode, and `loadSettings()` ran unconditionally, so a
`-demo 1 -zones derived` run left its injected max HR in that simulator's app
group and **every later demo run read it back**. The symptom was a watch demo run
sitting in zone 5 from end to end with its caption stuck on "MAX" — against a
stray `maxHR: 136` no screen mentioned. If you ever see a demo run whose numbers
cannot come from `SampleData`, check whether that seal has been broken again:

```bash
python3 -c "
import plistlib, json
p='<simulator>/data/Containers/Shared/AppGroup/<id>/Library/Preferences/group.com.currimus.app.plist'
print(json.loads(plistlib.load(open(p,'rb'))['settings.v1']))"
```

The stale values may still be sitting in an app group on this machine. They are
harmless now — `testADemoStoreNeitherReadsNorWritesTheSharedSettings` is what
keeps them harmless.
