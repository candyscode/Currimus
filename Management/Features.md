# Currimus Features & Changes

## How to use this document

This document is the single source of truth for **planned, WIP and open** features of the Currimus app (incl. all targets like iOS, watchOS, tvOS etc.). Everything that is finished lives in [Features-completed.md](Features-completed.md).

This document (Features.md) is checked into the repo and is modified by the project manager of Currimus (Andi) and all AI agents working on the project. Typically, Andi adds new features and AI agents pick them up, add the Markdown accordingly with the status and add results. Furthermore, AI agents have to make sure, the MD is always formatted properly and contains all relevant information. A feature can always has one of the following status: In Specification (Agent must not work on the feature as Andi is not done specifying it yet), Open (Not started yet, free to be taken by an AI agent), WIP (AI Agent is currently working on the feature / the feature has been started but is NOT completed yet), Done (Feature is finished, committed and pushed).

**When a feature reaches Done, move its whole section — description, agent comments, review, commit link — out of this file and append it to `Features-completed.md`, keeping the numeric order there.** This file then only ever holds tickets in In Specification, Open or WIP. Both files are committed together with the work they describe.

A feature is specified like this:

### CUR-0: Feature Title

[ ] In Specification
[X] Open
[ ] WIP
[ ] Done

Feature Description (may include acceptance criteria etc.)

#### Agent Comments
Could not complete, due to...; Decision needed, which is...;

#### Link to completed work (e.g. commit, PR, branch etc.)
https://[...]

Every feature has a unique ID: CUR-1, CUR-2, CUR-3 etc. Commit and and branch names contain the feature ID and a short description of the change. IDs are never reused — the next new ticket takes the highest ID found in **either** file plus one.

## Features

### CUR-9: Coaching Mode (for beginners)
 [X] In Specification
[ ] Open
[ ] WIP
[ ] Done

### CUR-10: Intervall Mode
 [X] In Specification
[ ] Open
[ ] WIP
[ ] Done

### CUR-11: Liquid glass fallback for older iOS Versions
 [ ] In Specification
[ ] Open
[X] WIP
[ ] Done

IMPORTANT: For now, please do NOT implement anything but include the implementation plan in the agent comments below. I will review the proposal and then give you the ok, to start implementing.

Currently, we loose a not of customers which do not have the iOS version that introduced liquid glass. Create a fall-back version of the liquid glass ui that enables the minimum iOS version of Currimus to be much lower than currently. The look and feel shall be very close to the liquid glass ui we have right now. Of course, this change also applies to the Apple Watch part of the app.

Choose a sensible minimum iOS and watchOS target that is a good tradeoff between user base and still modern enough UI framework to have a good / similar match to the current UI.

#### Agent Comments

**Status: proposal only — nothing implemented, waiting for your go-ahead.**

**The audit first, because it changes the answer.** The app leans on Liquid Glass far less than it looks. `.glassEffect` appears in exactly **two** places: `GlassIconButton` (the round back/settings buttons) and the log's floating delete bar. Everything else that reads as glass is already hand-built from plain fills — `GlassCard` is a white-at-4.5 % fill with a hairline border, `TopScrim` is `.ultraThinMaterial` under a gradient, the chips and toggles are Capsules. The watch app uses no Liquid Glass at all. So the "fallback" is small; what actually sets the floor is a handful of ordinary SwiftUI APIs.

**Recommended targets: iOS 18.0 and watchOS 10.0.**

| step | what it buys | what it costs |
|---|---|---|
| iOS 26 → **18.0** | every iPhone Apple still supports at iOS 18 (A12: XS, XR, and up) plus everyone who simply has not updated | the two `.glassEffect` call sites need a fallback; the tab bar renders as iOS 18's own translucent bar instead of Liquid Glass |
| 18 → 17 | **no new devices** — iOS 17 and 18 support the same hardware — only users lagging one version | `onChange(of:)`'s two-parameter form, `Tab(value:)` → `TabView { … .tabItem { } }` |
| 17 → 16 | iPhone 8 / X (A11, 2017) | the above, plus a real regression-test pass on a device class we have never run on |
| watchOS 11 → **10.0** | Apple Watch Series 4 and 5 (watchOS 11 needs Series 6+) | nothing found: the watch app's newest API is `.containerBackground(for: .widget)`, which is watchOS 10 |

iOS 18 is the sweet spot — it recovers the whole supported device range for two fallbacks and a tab bar that looks like the OS it is running on. Going to 17 or 16 buys progressively less for progressively more risk.

**The plan, in order:**

1. **One abstraction, two call sites.** Add `func glassSurface<S: Shape>(in shape: S) -> some View` to `iOS/Glass.swift`:
   `if #available(iOS 26, *) { content.glassEffect(.regular, in: shape) } else { content.background(.ultraThinMaterial, in: shape).overlay(shape.stroke(Theme.glassCardStroke, lineWidth: 1)) }`
   Replace both `.glassEffect` calls with it. `.ultraThinMaterial` plus the design's own hairline is visually very close at these sizes — the round buttons are 44 pt and the delete bar is a dark capsule over a dark background.
