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

Climb comes from the **barometer** (`CMAltimeter.startAbsoluteAltitudeUpdates`),
not from `CLLocation.altitude`. GPS altitude error is two to three times the
horizontal one and it wanders while standing still; summing it over a run read
20–25 % high against Apple Fitness (CUR-40). Apple Fitness uses the barometer,
and `CMAltimeter`'s absolute altitude is the same sensor fusion.

- `NSMotionUsageDescription` is **required**. Without it, touching `CMAltimeter`
  is a crash, not a denial. It lives in `project.yml` as an
  `INFOPLIST_KEY_`.
- Absolute altitude needs a Series 6 or newer, which is also what watchOS 11
  needs — so on every watch that can run Currimus it is available.
  `BarometricAltimeter.isAvailable` is asked anyway; a `false` falls back to
  the GPS altitude path in `integrate`.
- **Never feed both sources into one series.** The handover leaves a step, and
  the step is counted as climb.
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
