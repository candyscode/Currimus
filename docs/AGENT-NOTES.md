# Agent notes

Things that cost time to work out once, written down so they cost nothing the
next time. Process lives in `Claude.md`, tickets in `Management/Features.md`.

## Build, test, run

```bash
xcodegen generate                       # after ANY new/renamed/removed source file
xcodebuild build -scheme Currimus      -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild build -scheme CurrimusWatch -destination 'platform=watchOS Simulator,name=Apple Watch Ultra 3 (49mm)'
xcodebuild test  -scheme CurrimusTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

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

`record` **overwrites the references for whichever simulator it runs on**. The
baseline is pinned to iPhone 17 Pro / Apple Watch Ultra 3 (49mm) — running it
with `WATCH_SIM` pointed elsewhere silently replaces the baseline with captures
from the wrong device. Recover with `git checkout -- Tests/UISnapshots/reference`.

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
- The simulator has no Health data whatsoever. Anything derived from Health
  (zones, cadence, imported runs) needs a DEBUG injection to be seen at all —
  see the `-zones derived|updated|coach` flags.

## Watch haptics

`WKInterfaceDevice.play(_:)` is the only haptic API on watchOS, and watchOS
pairs a sound with every type. An app **cannot** play a silent haptic; whether
anything is audible is the wearer's Silent Mode setting. `.notification` and
`.success` are the two that sound like a little tune — both were removed in
CUR-6. Patterns are built by repeating tap types (`.click`, `.directionUp`,
`.directionDown`) on a `Task` with `Task.sleep` between them.

## Demo settings leak into the app group

`RunStore.persistSettings()` writes even in demo mode (the widget has no other
way to learn the goal), so a `-demo 1 -zones derived` run leaves its injected
max HR in the real app-group defaults on that simulator. Harmless on a device;
on this machine it means a snapshot reference can be recorded against a max HR
some earlier run left behind. Worth knowing before chasing a phantom diff.