2. **The tab bar.** `Tab(value:)` is iOS 18, so the code compiles unchanged; below iOS 26 it simply draws the standard tab bar. Recommend accepting that rather than hand-drawing a floating bar: the design's own glyphs already carry the brand, and a hand-built tab bar is a permanent maintenance cost for a cosmetic difference. (If you want the floating look everywhere, that is a separate, larger piece of work — say so and it gets its own ticket.)
3. **Lower the targets** in `project.yml` (`deploymentTarget: iOS "18.0"`, `watchOS "10.0"`), regenerate, and fix whatever the compiler then objects to. Expect very little: the audit found no other iOS 19–26 API in the codebase.
4. **Check the two version-sensitive spots by hand**: the pushed-screen back button (glass circle) and the log's delete bar, on an iOS 18 simulator.
5. **Verify.** The snapshot harness pins one device and OS, so this does not want a second committed baseline. One manual pass with `IOS_SIM` pointed at an iOS 18 simulator, comparing by eye, is the right amount of ceremony.
6. **App Store Connect**: the minimum-OS field follows the build automatically; no listing change needed.

**Risks:** an iOS 18 simulator runtime has to be installed to test at all (it is not on this machine today). `.ultraThinMaterial` renders slightly lighter than Liquid Glass over bright content — on this app's near-black background the difference is small, but it is the one thing worth looking at with your own eyes before signing off.

**Effort:** roughly half a day including the manual pass.

#### Link to completed work

Proposal only: https://github.com/candyscode/Currimus/commit/04a0a83

### CUR-12: iOS Widgets
 [X] In Specification
[ ] Open
[ ] WIP
[ ] Done

To be designed by Claude Design.

### CUR-13: Optimize for smaller Apple Watches
 [ ] In Specification
[ ] Open
[X] WIP
[ ] Done

IMPORTANT: For now, please do NOT implement anything but include the implementation plan in the agent comments below. I will review the proposal and then give you the ok, to start implementing.

Currently, we are very focussed on Apple Watch Ultra screen sizes. Make an evaluation on how the app looks on medium and small sized Apple Watches and make improvement suggestions. 

The main customer base uses Apple Watch Ultras however, so this is the focus. 

The UI must not change at all to what it currently looks like on Apple Watch Ultra, but should simply improve on smaller Watches.

#### Agent Comments

**Status: evaluation + proposal only — nothing implemented, waiting for your go-ahead.**

**How this was evaluated.** The snapshot harness was pointed at an **Apple Watch SE 3 (40 mm)** — the smallest case Apple still ships, 324 × 394 px against the Ultra's 410 × 502 — and every screen captured and read. Nothing in the app was changed; the Ultra references in the repo are untouched.

**The good news:** the layout holds up far better than expected. Home, the live Run screen, the Pacer screen and the run Summary all fit, nothing overlaps, and the hero numbers stay legible. `RunScaffold`'s "hero at the top, footer at the bottom, spare height pooled between" does the right thing at every size. Three things break, and all three are the same kind of break: **type that was allowed to paint outside its box because the Ultra had room for it.**

**Finding 1 — the caption collides with the system clock (worst of the three).**
On the Summary and Trail Summary screens, "RUN COMPLETE" and "TRAIL COMPLETE" run under the clock in the top-right. On the Ultra there is 86 px more width and they clear it. The captions on the *live* screens ("RUN", "TRAIL", "PACER") are short enough to be fine everywhere.
*Fix:* `TopBarCaption` should know the screen it is on — either a shorter string on narrow cases ("COMPLETE" instead of "RUN COMPLETE"), or a reserved right-hand inset for the clock that the caption is laid out against. The reserved inset is the better fix: it is one change in `TopBar.swift` and it protects every future caption.

**Finding 2 — `labelOutsideLayout` runs off the edge.**
`BigStat(labelOutsideLayout: true)` deliberately lets a long label paint past its column (a CSS-overflow trick, so a wide label does not widen a `1fr` grid column). On the Ultra that spills into spare margin; on 40 mm it spills off the screen. Seen on the Trail screen: "M/H · LAST 10 MIN" is cut to "M/H · LAST 10 MI".
*Fix:* keep the overflow, but clamp it to the screen: allow `minimumScaleFactor` on those labels below a width threshold, or shorten to "M/H · 10 MIN" on narrow cases. Scaling is invisible on the Ultra and costs nothing there.

**Finding 3 — the elevation axis label truncates.**
Trail Summary's profile shows "1.024…" where the Ultra shows the full "1.024 m". A four-digit elevation plus the unit does not fit the axis gutter at 40 mm.
*Fix:* drop the unit on the axis labels when the value is four digits, or use "1.0k".

**What I would do, and in what order:**

1. A single `WatchSize` helper (`WKInterfaceDevice.current().screenBounds.width`, bucketed into narrow / regular / ultra) so these decisions are made in one place rather than sprinkled as magic numbers. **The Ultra bucket returns exactly today's values**, so its rendering cannot change — that is the constraint this ticket is built around, and it should be enforced by construction, not by care.
2. Fix the three findings above against that helper.
3. Add `WATCH_SIM="Apple Watch SE 3 (40mm)"` as a **second** reference set in the snapshot harness (`Tests/UISnapshots/reference/watch-40/`), so a regression on the small case is caught rather than discovered. The harness already takes `WATCH_SIM`; it needs a per-device reference directory.
4. Re-read all 15 watch screens on 40 mm and on the 42 mm Series 11 after the fixes.

**Effort:** about a day, most of it in step 3 and the re-read.

**Not proposed:** any change to spacing, type scale or layout proportions. The 40 mm screens are tight but correct, and shrinking type to buy margin would cost the glance-ability the whole watch UI is built for. These are three overflow bugs, not a design problem.

#### Link to completed work

Evaluation only: https://github.com/candyscode/Currimus/commit/04a0a83

### CUR-14: Hiking mode
 [X] In Specification
[ ] Open
[ ] WIP
[ ] Done

Maybe based on trail run mode but with different metrics? How to exclude from progress page? How to make this clear in the UI?
