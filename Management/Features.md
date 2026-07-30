# Currimus Features & Changes

## How to use this document

This document is the single source of truth for planned, WIP and completed features of the Currimus app (incl. all targets like iOS, watchOS, tvOS etc.).

This document (Features.md) is checked into the repo and is modified by the project manager of Currimus (Andi) and all AI agents working on the project. Typically, Andi adds new features and AI agents pick them up, add the Markdown accordingly with the status and add results. Furthermore, AI agents have to make sure, the MD is always formatted properly and contains all relevant information. A feature can always has one of the following status: In Specification (Agent must not work on the feature as Andi is not done specifying it yet), Open (Not started yet, free to be taken by an AI agent), WIP (AI Agent is currently working on the feature / the feature has been started but is NOT completed yet), Done (Feature is finished, committed and pushed).

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

Every feature has a unique ID: CUR-1, CUR-2, CUR-3 etc. Commit and and branch names contain the feature ID and a short description of the change.

## Features


### CUR-1: Option to delete runs

[ ] In Specification
[ ] Open
[ ] WIP
[X] Done

Nur iOS App: Im Log-Tab soll man durch links-wischen auf einen Eintrag die Möglichkeit haben einen Löschen-Button zu bekommen, über den man den Eintrag löschen kann. Der Lauf wird dann sowohl aus Currimus als auch aus Apple Health gelöscht. Zudem braucht es im Log auch einen Markiermodus, wo man mehrere Läufe auswählen und dann auch löschen kann. In der Detailansicht eines Laufes soll es auch die Möglichkeit geben, den Lauf zu löschen (falls nicht bereits gegeben). Achte dabei darauf, dass die UI-Changes ins Look & Feel der App und zum Design System passen.

#### Agent Comments

Delivered on iOS only, four ways into the same delete:

- **Swipe left** on a log row reveals a signal-orange Delete tile (`SwipeToRevealRow` in `iOS/RunDeletion.swift`). The log is a hand-built scroll view, not a `List`, so the gesture is drawn by hand; it is attached with `simultaneousGesture` and ignores drags that are more vertical than horizontal, so the scroll view keeps its own gesture.
- **Marking mode**: a "Select" chip next to the filter chips turns the rows into checkboxes and swaps the tab bar for a floating glass bar with the count and a Delete button.
- **Run detail** has an outlined "Delete run" button at the bottom; it dismisses back to the log.
- The long-press context menu that already existed is still there.

Apple Health: deleting now removes the workout Currimus saved for the run *and* its GPS route (`HealthImport.deleteWorkouts`). Write access is asked for at the first delete rather than at launch. Two honest limits, both surfaced in the UI rather than hidden:

- Imported runs (recorded by other apps) cannot be deleted — HealthKit only lets an app delete its own samples. Those rows offer no swipe and no checkbox, and say where to delete them instead.
- If Health refuses or fails, the run still leaves Currimus and the log shows a dismissible notice (`RunStore.healthNotice`) instead of claiming a deletion that did not happen.

Untested by machine: the swipe gesture itself (no UI-test target — the harness screenshots states, it cannot drag). Worth one pass by hand on device.

#### Link to completed work

https://github.com/candyscode/Currimus/commit/b9d9424

#### Andi's Review

Swipe gesture does not work properly. Dragging to reveal delete button works, but when finger is released, the item goes back again and hides the button again. => Not clickable. The "Are you sure modal" looks custom. We can use the standard iOS modal, no? Imported runs dont even have the swipe feature, I get the point (not deletable), but it seems broken to the user. Maybe show a greyed out button that is pressable but shows an explanatory text that this is not possible due to iOS's limitation.

#### Agent Response

All three fixed.

**Second round (2026-07-28): the swipe still snapped back, and this time it is verified by machine.** The real cause was the row's content being a `Button`: a horizontal drag never leaves a full-width button's bounds, so SwiftUI never cancelled its tap, and lifting the finger fired the row's own tap — which closed the row before the delete tile could be pressed. The content is a plain view with a `TapGesture` now, which does not fire once the finger has travelled. A new **`CurrimusUITests`** target drives the actual gesture and asserts the tile is *hittable* after the swipe, stays open, and that a tap on a closed row still opens the run — none of which a unit test can express, `simctl` can inject, or a screenshot can show. That is why this broke twice.

- **The swipe snapping back (first attempt, insufficient).** Two causes, both removed. The row derived its offset from `openRow` (parent state) plus a live drag, so the settle animation depended on the parent's update landing inside the same transaction — when it did not, the row animated back to zero under the finger. The row now owns a single `offset` and `openRow` is used only to close the *others*. Second, each row carried a `.contextMenu` for the same long-press delete; `UIContextMenuInteraction` competes with the drag for the touch and cancels it. The context menu is gone — the swipe, the marking mode and the detail screen are three ways in already.
- **The dialog** is a plain `.alert` now, on both the log and the run detail. It was a `confirmationDialog` (an action sheet) — also standard, but it evidently did not read that way.
- **Imported runs swipe too.** The tile is greyed and still pressable; pressing it explains that Apple Health only lets the app that recorded a run delete it, and where to do it instead. A row that silently swallows the gesture looks broken, which was exactly your point.

### CUR-2: Re-calculate heart rate zones on app start

[ ] In Specification
[ ] Open
[ ] WIP
[X] Done

Wir berechnen ja aktuell die Pulszonen auf Basis von einigen Eckdaten aus Apple Health. Das kann sich ja verändern über die Zeit. Vielleicht wird die Person ja fitter oder weniger fit.  Dementsprechend bitte bei jedem Aufstart der App das Ganze einmal neu ziehen und neu berechnen und neu anpassen, dass die Pulszonen einfach immer aktuell sind mit den Informationen, die von der Apple Watch aufgezeichnet werden, wie maximale Herzfrequenz, hohe Herzfrequenz und so weiter, wie wir das halt auch immer momentan berechnen. Zeige dem Nutzer beim Aufstand und wenn sich die Pulszonen tatsächlich verändert haben (z.B. Zone 2 geht jetzt bis 160 BPM statt 155 BPM) einen kurzen nicht-invasiven Hinweis an, dass die Pulszonen geupdated wurden. Baue auch in die Pulszonen-Seite in den Einstellungen einen kurzen Hinweis-Text ein, wie sich die Pulszonen berechnen (aus welchen Werten aus Health und dass diese regelmäßig geupdated werden). Achte dabei darauf, dass die UI-Changes ins Look & Feel der App und zum Design System passen.

#### Agent Comments

