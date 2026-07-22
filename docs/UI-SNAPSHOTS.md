# UI snapshot regression tests

A safety net for the *look* of the app. It drives Currimus through its built-in
DEBUG screenshot routes on a pinned simulator, captures every screen, and diffs
each one against a committed reference image. If a change moves a card, clips a
number, recolours a stat, drops a divider or overflows the screen, the diff
turns magenta and the run fails.

```bash
scripts/ui-snapshot.sh verify all      # compare every screen against references
scripts/ui-snapshot.sh verify ios      # just the iPhone
scripts/ui-snapshot.sh verify watch    # just the watch
scripts/ui-snapshot.sh record all      # (re)write references — see "Updating"
scripts/ui-snapshot.sh verify all --no-build   # reuse the last build
```

Exit code is `0` when everything matches and non-zero when anything changed, so
it drops straight into a pre-push hook or CI step.

## Why screenshots, not view snapshots

The design leans on Liquid Glass, `.ultraThinMaterial`, the native Liquid-Glass
tab bar, native wheel pickers and MapKit. An in-process `ImageRenderer` (what
libraries like swift-snapshot-testing use) renders none of those faithfully — it
would miss exactly the glass/material/picker glitches this test exists to catch.
A real device screenshot is the only thing that shows what the user sees.

watchOS is the other reason: it has no XCUITest, so a full-device screenshot
driven by `simctl` is the only way to regression-test the watch UI at all.

The app was *built* for this: the `-screen`, `-tab`, `-push`, `-home`, `-demo`
launch arguments (see `DebugFlags`, `CurrimusApp`, `WatchApp`) exist so every
screen can be reached deterministically from a launch argument. This harness is
the codified form of the screenshot workflow already used to verify the design.

## What is compared, and how strictly

Each screen is listed in `scripts/uisnap/ios-routes.txt` or `watch-routes.txt`
as `name | tier | launch-arguments`. The tier picks the diff budget:

| tier | tolerance | budget | used for |
|------|-----------|--------|----------|
| `strict` | 12 / 255 | 0.20 % | pixel-stable screens — guards every detail |
| `medium` | 16 / 255 | 1.5 % | live run screens whose elapsed time keeps ticking |
| `loose`  | 18 / 255 | 3.5 % | screens whose content is relative to *today* |

*tolerance* is the per-channel delta a pixel may drift before it counts as
changed (absorbs sub-pixel antialiasing); *budget* is the share of pixels
allowed to change before the screen fails.

Two sources of non-determinism are handled directly rather than by loosening the
budget:

- **The clock.** On iOS the status bar is pinned to 9:41 with a full battery
  before capture. On the watch `simctl` can't pin it, so the top-right corner
  (clock + pairing glyph) is masked out of every watch comparison — it shows up
  blue in the diff image.
- **Ticking time.** The live run/pacer/trail screens keep counting between
  launch and capture, so their seconds glyphs drift a little; that is what the
  `medium` tier's budget absorbs. Structure, colour and layout are still held to
  account — a 1.5 % budget is tiny next to a moved card or a collapsed column.

### The honest limitation: date-relative screens

The demo data (`SampleData`) is generated relative to `.now` — the race
countdown, the week bars, the "yesterday" labels and the monthly totals all
shift day to day. Those screens (Home, Log, Progress, Race, Records, run
details) are therefore on the `loose` tier: the test guards their **structure**
(nothing vanished, overflowed or recoloured) but not their exact pixels.

Making them pixel-exact would need a frozen-clock debug hook threaded through
the ~60 `.now` reads in the store, models and views. That's a deliberate,
separate change; until then, the date-stable screens (Settings, Pacer defaults,
HR zones, GPS accuracy, Acknowledgements, Edit run, First launch, and the entire
watch app) carry the strict guard, and they are where fiddly layout regressions
actually hide.

## Updating references

References live in `Tests/UISnapshots/reference/{ios,watch}/` and are committed.
Re-record them **on purpose** whenever a design change is intended:

```bash
scripts/ui-snapshot.sh record ios      # after an intentional iPhone change
git add Tests/UISnapshots/reference     # review the image diff, then commit
```

Review the changed PNGs in the commit like any other diff — a reference update
should be as deliberate as the code change that caused it. Because the demo is
date-relative, the `loose` references also drift over calendar time; re-record
them if a stale date ever pushes one over its budget.

## Layout

```
scripts/
  ui-snapshot.sh            # entry point: build · boot · capture · diff
  uisnap/
    ios-routes.txt          # name | tier | launch-args  (iPhone)
    watch-routes.txt        # name | tier | launch-args  (watch)
    compare.swift           # dependency-free CoreGraphics pixel comparator
Tests/UISnapshots/
  reference/{ios,watch}/*.png   # committed baseline
  _work/                        # git-ignored: compiled comparator, captures, diffs
```

The comparator has no third-party dependencies — it is one Swift file compiled
on the fly with `swiftc`, using only ImageIO/CoreGraphics, so the harness runs
anywhere Xcode does.

## Simulators

Defaults are `iPhone 17 Pro` and `Apple Watch Ultra 3 (49mm)`; override with the
`IOS_SIM` / `WATCH_SIM` environment variables. Keep the reference device and OS
fixed — a different screen size or OS version will legitimately change every
pixel. The harness boots the simulator if it isn't already running.
