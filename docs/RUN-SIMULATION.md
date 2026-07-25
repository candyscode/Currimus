# Run simulation

Tools for finding bugs in how a run is recorded and shown — especially the ones
that only appear at length, where a real device session is too slow and too
tedious to reach. A run is described once, as a `RunScenario`, and driven two
ways: headless in a test, and live on the watch.

Everything here is `#if DEBUG` — like `SampleData`, none of it reaches a shipped
binary.

## The scenario (`Shared/RunScenario.swift`)

A `RunScenario` deterministically describes one run, sampled per second: target
pace, heart rate, altitude, and whether a GPS fix arrives — each as a function of
elapsed time — plus a stop condition (a distance or a duration). Nothing is
random, so the same scenario always produces the same run, which is what lets a
"defined test set" mean the same thing twice.

The library is that test set:

| key | what it exercises |
|-----|-------------------|
| `marathon` | an even 5:00/km road marathon — the canonical long run |
| `negsplit` | a marathon that speeds up in the second half |
| `ultra` | a 50 km / ~6 h mountain ultra, ~1500 m of climb |
| `pacer` | a pacer run holding target |
| `treadmill` | distance from pace, no GPS at all |
| `dropout` | GPS lost between km 3 and 5 |
| `hrgap` | the heart-rate strap drops for two minutes |
| `stopgo` | a real standstill at a crossing (clock runs, pace blanks) |
| `walkrun` | a 4:1 run/walk session — big pace steps, folded into steady km |
| `paused` | a long run paused five minutes (clock stops, track keeps the gap) |
| `saver` | battery-saver GPS — sparse, coarse fixes, distance still whole |

Add one by extending `RunScenario` with another static factory and listing it in
`.all`.

## Layer 1 — headless simulator (`Shared/RunSimulator.swift`)

`RunSimulator` runs a scenario through the **real** `RunMetrics` pipeline exactly
the way `RunSession` drives a live recording — pace → distance → tick → splits,
plus altitude and route ingestion — but instantly. A four-hour marathon or a
six-hour ultra is simulated in milliseconds, so "is every kilometre recorded,
does anything drop on a long run" becomes a unit test instead of a device
session nobody watches to the end.

`Tests/RunSimulationTests.swift` asserts what only goes wrong at length: a
dropped kilometre, a truncated profile, a route that loses its start, a
quadratic slow-down. Run them with the rest:

```bash
xcodebuild test -scheme CurrimusTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

What it has already established: the pipeline records completely (42/42 and 50/50
splits), stays bounded by decimation that keeps both ends of the profile and
track, and a six-hour run simulates in ~50 ms — linear, not quadratic. Those are
now permanent regression guards.

## Layer 2 — live playback (watch, DEBUG launch arguments)

The same scenarios play through the live watch UI, so a whole run can be watched
— and screenshotted — unfolding on screen. Drive it with launch arguments:

```bash
BID=com.currimus.app.watchkitapp
# play a marathon live at 30× real time (a watchable run)
xcrun simctl launch <watch-udid> $BID -simulate marathon
# jump straight to km 25 of the ultra — a long run's live screen
xcrun simctl launch <watch-udid> $BID -simulate ultra -at 25
# jump to the finished summary
xcrun simctl launch <watch-udid> $BID -simulate pacer -finish 1
# play live at 60×
xcrun simctl launch <watch-udid> $BID -simulate marathon -speed 60
```

`-simulate <key>` alone plays live; `-at <km>` jumps to a distance; `-finish 1`
jumps to the summary; `-speed <N>` sets the live rate. The scenario feeds the
real pipeline (`metrics.tick`, `raiseKilometerAlert`), so the screens render
exactly what a real run of that shape would.

This is how the "blind" long-run states finally got looked at — a 42 km run deep
in, a 50 km ultra's summary with a four-digit climb and a six-hour clock. Driving
it immediately turned up two bugs that had never been on screen before: a pacer
summary grammar slip ("behind of the target") and a 40 mm trail-summary overflow
at ultra distances, both since fixed.

## How the two layers fit together

- **Layer 1** is the net: fast, deterministic, part of CI, guards the recording
  arithmetic and data-completeness forever.
- **Layer 2** is the eyes: renders those same scenarios so a human (or Claude)
  can spot what an assertion wasn't looking for — layout, copy, overflow.

A bug found in one is reproducible in the other, because both consume the same
`RunScenario`.

## Pre-push gate

`.githooks/pre-push` runs the unit + simulation tests (which include
`RunSimulationTests`) on every `git push`, blocking it only on a real test
failure. Enable it once per clone:

```bash
git config core.hooksPath .githooks
```

- Bypass a single push: `git push --no-verify`
- Override the simulator: `IOS_SIM="iPhone 16 Pro" git push`

The UI snapshots are **not** in the gate — they proved too flaky to block a push
automatically (date-relative demo data, a non-deterministic MapKit map,
occasional xcodebuild crashes). They are a **manual** step on any UI change
instead — see [UI-SNAPSHOTS.md](UI-SNAPSHOTS.md).