- The re-derivation on every launch and every return to the foreground was already wired up (`RunStore.refreshImportedRuns` → `refreshHeartRateZones`); what was missing is everything around it.
- **The notice.** `HRZones.changeSummary(from:to:)` names the boundary that moved furthest — "Heart rate zones updated from Apple Health. Zone 4 now ends at 173 bpm instead of 169." It shows as a dismissible `NoticeCard` at the top of Home and taps through to the zones screen. Suppressed for the very first derivation (that is the app learning the runner, not an update) and for a forced recalculation (those numbers are already on screen).
- **One correction to existing behaviour:** a max heart rate the runner had set by hand was being overwritten by the automatic refresh, because only hand-set *boundaries* were protected. `HRZones.isAutomatic` now covers both. "Recalculate from Apple Health" is how control is handed back.
- **The zones screen** gained a "HOW THESE ARE KEPT CURRENT" section naming the two Health values and where each comes from (third-highest daily peak of the past year; Health's own 60-day resting average), that they are re-read on every launch, and what stops that.
- `-zones updated` (DEBUG) injects the notice — the simulator has no Health data, so the banner is otherwise unreachable.

#### Link to completed work

https://github.com/candyscode/Currimus/commit/940260d

### CUR-3: Minor UI improvements in run detail view

[ ] In Specification
[ ] Open
[ ] WIP
[X] Done

iOS App Run Detail Ansicht: Stelle die Zeit in den Pulszonen nicht mehr als einen einzelnen horizontalen Indicator mit prozentualen Anteilen der Zeit in den Pulszonen, sondern anstelle das als fünf horizontale Balken untereinander dar, wo man dann Zone 1 bis 5 untereinander aufgeschlüsselt sieht. Auf der Apple Watch gibt es ja auch diesen einen Pulszonen Übersichts-Balken (den wir auf iOS ersetzen). Auf der Apple Watch soll er bleiben. Dann bezüglich der Splits, die Verbrauchen aktuell bei langen Runs sehr viel Platz. (Halbmarathon = mind. 21 Balken untereinander). Dementsprechend überleg dir für die Splits eine Möglichkeit, nur das Allerwichtigste bezüglich den Splits des Runs anzuzeigen, also vielleicht irgendwie durchschnittliche Split-Zeit und schnellste Split-Zeit oder so (deine Entscheidung, was für einen Läufer halt sinnvoll ist). Und das Ganze als Button, wo man dann drauf tippen kann und dann bekommt man die Anzeige mit den ganzen Splits, die wir aktuell schon haben. Einfach, dass wir im Run Detail View weniger Platz verschenken. Achte dabei darauf, dass die UI-Changes ins Look & Feel der App und zum Design System passen.

#### Agent Comments

- **Zones**: `ZoneBreakdown` (iPhone only) replaces the proportional strip with five bars off a common baseline — `Z2 · Easy [bar] 1h 05` — and hours once a zone passes 60 minutes, so an ultra reads "4h 12" and not "252m". Runs without heart-rate data say so in one line instead of drawing five empty bars. The watch keeps `ZoneHeatStrip` (a stacked list does not fit a 49 mm screen), as does the Home summary card.
- **Splits**: `SplitsSummary` folds them into one card — AVG /KM, FASTEST, SLOWEST, plus a line on how the second half ran against the first ("Second half 4 s/km faster — a negative split"), which is the judgement the bar chart made you count out by eye. Tapping expands to the full per-kilometre list, unchanged.
- The section only renders from two kilometres up: an imported run carries no splits and used to show a heading over empty space.
- Net effect on the demo half marathon: the whole road detail now fits in roughly one screen instead of three.

#### Link to completed work

https://github.com/candyscode/Currimus/commit/b8b5a3d

### CUR-4: Remove feature in run mode to change pace color to orange

[ ] In Specification
[ ] Open
[ ] WIP
[X] Done

Apple Watch: Im Run-Modus wird die Pace, die dort angezeigt wird, manchmal rot. Dieses Feature versteht man nicht als Kunde. Bitte ausbauen, die Pace soll einfach immer weiß angezeigt werden.

#### Agent Comments

Two places coloured the live pace, both gone:

- **Run**: pace was orange the whole time (white only with the wrist down), so it read as a warning about a number nobody had set a target for.
- **Pacer**: pace turned orange whenever the runner was more than 6 s/km *fast*. That is the "sometimes" in the ticket. The gauge and the FAST/SLOW caption under it still say the same thing, in a shape built to say it — only the number stopped shouting.

Trail already showed white. Left alone on purpose (say the word if these should follow): the post-run **summary** screens still show avg pace in signal orange, as does the run detail on iPhone — there it is a stable accent, not a state that comes and goes.

#### Link to completed work

https://github.com/candyscode/Currimus/commit/01ec12e

### CUR-5: Show heart rate zone indicator also when user is not looking

[ ] In Specification
[ ] Open
[ ] WIP
[X] Done

Nur Apple Watch: Im abgedunkelten Modus (isLuminanceReduced), soll bitte weiterhin die Pulszonenanzeige hell bleiben und auch der Indicator (weiße Nadel) soll weiter angezeigt werden.

#### Agent Comments

- The **needle** is drawn with the wrist down again. It was hidden on the argument that heart rate arrives sparsely there, so a parked needle claims a position it no longer holds — but that is exactly the glance the mode exists for, and a needle a few seconds old still answers "high or low in the zone" better than no needle at all.
- The **bar** keeps full brightness: the active segment, its border, the Z1–Z4 heat when zone 5 burns, the resting track, and the zone number under it. All of those used to step down through `RunPalette` when the wrist dropped.
- One thing still steps back in always-on: the **glow** around a burning zone 5. It lights pixels beside the bar rather than in it, which is decoration — say the word if it should stay lit too.
- New snapshot route `run-aod` (`-screen run -aod 1`) captures the dimmed run screen; nothing covered it before.

#### Link to completed work

https://github.com/candyscode/Currimus/commit/63a8b92

#### Andi's Review

It seems the entire darkening feature is gone. Can you please check? Nothing darkens anymore when I put the wrist down.

#### Agent Response

You are right, and it was this ticket plus CUR-4 between them. The wiring was never broken — but `RunPalette.hero` had always returned full-strength ink for *every* number on the screen, so the only things that actually dimmed were the small captions. CUR-4 then took away the orange pace and CUR-5 lit the zone bar back up, and there was nothing visibly left.

Fixed by making something give: the hero (the clock, or the pacer's live pace) steps back to a light grey with the wrist down, and the numbers around it — distance, pace, climb — step back further. The zone bar, its needle and the zone number stay at full strength, which is what this ticket asked for. Captions are unchanged.

If the hero now feels too dark at arm's length in sun, it is one constant in `RunPalette` (`hero`, currently `0xC4C4C4`) — say the word and it goes back up. Snapshot route `run-aod` shows the result.

### CUR-6: Vibration-based heart rate zone indication

[ ] In Specification
[ ] Open
[ ] WIP
[X] Done

Wir bauen ein Feature ein, mit dem man ohne auf die Watch zu schauen in der entsprechenden Puls zurück bleiben kann. Und zwar kann man das in den Einstellungen der App in iOS einschalten und sagen, man möchte Vibrationshinweise für eine Pulszone. Und dann kann man auswählen, welche Pulszone man haben möchte, an die man erinnert wird, wenn man dabei ist, sie zu verlassen. Zum Beispiel Zone 2. Achte dabei darauf, dass die UI-Changes ins Look & Feel der App und zum Design System passen. 
Und dann läuft es wie folgend: Wenn man noch innerhalb der Zone 2 ist, aber in den unteren 15%, dann gibt es einen Vibrationshinweis der schnell hintereinander pulsiert, um dem Nutzer zu sagen: lauf etwas schneller. Das Vibrationsmuster läuft dauerhaft, solange er in dieser 15% Scheibe ist. 

Und wenn man den oberen 15% ist, wird wieder ein Vibrationsmuster abgespielt.  Diesmal aber mit langsameren Vibrationspulsen, um dem Nutzer zu sagen: lauf etwas langsamer.

Das soll ihm dann helfen, auch ohne auf die Uhr zu schauen, immer zu wissen, wo er sich innerhalb der Pulszone befindet 

Und wenn er die Pulszone verlässt (z.B. er möchte in Zone 2 bleiben und jetzt in Zone 3 ist) dann gibt's eine Dauer Vibration für 3 Sekunden und eine Full-Screen Display-Warnung ähnlich wie die Split-Anzeige (in die Richtung: "Du bist jetzt in Zone 3, werde langsamer").

Entferne alle Tonsignale, die die Apple Watch von sich gibt. Da haben wir aktuell so einen Bimmelton. Wir arbeiten ab sofort nur noch mit Vibrationen. 

#### Agent Comments

- **The decision layer** is `Shared/ZoneCoach.swift` — pure, no haptics and no clock of its own, so the cadence is asserted in `Tests/ZoneCoachTests.swift` instead of only being feelable on a wrist. `RunSession` feeds it the per-second tick and plays what it asks for.
- **Bands and patterns**: bottom 15 % of the target zone → four quick taps (`.directionUp`), repeating every 3.5 s while you stay there. Top 15 % → three slow taps (`.directionDown`), every 5 s. The two must never be confused through a sleeve, which is why one is fast and light and the other slow and heavy.
- **Losing the zone**: three seconds of buzzing (12 taps) plus a full-screen warning in the same treatment as the kilometre split — "ZONE 3 · Ease off · back down to zone 2" — for five seconds, on the Run, Pacer and Trail screens. It repeats every 60 s while the zone is still lost; firing once and never again would be a cue missed exactly when it mattered.
- **Zone 0 (no heart rate yet) is not the wrong zone.** Buzzing at someone whose strap has not connected is how a feature gets switched off for good.
- **Settings**: iPhone › Settings › Zone coaching — a toggle, the five zones with the runner's own bpm ranges, and a plain description of the three patterns. Off by default; switching it on defaults to zone 2.
- **Sounds**: `.notification` (the kilometre chime) and `.success` (the finish chime) are gone — those are the two watchOS plays as a little tune. Everything is built from taps now (`.click`, `.start`, `.stop`, `.directionUp/Down`). One honest limit: watchOS pairs a sound with *every* haptic type and gives an app no way to suppress it — whether any of it is audible is the wearer's Silent Mode setting, not ours. The two musical cues are what "Bimmelton" meant, and they are gone.
- Cues also run in the watch simulator's demo runs, since no simulated wrist has a pulse and that is the only place this can be watched at all.

#### Link to completed work

https://github.com/candyscode/Currimus/commit/44c1cc1

#### Andi's Review

There is no Zone 0! Only Zone 1 to Zone 5.

#### Agent Response

Correct — zero was an internal sentinel ("no heart rate yet", which draws the bar unlit) that leaked into the way I described the feature. `ZoneCoach.update` now takes `zone: Int?`, so the absence of a reading is expressed as an absence rather than as a sixth zone, and the comments and tests say so. Behaviour is unchanged: no reading still means no vibration.

### CUR-7: Show progress over pace in heart rate zone 2

[ ] In Specification
[ ] Open
[ ] WIP
[X] Done

As a runner, I want to track my progress on my pace while running in zone 2. So additional to the graph for avg. pace in the last 12 months, which we already have, I want another graph showing the avg. pace but only the paces are counted which were achieved while running in heart rate zone 2. For both of those graphs also runs from other running apps stored in Apple Health shall be taken into account. Make sure the UI changes fit into the look and feel of the app and the design system. Also make sure, that the two graphs stacked over each other in the progress tab look nice. If they don't, you are free to redesign the progress view.

#### Agent Comments

_Superseded by the rework below — see "Agent Response to the review"._

#### Andi's Review

I asked Claude regarding the shortcomings of CUR-7 and this was the answer. Implement everything it said, except the part marked optional. Make sure the UI looks good. Both graphs need their own x-Axis. 12 months instead of 12 weeks in this case. Zone 2 only, not configurable for now.

##### Start of Claude Review

What's actually wrong with it

1. The unit is the whole run, not the time in the zone. RunAnalytics.isRun(_:mostlyIn:zones:) asks "did this run spend ≥50 % of its time in zone 2", and if yes, the run's entire distance and duration go into the week. So a 20 km long run that was 60 % Z2 and 30 % Z3 contributes its Z3 kilometres too — and those are the faster ones. The bias has a direction: the chart flatters you. It reports zone-2 pace as quicker than you actually run in zone 2.

2. The 50 % threshold is a cliff. 49 % contributes nothing, 51 % contributes everything. Week-to-week movement in the line can come purely from runs crossing that line, which is noise dressed as fitness.

3. Imported runs are placed by mean heart rate — exactly where the mean lies. An interval session that alternates Z1 and Z4 averages neatly into zone 2. Strava intervals can land in your easy-run chart. Averaging HR is meaningless for precisely the run shape most likely to be misfiled.

4. Today's zones are applied to old runs. isRun takes store.zones — the current boundaries. CUR-2 now re-derives those on every launch, so a max-HR change silently reclassifies history for imported runs. Your own runs are safe (their zoneSeconds were frozen on the watch), imported ones aren't. That's an interaction between two tickets I shipped in the same session, and it's the one I'd want fixed regardless of what else you do.

5. The two headlines are computed differently — and I did that. The overall pace above is distance-weighted across the whole 12-week window (time / km). My zone-2 number is the unweighted mean of the weekly paces, so a week with one 5 km jog counts the same as a week with 60 km. Two numbers stacked to be compared, arrived at two different ways. That's a defect, not a trade-off.

6. The delta compares two single weeks — first present value against last present. Zone-2 series are sparser than the overall one, so those two weeks can be far apart and each can be a single run. And nothing in the UI tells you which points rest on 4 km and which on 40.

How to fix it, in the order I'd do it

First, today, ~15 minutes: make the headline distance-weighted like the one above it. Pure inconsistency, no design question attached.

Then the real fix: measure pace per zone at the source. RunMetrics.tick already gets elapsed, distance, heart rate and zone every second — it accumulates zoneSeconds and throws the distance half away. Add zoneDistanceKm[5] beside it, store it on Run as an optional array, and zone-2 pace becomes zoneSeconds[1] / zoneDistanceKm[1]: exact, per run, no threshold, no contamination. Every run then contributes its zone-2 portion rather than qualifying or not, and the weekly aggregate becomes a proper Σtime / Σdistance. That kills shortcomings 1, 2 and most of 5 outright. Cost is small — an array on the model, a few lines in RunMetrics, one field in the sync payload — but it only applies to runs recorded from then on, so you'd need to decide what the chart does with the twelve weeks of history that predate it (my instinct: keep today's approximation for legacy runs and don't mark the seam, since the error is small at the aggregate level).

Then imported runs. The honest fix is to read the workout's heart-rate samples from Health and build real zone seconds, instead of trusting one average. That's a heavier query, but it pays twice: those runs would also get a real zone breakdown in the run detail, where they currently show nothing. Together with freezing the zone bounds on each run, that closes 3 and 4.

Then the small honesty work: a delta over a smoothed window (first three weeks against last three) instead of two lone points, and a visual signal for weeks with little zone-2 volume.

Optional, worth arguing about: grade-adjust road runs with real climb (RunAnalytics.gradeAdjustedPace already exists) so hills don't read as lost fitness; and let the chart follow the zone chosen in CUR-6's coaching rather than hardcoding 2.

One more thing, since it's related: your ticket said twelve months and I built twelve weeks so the two charts could share an axis. For a base-building metric, months are the better window — fuller buckets, less noise — but it means giving up the shared axis. Worth deciding deliberately rather than inheriting my choice.

Want me to do the headline fix now and write the zone-distance recording up as CUR-15?

##### End of Claude Review

#### Agent Response to the review

Everything on the list is in, except the two items it marked optional (grade-adjusted road pace, and letting the chart follow CUR-6's coaching zone). Zone 2 stays fixed, as you asked.

**1 + 2 + 5 — the whole-run unit and the 50 % cliff are gone.** `RunMetrics` now records the distance covered in each zone alongside the seconds it already kept, and a run carries `zoneDistanceKm`. Zone-2 pace for such a run is exactly `zoneSeconds[1] / zoneDistanceKm[1]`: its zone-2 portion counts, the rest of it does not, and there is no threshold to fall either side of. The month is aggregated as total time over total distance — the same arithmetic as the overall pace above it, which fixes the mean-of-means headline as well.

Runs recorded before this ticket have no per-zone distance and cannot get one, so they keep the old approximation (majority of time in the zone → the whole run counts). The chart says so under itself when any month rests on one: "Older runs count whole, so the early months are approximate." That sentence disappears by itself as the log turns over.

**3 + 4 — imported runs.** Reading the heart-rate trace out of Health turned out to be its own ticket, so it is CUR-15: an imported run's real zone seconds are built from its samples the first time its detail screen is opened, and they are persisted. Once that has happened the run is placed by what it actually did rather than by an average heart rate that means nothing for an interval session — and because the result is stored, a later change to the zone boundaries cannot silently reclassify it. Until a run has been opened it still falls back to average heart rate, which is the best available.

**6 — the delta and the sparsity.** `RunAnalytics.trendChange` averages three months at each end instead of comparing two lone points. Under the chart, in plain text: how many runs and how many kilometres the line is built from.

**Window and axes.** The zone-2 chart is twelve months, on its own axis (every third month labelled). The overall pace chart keeps its twelve weeks and gets its own axis back. They are separated by a divider rather than stacked under one shared axis, since they no longer cover the same period.

**Demo data** now spans a full year and carries per-zone distance, so the twelve-month chart has twelve months to draw and the measured path is what you see.

#### Link to completed work

https://github.com/candyscode/Currimus/commit/e8eae58

### CUR-8: Show hints to improve running style in run detail view

[ ] In Specification
[ ] Open
[ ] WIP
[X] Done

This, for now, only applies to the Run and Pacer mode, not the trailrun mode (so all modes which track more or less horizontal runs not on a mountain). Create a section in the run detail view that shows hints to the user on how to improve next time. If there is nothing to improve, the section is not shown. For now, there is only one hint to be shown. The app shall tell the user when the cadence (steps per minute) is too slow for the avg. pace he had during this run. Find the ideal cadences yourself (do an internet research). The hint shall be like "Good work! To further improve your running style and to save your joints try to do more and smaller steps. Try to think you are running on a slippery surface like ice, this may help" (of cource find a better wording!)

In the future, we will include more hint types and might even integrate AI-generated hints, so make the UI hint section extensible. Make sure the UI changes fit into the look and feel of the app and the design system.

Also, show the avg. cadence also in run detail view, regardless if there is a hint or not. 

#### Agent Comments

**Cadence had to be measured first.** Nothing in the app counted steps. The watch now enables step collection on the live workout (`HKLiveWorkoutDataSource.enableCollection(for: .stepCount)`, not in the default set for running), and a run carries `cadenceSpm` — steps over its own moving time. Runs another app recorded get it from the workout's step total in Health, when that app wrote one. Runs recorded before this ticket have no cadence and are simply left alone.

**Where it shows.** SPM joins TIME · AVG /KM · CLIMB as a fourth stat in the run detail, always, hint or no hint. Also in the CSV export (empty, not 0, for runs without it — a zero would read as a runner who took no steps).

**The hint.** `Shared/RunHints.swift` — `RunHints.all(for:)` returns a list, the detail screen renders whatever is in it, and an empty list draws nothing. A second hint, or an AI-written one, needs no change to the screen.

**The research** ([TrainingPeaks](https://www.trainingpeaks.com/blog/finding-your-perfect-run-cadence/), [E3 Rehab](https://e3rehab.com/running-cadence/), [Heiderscheit et al. 2011](https://pmc.ncbi.nlm.nih.gov/articles/PMC3022995/), [12-week cadence retraining, PeerJ 2020](https://peerj.com/articles/9813/)):

- There is no single right cadence. The famous 180 spm came from watching elites *race*; studies of recreational runners find preferred cadence spread widely at any given ability, and the cadence–economy relationship is not linear. So the app uses a floor, not a target.
- Cadence rises with speed, so the floor ramps: ~158 spm at 7:00/km, 162 at 6:00, 168 at 5:00, 178 at 4:00, capped at 182. Below ~160 is the range typical of overstriding.
- Raising cadence 5–10 % at the same pace shortens the stride and cuts the energy the knee absorbs per step by roughly 20–40 % (Heiderscheit 2011). That is what the hint asks for — five per cent above what the runner actually held, so the next run has a reachable number.

**Deliberately reluctant.** The hint needs a 5 spm margin below the floor before it says anything, needs at least 2 km, and skips trail entirely (cadence on a mountain is set by the ground, and telling someone to take quicker steps up a scramble is advice about a run they did not do). Pacer and Run both qualify, as specified.

**Demo data** now carries a cadence per session type, with the long run deliberately short of the mark so the hint can be seen at all.

#### Link to completed work

https://github.com/candyscode/Currimus/commit/3d03070

#### Andi's Review

Are you happy with the solution or does it have significant shortcomings, we have to address?

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

### CUR-15: Imported runs from Apple Fitness app does not show heart rate zones and track on map.

[ ] In Specification
[ ] Open
[ ] WIP
[X] Done

Imported runs from Apple Fitness, Strava & Co. must also show heart rate zones and track on map in the run detail view. Currently shows "No GPS track for this run" and "No heart rate zones was recorded for this run".

#### Agent Comments

Both were there in Health all along; Currimus was only reading the workout's summary.

- **Zones** are rebuilt from the workout's heart-rate trace (`HealthImport.zoneSeconds`): every sample stands for the time until the next one, capped at a minute, so a strap that dropped out for an hour does not count as an hour in whatever zone it last saw. The samples are asked for by time window rather than by association — plenty of apps save a workout without tying the heart rate to it.
- **The route** comes from the workout's `HKWorkoutRoute` series and is cached in the same sidecar file every Currimus run uses, so the map, the elevation profile and the GPX export all work on it unchanged.
- **On demand, not on refresh.** Both are fetched when a detail screen opens (`RunStore.hydrateImported`), because pulling every sample of eighteen months of other apps' workouts on each foreground would spend a lot of battery filling screens nobody had opened. The second visit is free.
- Two things this needed on the way: the detail screen was reading `store.runs`, which never contains an imported run, so it kept showing the copy it was pushed with; and the sample-file prune ran against the owned list alone, so a fetched route was deleted on the next save.

**Second round (2026-07-28), from testing on device:**

- **No GPX track.** `HKSeriesType.workoutRoute()` was added to the read set *after* the install had already answered the Health prompt, so it sat undetermined and every route query came back empty — silently, because Health never reports a denied read. Authorization is now re-requested once per session at the first hydration, which raises the sheet for types that are new and is a no-op for the rest.
- **Zone times vanishing while the detail screen was open.** Same shape as review finding 1: the imported list is replaced wholesale on every refresh, and anything living only in it is one foreground away from being lost. The rebuilt zone seconds are written to the run's sidecar file now — the same place the route already lived, which is exactly why the route survived and the zones did not.

#### Link to completed work

https://github.com/candyscode/Currimus/commit/2ea9c45

### CUR-16: Code review of CUR-1…CUR-15

[ ] In Specification
[ ] Open
[ ] WIP
[X] Done

A review of the whole CUR-1…CUR-15 series and the working tree, run on 2026-07-28. Nine findings, all confirmed against the code and all fixed.

#### Agent Comments

Two of them meant a shipped feature quietly did not do what its ticket claims:

1. **Every foreground threw away the zones CUR-15 had fetched.** `refreshImportedRuns` replaces the imported list wholesale with what Health returns, and a workout *summary* carries no zone breakdown — so a run whose heart-rate trace had been read went back to zeros on the next return to the app, and the zone-2 chart silently fell back to placing it by its average heart rate. Hydrated zones are now carried across the refresh (`carryingHydratedZones`), and a fresher answer from Health still wins.
2. **Zone coaching went silent for the second run of an app session.** `RunSession` lives for the lifetime of the app, and the coach was only rebuilt when the target zone *changed* — so run two inherited run one's `lastFired`, sitting on the previous run's elapsed clock, and suppressed every cue until the new run passed the same elapsed time. The coach is rebuilt in `resetMetrics`, along with clearing a stale zone warning.
3. **The out-of-zone alarm fired during the warm-up.** Any zone that was not the target counted as "left", so a run that starts in zone 1 got three seconds of buzzing and a full-screen warning within seconds of starting, repeating every minute until the runner reached zone 2. A zone cannot be left before it has been reached; `ZoneCoach` now waits for the first arrival.
4. A route query that failed without setting `done` never resumed its continuation, leaving the detail screen waiting on it for the rest of the session.
5. An imported treadmill run has no route and never will, so "has no route yet" meant it re-queried Health on every single visit. Hydration is remembered instead.
6. The zone number under the bar dimmed with the wrist down — CUR-5 says it stays lit, and so did the comment above it. (Trail's climb stats moved to the secondary ink at the same time, so they no longer sit a step brighter than the numbers beside them.)
7. A swipe the scroll view took over left `isDragging` set, so the row stuck half-open and the close-all path refused to touch it.
8. The zone-2 headline divided by months that had contributed no time, and the delta was labelled with the first month of the *window* rather than the first month with a point in it.
9. A zone-update notice could be cleared before it was read, by a later refresh that found nothing to say.

#### Link to completed work

https://github.com/candyscode/Currimus/commit/24028c7

### CUR-17: Heart rate zones should match Apple Fitness

[ ] In Specification
[ ] Open
[ ] WIP
[X] Done

Ein Lauf, den Apple Fitness überwiegend als Zone 3 (Rest Zone 2, nie Zone 4) zeigt, erscheint in Currimus als Z3 und Z4. Die Pulszonen sollen 1 zu 1 wie in Apple Fitness sein.

#### Agent Comments

**What can and cannot be done today.** Apple keeps the zone configuration in Health's own store and does not publish it: until iOS 27 there is *no* API to read a person's heart-rate zones, which is a long-standing developer request. iOS 27 / watchOS 27 add exactly that — `zoneGroupsByType` on `HKWorkout`/`HKWorkoutActivity`, live zone updates, and the person's preferred zone configuration ([WWDC26 session 207](https://developer.apple.com/videos/play/wwdc2026/207/)). This app builds against the iOS 26.5 SDK, so it cannot use them yet. Worth a ticket the moment the deployment target moves — and worth weighing against CUR-11, which proposes moving the floor *down*.

Until then the two can only be brought together by matching Apple's model and its inputs, which is what this does:

- **The max heart rate was the culprit.** Currimus took the *third*-highest daily peak of the past year — very robust, and reliably a few beats under the real ceiling. A max that is low drags every boundary down with it, which is exactly the direction of the mismatch: runs landing one zone too high. It now takes the highest believable peak, as Apple does, with one guard: a day standing more than 12 bpm above the third-highest is a sensor artefact, not a runner, and is skipped.
- **Zone 1's floor** was half of *max*; Apple's model puts it at half of the heart-rate *reserve*. The four upper bounds already used the reserve ladder (60 / 70 / 80 / 90 %), so this was the one boundary out of step.
- **The zones screen says so plainly**, including that Apple does not publish its numbers and that setting the max by hand is the way to force agreement.

Expect them to line up now, or to be a beat or two apart where the underlying max differs. Exact equality needs the iOS 27 API.

#### Link to completed work

https://github.com/candyscode/Currimus/commit/2d73f16

### CUR-18: Lags in Settings and in the log's marking mode

[ ] In Specification
[ ] Open
[ ] WIP
[X] Done

Auf dem iPhone 14 Pro Max ruckelt es in den Settings und beim Markieren von Läufen. Vermutung: Arbeit auf dem UI-Thread.

#### Agent Comments

Correct on both counts, and they were two different pieces of main-thread work.

**Settings.** Every toggle wrote the settings blob synchronously: a `JSONEncoder` pass plus three `UserDefaults` writes, and then `updateApplicationContext` — a synchronous hop into another process — to push the same settings to the watch. All of it on the main thread, behind the switch the finger was still on. Both now run on the store's existing serial io queue, so the order is preserved and the widget cannot tell the difference.

**Marking mode.** The log is an eager `VStack`, so every state change rebuilds every row — and a row was expensive: two `Date.formatted` calls, three number formats, and `run.classification`, which walks the run's splits twice to get their spread. At a year of running that is roughly a thousand formatter invocations per checkbox tap. The strings a row draws are now computed once per log change and cached in the store (`RunStore.logText`), alongside the month grouping, which was also re-grouping and re-sorting the whole log on every pass.

**Not done: making the list lazy.** A `LazyVStack` is the obvious answer and it breaks the swipe — the delete tile lives in the row's background and loses its definite height under a lazy container, so the button stops being hittable. The UI test caught that within a minute of trying it. Left eager on purpose; the note is in `LogView` so the next person does not repeat it.

**Also off the main thread:** encoding a finished run for the watch→phone transfer, which ran while the watch was drawing the summary.

#### Link to completed work

https://github.com/candyscode/Currimus/commit/2d73f16

### CUR-19: Eight findings from using the app

[ ] In Specification
[ ] Open
[ ] WIP
[X] Done

Acht Punkte aus dem Praxistest (2026-07-28): 0,0-km-Läufe im Log obwohl die Watch das Gegenteil behauptet; unverständlicher Satz im Zone-2-Chart; das Herzfrequenz-Widget in Progress; wie Records einem 5K/10K zugeordnet werden; woraus sich Monthly Climb im Trail-Progress speist; Optik des Swipe-to-delete; Herkunft und Belastbarkeit der Marathon-Prognose; Abstand einer Zeile in den Settings.

#### Agent Comments

**1 · 0,00 km-Läufe wurden doch gespeichert — die Behauptung der Watch war schlicht falsch.** Der Guard stand nur an *einer* Stelle: `WatchApp.finish()` weigerte sich, den Lauf lokal abzulegen. `RunSession.end()` hat ihn aber bedingungslos ans iPhone geschickt, und `RunStore.add` hat alles genommen, was ankam. Jetzt lehnt `add` einen Lauf ohne verwertbare Distanz ab (der eine Punkt, durch den beide Wege laufen), und die Watch verschickt ihn gar nicht erst. Bereits vorhandene 0,00-km-Einträge bleiben liegen — sie lassen sich seit CUR-1 wegwischen; automatisch löschen wollte ich fremde Daten nicht.

**2 · "Older runs count whole, so the early months are approximate"** setzte voraus, dass man die Historie der App kennt. Jetzt: *"Für ältere Läufe kennt Currimus nur das Tempo des ganzen Laufs, nicht das seines lockeren Teils — diese Monate sind daher eine gute Schätzung, keine Messung."*

**3 · Das Herzfrequenz-Widget war halb kaputt.** Die 6:55 sind der Median deiner eigenen lockeren Läufe (Easy + Long), auf fünf Sekunden gerundet — das stand nirgends. Der Untertitel lautete außerdem *immer* "Same effort, less work", auch bei +2 bpm. Genau der Fall, den man wissen muss, wurde als Fortschritt verkauft. Jetzt nennt der Untertitel die Herkunft der Pace und liest die Richtung ab ("Same pace, 2 bpm higher than it used to be. Heat, fatigue or a hard block will do that."), und die Delta-Zahl ist nur noch orange, wenn sie eine Verbesserung ist.

**4 · Records.** Ein 5K/10K-Rekord ist die schnellste *zusammenhängende* Strecke dieser Länge in irgendeinem Lauf — der Lauf muss dort nicht enden. Läufe aus fremden Apps kommen ohne Kilometer-Splits, die zählen daher mit ihrer Durchschnitts-Pace über den ganzen Lauf. Dein Oktober-10K steht also da, weil seither nichts schneller *war*, nicht weil die Sommerläufe ignoriert werden. Zwei Änderungen: das Banner sagt nur noch "NEW", wenn der Rekord jünger als 60 Tage ist, sonst "YOUR BEST" (und ohne Signal-Akzent) — eine neun Monate alte Bestzeit als Neuigkeit anzukündigen war irreführend; und die Erklärung steht jetzt unter der Liste.

**5 · Monthly Climb im Trail-Progress** zählt *jeden* Höhenmeter des Monats — Trail und Straße, inklusive importierter Läufe, sofern die aufzeichnende App die Höhe mitgeschrieben hat. Die Climb-Rate darüber zählt dagegen nur Trailläufe. Der Unterschied war nicht erkennbar und steht jetzt als Zeile unter den Balken.

**6 · Swipe-Optik.** Der Eintrag schiebt jetzt bis zum Displayrand statt am 26-pt-Rand der Liste abzuschneiden (Maske statt Clip — eine Maske hat kein Mitspracherecht am Layout), und zwischen Pace und Löschen-Button liegen 14 pt. Neuer Screenshot-Schalter `-swipe 1`, weil sich ein Drag nicht in einen Screenshot injizieren lässt.

**7 · Marathon-Prognose.** Riegel: T₂ = T₁ · (D₂/D₁)^n, aus einer Benchmark hochgerechnet. Drei Schwächen, alle behoben: sie nahm den *10K zuerst* statt der nächstgelegenen Distanz unter dem Rennen (ein Halbmarathon sagt über einen Marathon weit mehr aus); sie nahm die absolute Bestzeit, auch wenn die ein Jahr alt war; und sie nutzte n = 1,06 auch über die Marathondistanz, wo das notorisch zu optimistisch ist — die letzten zehn Kilometer sind kein Skalierungs-, sondern ein Verpflegungsproblem. Jetzt: nächstgelegene Benchmark, bevorzugt aus den letzten 120 Tagen, n = 1,08 beim Sprung von ≤ 12 km auf > 30 km. Der Text unter der Zahl nennt jetzt die Grundlage *mit Datum* und sagt es ausdrücklich, wenn nichts Aktuelles vorlag. Belastbar ist sie damit als grobe Standortbestimmung — mehr kann eine Formel ohne Langlauf-Umfang, Hitze und Verpflegung nicht leisten, und genau das steht jetzt dort.

**8 · Settings-Abstand.** `ChevronRow` hatte nur `minHeight: 56` und kein vertikales Padding: kurze Zeilen wirkten dadurch gepolstert, eine Zeile mit umbrechendem Untertitel klebte an der Trennlinie. Jetzt 10 pt Padding *und* die Mindesthöhe — kurze Zeilen sehen aus wie vorher, lange bekommen denselben Abstand.

#### Link to completed work

https://github.com/candyscode/Currimus/commit/fbfd965

### CUR-20: Audit aller Texte, die dem Nutzer etwas behaupten

[ ] In Specification
[ ] Open
[ ] WIP
[X] Done

Alle Texte in iOS-App und Watch-App daraufhin prüfen, ob sie für *jeden* Wert stimmen, den das zugehörige Feld annehmen kann — besonders dort, wo ein Satz unter einer Zahl steht und diese Zahl deutet.

#### Agent Comments

Neun Befunde, alle bestätigt und behoben. Das Muster ist fast überall dasselbe: der Text beschreibt den *erwarteten* Wert, nicht den möglichen.

| # | Wo | Was behauptet wurde | Wann es falsch war |
|---|---|---|---|
| 1 | Home (letzter Lauf), Log-Zeile | `MOSTLY Z0` / `… · Z0` | Immer, wenn ein Lauf keine Herzfrequenz hat. Zone 0 gibt es nicht (dein eigener Hinweis aus CUR-6) — die Watch zeigte hier längst „–", das iPhone nicht. |
| 2 | Watch, Pacer | `PACER · ON TARGET 5:15` | Sobald keine laufende Pace vorliegt: beim Start vor dem ersten GPS-Fix und an jeder Ampel. `paceDelta` ist dann 0, und 0 hieß „genau im Ziel". Die Hero-Zahl darüber zeigte gleichzeitig `–:––`. |
| 3 | Race, „LAST 4 WEEKS" | z. B. `284 km · +118 %` | Immer bei importierten Läufen: der aktuelle Wert zählte *alle* Läufe, der Vergleichswert nur die von Currimus selbst aufgezeichneten. Zwei verschiedene Grundgesamtheiten. Zusätzlich war die Zahl immer orange — ein Volumenrückgang las sich als Erfolg. |
| 4 | Race Setup | „so the goal sits inside what you have already held" | Beim Marathon: verglichen wurde die nötige Renn-Pace mit der besten *Tempo*-Einheit, meist 5–12 km. 5:00/km über 8 km sagt fast nichts über 42 km. |
| 5 | Settings, Progress, Records, Race Setup | `1 runs read`, `1 runs · 9 km in zone 2`, `race day in 1 days` | Bei genau eins. Es gab keine Pluralbehandlung. |
| 6 | Settings, Zeile „Target race" | `Marathon · -3 days` | Nach dem Renntag. |
| 7 | Run Detail (Trail-Hero) | `0 m climb`, `0 CLIMB M/H` | Bei importierten Läufen ohne Höhendaten: eine fehlende Messung wurde als gemessene Null dargestellt. |
| 8 | Progress, Trend-Delta | `+0:00 since May`, in Signal-Orange | Bei exakt null Veränderung — als Verbesserung markiert. |
| 9 | Records | `race day in 0 days` | Am Renntag selbst. |

Behoben, und zwar an der Wurzel statt im Text: eine fehlende Messung wird jetzt als fehlend dargestellt (`–`), nicht als Null; `Format.plural` erledigt die Ein-/Mehrzahl an einer Stelle; der Pacer kennt einen Zustand „noch keine Pace" und behauptet dort nichts; der Vier-Wochen-Vergleich rechnet auf beiden Seiten mit denselben Läufen; und Signal-Orange markiert weiterhin ausschließlich eine Verbesserung.

Nicht geändert, aber geprüft und für richtig befunden: `–:––` bei fehlender Pace, die leeren Zustände der Records („no 10 km effort yet"), die Erklärungen der Pulszonen-Herleitung, die Recording-Issue-Texte auf der Watch, sowie die Zonen-Warnung und die Vibrationsbeschreibungen aus CUR-6.

#### Link to completed work

https://github.com/candyscode/Currimus/commit/154cfc6

\n\n### CUR-21: Zone-2-Pace nur noch gemessen, nie geschätzt

[ ] In Specification
[ ] Open
[ ] WIP
[X] Done

Rückfrage von Andi zu CUR-7: Ist es eine gute Idee, angenäherte Werte im Zone-2-Graphen zu zeigen, wenn wir nur die Pace des ganzen Laufs kennen? Vorschlag: solche Läufe gar nicht betrachten.

#### Agent Comments

Zugestimmt — mit einem Zwischenschritt, weil „nur exakte Werte" allein den Graphen bei Andi auf Monate hinaus leer gelassen hätte: `zoneDistanceKm` gab es nur auf Läufen, die Currimus selbst aufgezeichnet hat, und sein Log besteht überwiegend aus Läufen der Apple-Workout-App.

**Also erst messen, dann die Näherung streichen.** Seit CUR-15 holt die App für importierte Läufe die GPS-Route *mit Zeitstempeln* und die vollständige Herzfrequenzspur aus Health. Beides wurde über denselben Lauf aufgezeichnet — man kann sie also wieder zusammenführen und Segment für Segment ausrechnen, wie viel Strecke bei welcher Herzfrequenz zurückgelegt wurde. Das ist dieselbe Rechnung, die die Uhr live macht, nur nachträglich (`RunAnalytics.zoneDistanceKm(route:heartRate:zones:)`, rein und getestet).

Aus derselben Route fallen außerdem **echte Kilometer-Splits** ab (`RunAnalytics.splits(fromRoute:)`) — siehe unten, das repariert nebenbei die Records importierter Läufe.

**Die Regel lautet jetzt: gemessen oder gar nicht.** `RunAnalytics.effort` akzeptiert ausschließlich Läufe mit gemessener Zonen-Distanz. Was nicht messbar ist — Laufband ohne Route, Lauf ohne Herzfrequenz — fällt raus und wird unter dem Graphen gezählt: *„3 runs spent in zone 2 could not be measured exactly — no route or no heart-rate trace — and are left out rather than estimated."* Läufe verschwinden damit nicht stillschweigend.

**Nachladen im Hintergrund** (`RunStore.backfillImported`): bei jedem Refresh werden bis zu zwölf importierte Läufe der letzten zwölf Monate rekonstruiert, neueste zuerst, und dauerhaft gespeichert. Ohne das hätte sich der Graph nur gefüllt, wenn man zufällig alte Detailansichten öffnet — ein Diagramm, das seine Form ändert, weil man woanders hingeschaut hat.

**Grenzen, ehrlich benannt:** Segmente über 60 s Lücke (Pause, GPS-Ausfall) und Sprünge über 500 m zählen nicht mit; ein Herzfrequenzwert gilt höchstens 60 s weit. Läufe, die Currimus vor CUR-7 selbst aufgezeichnet hat, haben keine gespeicherte Herzfrequenzspur — sie liegen aber als Workouts in Health und werden über denselben Weg erfasst, sobald sie an der Reihe sind.

#### Link to completed work

https://github.com/candyscode/Currimus/commit/934d291

\n\n### CUR-22: Marathon-Prognose aus dem Training, nicht nur aus einer Bestzeit

[ ] In Specification
[ ] Open
[ ] WIP
[X] Done

Riegel schaut nur auf eine Bestzeit — also auf Geschwindigkeit, nicht auf Training. Für den Marathon fehlt damit die Hälfte. Zweites Modell ergänzen und beide zeigen.

#### Agent Comments

**Zwei Zeugen, bewusst nicht verrechnet.** Riegel liest eine harte Einheit und weiß nichts darüber, ob die Arbeit gemacht wurde; [Tanda (2011)](https://pubmed.ncbi.nlm.nih.gov/21957197/) liest die Arbeit — mittlere Wochenkilometer und mittlere Trainings-Pace der letzten acht Wochen — und nichts über Renn-Schärfe. Wo sie auseinanderliegen, *ist* das die Information; ein Mittelwert hätte sie weggeworfen.

- **Race-Screen:** beide Zahlen im Fließtext, jede mit ihrer Quelle verlinkt, plus eine Zeile, was die Lücke bedeutet („Deine Geschwindigkeit ist deinem Training voraus: das sind lange Läufe und Wochenumfang" bzw. umgekehrt). Erst ab acht Minuten Unterschied, darunter ist es Rauschen.
- **Kachel und Home:** die **langsamere** der beiden, Label `PREDICTED · CAUTIOUS`. Eine zu optimistische Prognose kostet am Renntag mehr als eine zu vorsichtige.
- **Nur Marathon.** Tanda ist auf die Distanz gefittet und wird für 5K/10K/Halb gar nicht erst gefragt.
- **Straßenläufe only** für beide Eingangsgrößen: der Pace-Term trägt über die Hälfte der Prognose, ein Bergtag bei 7:30/km würde sie um Minuten verschieben.
- **Grenze sichtbar:** die Studie umfasst 22 Läufer mit Zielzeiten von 2:47 bis 3:36. Liegen Umfang oder Pace außerhalb, sagt der Text das ausdrücklich („read it as a direction rather than a time") statt still eine Zahl auszuwerfen.

### CUR-23: Kadenz-Hinweis gegen die eigene Normalität, nicht nur gegen eine Tabelle

[ ] In Specification
[ ] Open
[ ] WIP
[X] Done

Der Hinweis aus CUR-8 misst gegen eine pace-abhängige Schwelle. Die kennt die Beinlänge des Läufers nicht — und wiederholt sich bei jedem Lauf.

#### Agent Comments

Ein Hinweis sollte zwei verschiedene Dinge sagen, also sind es jetzt zwei:

- **„Try shorter, quicker steps"** — die Schwelle aus CUR-8, medizinisch begründet ([Heiderscheit et al. 2011](https://pmc.ncbi.nlm.nih.gov/articles/PMC3022995/), jetzt verlinkt). Neu: erscheint **nur auf dem jüngsten Lauf, der ihn auslöst**. Das ist ein Trainingsprojekt, kein Tagesbefund — auf jedem Lauf wiederholt wird daraus Nörgeln. Kostet keinen gespeicherten Zustand: ob es einen neueren qualifizierenden Lauf gibt, beantwortet das Log selbst.
- **„Shorter steps than usual"** — neu, gegen den **eigenen** Median bei vergleichbarer Pace (±20 s/km, letzte 180 Tage, mindestens acht solche Läufe). Fängt Ermüdung, neue Schuhe, müde Beine. Schweigt bei jemandem, dessen 158 einfach seine 158 sind.

Bewusst **nicht** mit „muss beides zutreffen" verknüpft: wer dauerhaft überschreitet, liegt auch bei seinem eigenen Median niedrig — dann fiele ausgerechnet der Fall mit dem echten gesundheitlichen Nutzen weg. Beide feuern unabhängig und sagen Unterschiedliches.

`RunHints.all(for:in:)` bekommt jetzt das Log mit — das brauchen die AI-Hinweise aus CUR-8 später ohnehin.

### CUR-24: Jede geschätzte Zahl nennt ihre Grundlage

[ ] In Specification
[ ] Open
[ ] WIP
[X] Done

Überall, wo Modelle oder Schätzungen benutzt werden, dem Nutzer erklären, worauf das beruht — nicht die Formel, sondern „nach Tanda (2011)" mit Link zur Studie.

#### Agent Comments

`Shared/Sources.swift` hält die Quellen an einer Stelle (Titel, Jahr, URL, und wofür sie benutzt werden). `Explainer` rendert Markdown, weil SwiftUI Markdown nur in literalen Texten parst, nicht in interpolierten Strings — und genau so werden diese Absätze zusammengesetzt.

Verlinkt und benannt:

- **Race-Prognose** → Riegel (1981) und Tanda (2011).
- **Maximalpuls aus dem Alter** → Tanaka et al. (2001). Die Formel selbst steht nicht mehr da.
- **Kadenz-Hinweis** → Heiderscheit et al. (2011).
- **Acknowledgements** bekommt einen Abschnitt „RESEARCH" mit allen vieren und je einer Zeile, wofür sie benutzt werden.

**Nachtrag (Andi): auch die grade-adjusted pace gehört auf eine wissenschaftliche Basis, und wo es keine gibt, muss die Rechnung erklärt werden.**

Es gibt eine, und zwar die kanonische: [Minetti et al. (2002)](https://journals.physiology.org/doi/full/10.1152/japplphysiol.01177.2001) haben zehn Läufer von −45 % bis +45 % Steigung auf dem Laufband vermessen und den Energieverbrauch pro Meter bestimmt. Genau darauf beruht auch Stravas GAP. Currimus rechnet jetzt damit: jedes Streckenstück wird über seine tatsächliche Steigung in die Flachdistanz umgerechnet, die denselben Energieaufwand gekostet hätte, und die Laufzeit verteilt sich darüber.

- Die Steigung wird über mindestens 20 m Strecke gebildet — bei einem Fix alle paar Meter und einem Meter Höhenrauschen entstünden sonst Rampen, die es nie gab.
- Außerhalb von ±45 % wird das Polynom gekappt: dort ist es Extrapolation, nicht Messung.
- Der Wert wird **einmal berechnet und gespeichert** (auf der Uhr am Laufende, für alles andere beim Rebuild aus Health), weil das Log selbst keine Route trägt.
- **Wo keine Route existiert**, bleibt die alte Faustregel (≈0,4 s pro Höhenmeter, knapp die Hälfte zurück beim Abstieg) — und der Text sagt dann genau das, samt Hinweis auf den Rebuild-Button. Eine erfundene Zitation wäre schlimmer als keine.

#### Link to completed work

https://github.com/candyscode/Currimus/commit/ba5debb

\n\n### CUR-25: Ein Rennen, das vorbei ist

[ ] In Specification
[ ] Open
[ ] WIP
[X] Done

Rückfrage von Andi: Was passiert, wenn der Marathon gestern war? Gibt es dafür ein sinnvolles Handling?

#### Agent Comments

Nein, gab es nicht — an drei Stellen:

- **Home ließ das Rennen verschwinden.** Der Block prüfte `!race.isPast`, und der Ersatz-Hinweis („Training toward a race? Set it up") erschien nur, wenn *gar kein* Rennen gesetzt war. Nach dem Renntag blieb also nur der Wochenblock: kein Ergebnis, kein Weg zurück zum Race-Screen, kein Angebot für das nächste.
- **Der Race-Screen zählte durch die Null hindurch** — „-3" in 136 pt, daneben „DAYS".
- **Prognose und Required Pace liefen weiter**, als stünde das Rennen noch bevor.

Jetzt: der Countdown zählt nach dem Renntag andersherum („3 DAYS AGO"), die Prognose fällt weg, und an ihrer Stelle steht, **was tatsächlich passiert ist**. Currimus sucht dazu einen Lauf am Renntag über mindestens 95 % der Distanz — niemand öffnet mitten im Rennen eine App, um ein Häkchen zu setzen, und ein Marathon im Log am Marathontag ist kein Zufall. Der Text darunter stellt Zeit und Ziel gegenüber („42,4 km in **3:52:41**, 6:19 inside your goal of 3:59:00") oder sagt ehrlich, dass kein passender Lauf da ist. Home zeigt eine ruhige Zeile „Freiburg Marathon · 3 days ago", die dorthin führt.

### CUR-26: Laufband-Läufe aus Apple Health

[ ] In Specification
[ ] Open
[ ] WIP
[X] Done

Rückfrage von Andi: Wie behandeln wir Indoor-Läufe aus Apple Health?

#### Agent Comments

Sie wurden importiert und in alle Summen gezählt — aber alles, was an der GPS-Route hängt, fiel für sie aus: **keine Zone-2-Pace** (seit CUR-21 fallen sie damit ganz aus dem Graphen), **keine Splits** (und damit praktisch keine Chance auf einen 5K/10K-Rekord, weil nur die Durchschnitts-Pace des ganzen Laufs blieb), keine Steigungskorrektur. Und nirgends stand, dass es an der Halle lag: die Karte sagte „No GPS track for this run", was wie ein Fehler aussieht statt wie eine Tatsache.

Beides behoben:

- **Die Rekonstruktion braucht keine Route mehr.** Sie lief bisher über den GPS-Track; jetzt läuft sie über „zurückgelegte Distanz zum Zeitpunkt t" — und die schreibt die Uhr auch auf dem Laufband, als `distanceWalkingRunning`-Samples. Damit bekommen Indoor-Läufe Zone-2-Distanz *und* Kilometer-Splits wie jeder andere Lauf. Dieselbe Rechnung, nur eine andere Quelle für dieselbe Kurve.
- **Der Indoor-Marker aus Health** (`HKMetadataKeyIndoorWorkout`) wird gelesen und angezeigt: die Karte sagt jetzt „Indoor run — nowhere to draw" mit Laufband-Symbol.

**Nachtrag (Andi): stehen sie denn im Log?** Ja — unter *All* und unter *Road* (das heißt technisch „nicht Trail"), und sie zählen in jede Summe, jedes Wochenziel und jeden Pace-Schnitt. Nur ansehen konnte man es der Zeile nicht: gleiche Darstellung wie ein Lauf draußen, obwohl Route, Höhenmeter und die Art, wie die Distanz zustande kam, sich unterscheiden. Sie tragen jetzt ein `INDOOR`-Kürzel neben der Distanz — in gedämpftem Grau, nicht in Signal-Orange, weil es eine Tatsache ist und keine Auszeichnung. Ein Lauf pro Monat in den Demodaten ist jetzt ein Laufband-Lauf, damit Kürzel, leere Karte und die Rekonstruktion aus Distanz-Samples überhaupt sichtbar sind.

Was Indoor-Läufe weiterhin nicht bekommen: eine Steigungskorrektur. Ohne Höhenprofil gibt es keine Steigung, und für ein flaches Laufband ist die angepasste Pace die Pace — die Steigungsfunktion mancher Bänder schreibt Health nichts Verwertbares.

#### Link to completed work

https://github.com/candyscode/Currimus/commit/66b1d82

\n\n### CUR-27: Review der Commits seit dem letzten Review

[ ] In Specification
[ ] Open
[ ] WIP
[X] Done

Review aller Commits seit dem letzten Code-Review in dieser Session (24 Commits, CUR-15 bis CUR-26).

#### Agent Comments

Vier Funde, alle bestätigt und behoben. Zwei davon sind derselbe Fehlertyp wie Befund 1 des letzten Reviews — der Refresh ersetzt die importierte Liste vollständig, und alles, was nur dort lebt, ist einen Vordergrund vom Verschwinden entfernt.

1. **Die Steigungskorrektur überlebte keinen Refresh.** `carryingHydratedZones` trug Zonen, Zonen-Distanz und Splits über die Aktualisierung, aber nicht `gradeAdjustedSecPerKm`. Die aus Health rekonstruierte Minetti-Pace war beim nächsten Wechsel in den Vordergrund wieder weg, und der Trail-Progress fiel auf die Faustregel zurück. Jetzt mit Test, der *alle* rekonstruierten Felder prüft statt nur das, an das ich gerade dachte.

2. **Der Rebuild-Button versprach etwas, das er nicht halten konnte.** `hydratedImported` wurde erst *nach* einer erfolgreichen Antwort gesetzt. Ein Lauf, dessen Workout nicht mehr in Health liegt, kam also nie aus der Zählung heraus: die Zeile bot ewig „3 runs" an, und jeder Start fragte dieselben toten Läufe erneut ab. Genau die Behauptung, die in CUR-21 als erledigt notiert war — dort jetzt korrigiert.

3. **Hintergrund-Nachladen und Settings-Zeile waren sich uneinig.** Das Nachladen suchte nur nach fehlender Zonen-Distanz, die Zeile auch nach fehlender Steigungskorrektur. Die Zahl konnte damit durch Hintergrundarbeit allein nie auf null gehen. Beide lesen jetzt dieselbe Liste.

4. **`store.prediction` war ungecacht** — und seit CUR-21 deutlich teurer, weil importierte Läufe jetzt Splits haben: die Prognose sucht die beste Leistung über drei Distanzen, zweimal (aktuelles Fenster und gesamtes Log), und liest dabei jeden Split jedes Laufs. Home las das bei *jedem* Body-Pass. Jetzt gecacht wie jede andere Aggregation, invalidiert mit dem Log. Das ist derselbe Fehlertyp wie die Lags aus CUR-18, nur an einer neuen Stelle.

Geprüft und in Ordnung: die `distanceTrace`-Umstellung verhält sich identisch zur Routen-Variante (die bestehenden Tests decken beide Wege ab), die Behandlung des vergangenen Rennens auf allen drei Screens, die Reihenfolge der Rebuild-Tasks bei Abbruch, und dass `Explainer` nur auf Screens liegt, die nicht in der Scroll-Hot-Path sind.

**Nachtrag: `/code-review` über genau diesen Commit — fünf weitere Funde, alle bestätigt.** Ich hatte diese Änderungen selbst reviewt und die Hälfte davon übersehen.

1. **Das Hintergrund-Nachladen verhungerte an Laufband-Läufen.** Ich hatte es auf dieselbe Liste umgestellt wie die Settings-Zeile — die zählt aber auch fehlende Steigungskorrektur, und ein Indoor-Lauf bekommt die *nie* (keine Route, keine Steigung). Da die Liste nach Datum sortiert und auf zwölf begrenzt ist, hätten ein paar aktuelle Laufband-Läufe das Budget jedes Starts vollständig aufgebraucht — und die importierten Läufe, für die das Nachladen existiert, wären nie drangekommen. `needsRebuild` weiß jetzt, was ein Lauf überhaupt gewinnen kann.
2. **Und es lief plötzlich auch über die eigenen Läufe**, obwohl es „Imported" heißt: zwei bis drei Health-Abfragen pro Lauf bei jedem Vordergrundwechsel, für etwas, das niemand angefordert hatte. Wieder auf importierte Läufe begrenzt; der manuelle Rebuild deckt weiterhin alles ab.
3. **„Health hat das nicht" und „Health kann gerade nicht antworten" waren dasselbe.** Bei gesperrtem Gerät liefert HealthKit nichts zurück — mein Fix aus CUR-27 hätte dann bis zu zwölf Läufe als erledigt markiert, und die Settings-Zeile hätte „All done" gemeldet, ohne dass irgendetwas rekonstruiert wurde. Die Abfrage unterscheidet jetzt beides (Fehler → kein endgültiges Urteil).
4. **Die gecachte Prognose fror `isPast` ein.** Der Cache hängt am Log, die Frage „ist das Rennen vorbei" aber an der Uhr: mit offener App über Mitternacht hätte der Screen weiter eine Prognose für ein bereits gelaufenes Rennen gezeigt. Die Prüfung liegt jetzt vor dem Cache.
5. Kleinigkeiten: ein abgebrochener Rebuild konnte noch einen Fortschrittsstand über den neuen schreiben, und die beiden Mengen, die den Zähler speisen, waren nicht published — die Settings-Zeile konnte veralten, während man sie ansieht.

#### Link to completed work

https://github.com/candyscode/Currimus/commit/7910676

