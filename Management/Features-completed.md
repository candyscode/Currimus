# Currimus Features & Changes — completed

Tickets that are Done, in numeric order. They are moved here from
[Features.md](Features.md) the moment they are finished, so that file only ever
carries what is still ahead: In Specification, Open and WIP.

Nothing here is history for its own sake — the agent comments record *why* a
thing was built the way it was, and the reviews record what Andi thought of it.
Read the relevant one before you change the same area again.

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


### CUR-21: Zone-2-Pace nur noch gemessen, nie geschätzt

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


### CUR-22: Marathon-Prognose aus dem Training, nicht nur aus einer Bestzeit

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


### CUR-25: Ein Rennen, das vorbei ist

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


### CUR-27: Review der Commits seit dem letzten Review

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

**Zweiter Nachtrag: `/code-review` über den Fix-Commit — sieben weitere Funde.** Der erste davon traf wieder exakt die Stelle, die ich als repariert gemeldet hatte.

1. **Die Trennung „Health hat nichts" / „Health kann nicht" hatte ich nur an einer von zwei Abfragen angebracht.** Die zweite (das Zeitfenster-Match für eigene Läufe) verschluckte ihren Fehler weiter — ein Rebuild, währenddessen sich das Telefon sperrt, hätte jeden verbleibenden eigenen Lauf als endgültig markiert und „All done" gemeldet. Also genau der Fehler, den der Commit zu beheben behauptete.
2. **Ein Lauf mit Route, aber ohne Herzfrequenzspur** (mit Strava ohne Gurt aufgezeichnet) kam nie aus der Warteschlange: Health antwortet vollständig, es gibt trotzdem keine Zonen-Distanz, und markiert wurde nichts. Jetzt gilt: wenn eine *vollständige* Antwort den Lauf immer noch unvollständig lässt, kann kein späterer Rebuild mehr helfen — er wird endgültig markiert.
3. **Das Nachladen wählte nach der einen Regel aus und die Hydrierung lehnte nach einer anderen ab** — die ausgewählten Läufe taten nichts, wurden nicht als versucht vermerkt und wurden beim nächsten Vordergrundwechsel erneut gewählt. Wieder Aushungern, nur an anderer Stelle. Jetzt eine Regel für beide.
4. **Eine Abfrage, die gar nicht laufen konnte, zählte als Versuch.** Erster Start nach einem Neustart vor dem Entsperren: zwölf Läufe als versucht markiert, und bis zum nächsten App-Start versucht es nichts erneut.
5. Punkt 2 deckt auch ab, was ich mit der Laufband-Ausnahme nur für Indoor-Läufe gelöst hatte — jeder Lauf ohne Route ist betroffen, nicht nur der auf dem Band.
6. `attemptedThisSession` als `@Published` brachte für den Zähler nichts und löste pro nachgeladenem Lauf ein Neuzeichnen aller beobachtenden Views aus.
7. Der Prognose-Cache fror weiterhin die Uhr ein — nicht mehr bei `isPast`, aber beim 120-Tage-Fenster. Er ist jetzt an den Kalendertag gebunden.

#### Link to completed work

https://github.com/candyscode/Currimus/commit/7910676


### CUR-28: Den Rekonstruktions-Zustand auf einen Typ zusammenziehen

[ ] In Specification
[ ] Open
[ ] WIP
[X] Done

Vier Fehler in drei Tagen im selben Pfad, jeder mit derselben Form: eine Bedingung liegt an zwei Stellen, und ich ändere eine. Ursache angehen statt weiter Symptome.

#### Agent Comments

Die Fehlerliste, bevor etwas geändert wurde — sie ist die Begründung:

| | Was | Weil |
|---|---|---|
| CUR-16 #1 | Der Refresh warf die geholten Zonen weg | `carryingHydratedZones` kannte `zoneSeconds` nicht |
| CUR-27 #1 | Der Refresh warf die Steigungskorrektur weg | dieselbe Funktion, neues Feld, wieder vergessen |
| CUR-27#2 #1 | Das Nachladen verhungerte an Laufband-Läufen | Auswahl-Prädikat und „was kann ein Lauf gewinnen" waren dasselbe Prädikat für zwei Fragen |
| CUR-27#3 #3 | Auswahl und Hydrierung waren sich uneinig | zwei Regeln für „soll ich fragen" |

Zwei Ursachen, zwei Zusammenführungen:

**1 · `Reconstruction`** — alles, was Health an einen Lauf zurückgeben kann und die Workout-Zusammenfassung nicht trägt: Zonensekunden, Zonen-Distanz, Splits, Steigungskorrektur, Route. Ein neues Feld war bisher **fünf** Änderungen (Sidecar, dessen Initialisierer, das Zurückschreiben nach dem Abruf, das Zusammenführen auf den Lauf, das Übertragen über den Refresh) — und beim fünften ging es zweimal schief. Jetzt ist es eine. `applied(to:)` ist die einzige Stelle, die diese Felder auf einen Lauf schreibt, und sie überschreibt nie, was der Lauf selbst gemessen hat.

Das Dateiformat der Sidecar-Dateien bleibt unverändert (eigene `Codable`-Zuordnung auf die bisherigen flachen Schlüssel), damit bestehende Installationen nichts neu holen müssen.

**2 · `HealthRebuild`** — die Buchführung: wer wurde schon gefragt, wer ist endgültig erledigt, was steht noch aus. Vorher drei Prädikate und zwei Mengen verstreut über den Store, jedes von zwei bis drei Aufrufern unterschiedlich benutzt. Jetzt beantwortet ein Typ alle drei Fragen — „kann Health hier noch etwas beitragen", „soll ich jetzt fragen", „wie viele sind offen" —, und die Antworten können nicht mehr auseinanderlaufen.

Verhalten unverändert: alle bestehenden Tests laufen ohne Anpassung durch, inklusive der Fälle aus den vier Reviews.

**Nachtrag — Review des Umbaus selbst.** Vier Funde, alle behoben:

1. **Der Rebuild hat die Höhenkurve gelöscht.** Die Sidecar-Datei trägt auch die Höhenmessreihe; ich habe sie nach einem Abruf komplett neu geschrieben statt zusammengeführt — bei einem selbst aufgezeichneten Lauf wäre das Höhenprofil im Detail dauerhaft verschwunden. Es gibt jetzt `filling(from:)`: ein Rebuild fügt nur hinzu, er überschreibt nie. Damit ist auch der Fall abgedeckt, dass ein Abruf unvollständig zurückkommt (gesperrtes Gerät) und ein früher schon geholtes Feld wegnehmen würde.
2. **`@Published` auf der Warteschlange hat den Re-Render-Sturm zurückgebracht.** Beim Zusammenlegen der beiden Mengen ist eine bewusste Trennung verlorengegangen: „schon gefragt" läuft einmal pro Lauf, ein Nachladen von zwölf hätte jede beobachtende View zwölfmal neu gezeichnet. Nur das endgültige Erledigen bewegt die Zahl in den Settings, und nur das meldet sich jetzt.
3. **Die App-Version ist von 1.1 auf 1.0 zurückgefallen.** Der Bump stand nur in der generierten `.xcodeproj`, und mein `xcodegen generate` hat ihn weggeräumt — das nächste Archiv wäre als 1.0 hochgeladen und von App Store Connect abgelehnt worden. Steht jetzt in `project.yml` mit einem Kommentar, warum dort und nicht dort.
4. **`canGain` hieß an zwei von drei Aufrufstellen das Gegenteil.** Vor einem Abruf heißt das Prädikat „lohnt zu fragen", nach einem „Health hatte nichts, nicht mehr anbieten". Jetzt `isStillShort` — benannt nach dem, was es misst, nicht nach dem, was ein Aufrufer daraus schließt.

#### Link to completed work

https://github.com/candyscode/Currimus/commit/a03dfb0


### CUR-29: Was der Store beim Neustart verliert

[ ] In Specification
[ ] Open
[ ] WIP
[X] Done

Aus dem Audit vom 30.07.2026 (Andi: „Erstelle eine Einschätzung der App"). Die zwei Befunde, die einen Release verhindern — beide durch temporäre Probe-Tests bewiesen, beide an derselben Naht: `RunStore.loadSettings()` liest weniger zurück, als `persistSettings()` geschrieben hat.

1. **`HRZones.derivation` wird nirgends persistiert.** `WatchSettings` trägt nur `maxHR`, `zoneBounds`, `restingHR`. Folgen, alle drei bestätigt:
   - `isAutomatic` ist nach jedem Start wieder `true`, der Auto-Refresh überschreibt also eine handgesetzte maximale Herzfrequenz. Genau die Regression, die CUR-2 zu beheben beanspruchte — und der Settings-Text behauptet wörtlich das Gegenteil.
   - `HRZonesView.setMax` benutzt `z.derivation.map { … }`: ist `derivation` nil, bleibt die Manuell-Markierung ganz aus. Der Fehler greift damit auch innerhalb einer Session.
   - Der Zonen-Änderungs-Hinweis aus CUR-2 kann nie erscheinen, weil sein Guard `zones.derivation != nil` lautet. Totes Feature.
2. **`restingHR` wird nicht zurückgelesen**, obwohl es gesendet und geschrieben wird. Die Zonen fallen nach jedem Start von Karvonen auf %-von-Max zurück, bis Health wieder antwortet — und wenn Health nichts hat, dauerhaft.
3. **`alwaysOnReduced` wird nicht zurückgelesen.** Wer das Dimmen ausschaltet, hat es beim nächsten Start wieder an.

Akzeptanz: ein Test, der in einen Store schreibt, einen zweiten auf dieselben Defaults legt und prüft, was ankommt. Diese eine Sorte Test fehlt vollständig und hätte alle drei gefunden.

#### Agent Comments

Eine Ursache, drei Symptome: `WatchSettings` **ist** der persistierte Einstellungsblob, und es fehlte ein Feld. `derivation` ist jetzt darin — optional wie jedes später hinzugefügte Feld, damit eine ältere Watch-Version den Payload weiter lesen kann.

- `loadSettings()` liest jetzt jedes Feld zurück, das `watchSettings` schreibt: `restingHR`, `derivation` und `alwaysOnReduced` fehlten. Die Zonen kommen damit als vollständige `HRZones` zurück statt als `HRZones(maxHR:overrides:)`.
- `apply(_:)` auf der Uhr übernimmt die Herleitung mit. Das ist nicht nur Symmetrie: die Uhr ruft dasselbe `refreshImportedRuns → refreshHeartRateZones` auf und hätte sonst ihrerseits ein handgesetztes Maximum überschrieben.
- `HRZonesView.setMax` schreibt die Manuell-Markierung jetzt unbedingt statt per `map` auf eine bestehende Herleitung. War die nil — was nach jedem Start der Fall war und auf einem Gerät ohne Health-Daten dauerhaft bleibt —, entstand keine Markierung, und `isAutomatic` blieb `true`. Die Markierung ist genau das, was überleben muss; sie kann nicht davon abhängen, dass schon etwas anderes da ist.

**Vier neue Tests, und sie sind der eigentliche Ertrag.** Die Suite hatte diese Form nicht: `testSettingsSurviveAWatchSettingsRoundTrip` prüft `JSONEncoder → WatchSettings → JSONDecoder`, also die Codable-Konformität der Struct — nicht, was der Store schreibt und zurückliest. Die neuen Fälle gehen durch die Platte und einen zweiten Store:

| Test | hätte gefunden |
|---|---|
| `testEverySettingSurvivesARelaunch` | `alwaysOnReduced` |
| `testAHandSetMaxHeartRateStaysProtectedAcrossARelaunch` | die überschriebene Handeinstellung |
| `testTheRestingPulseAndItsZonesSurviveARelaunch` | Karvonen → %-von-Max, inklusive der verschobenen Grenzen |
| `testAReloadedStoreKnowsItsZonesWereAlreadyDerived` | den unerreichbaren Zonen-Hinweis |

187 Tests grün (vorher 183), beide Ziele bauen.

#### Link to completed work

https://github.com/candyscode/Currimus/commit/dce8506


### CUR-30: Der Zonen-Coach feuert bei flatternder Herzfrequenz neu

[ ] In Specification
[ ] Open
[ ] WIP
[X] Done

Aus dem Audit vom 30.07.2026. `ZoneCoach.update` setzt `lastFired = nil`, sobald der Cue kurz `nil` wird. Pendelt der Puls um eine Zonengrenze — was er ständig tut —, gilt der Cue bei der Rückkehr als „neu" und feuert sofort: der `leftZone`-Alarm bringt 3 Sekunden Dauervibration plus Vollbildwarnung alle zwei Sekunden statt der beabsichtigten 60-Sekunden-Kadenz. Per Test bewiesen.

Das ist der Fehler, an dem Nutzer ein Vibrationsfeature dauerhaft abschalten.

#### Agent Comments

Der Zustand war „welcher Cue galt zuletzt" — und der wurde weggeworfen, sobald keiner galt. Er ist jetzt „welcher Cue **wurde zuletzt gespielt**, und wann", und der überlebt eine Pause. Damit ist ein Cue, der einen Tick aussetzt und wiederkommt, derselbe Cue und nicht news.

Zwei Fälle brauchten eine Unterscheidung, sonst wäre es entweder weiterhin zu laut oder plötzlich zu stumm:

- **Ein anderer Cue-Typ unterbricht weiter sofort.** Vom Zonenboden geradewegs durch die Decke zu korrigieren muss jetzt gesagt werden, nicht in vier Sekunden.
- **Zwei `leftZone`-Alarme sind derselbe Typ**, und dort ist die Frage, ob es *schlimmer* wurde. Von Zone 3 auf 4 bei Ziel 2 ist eine neue Tatsache; von 4 zurück auf 3 ist derselbe Alarm aus etwas geringerer Entfernung und wartet seine Minute ab. Ohne das hätte ein Puls, der auf der 3/4-Grenze sitzt, jeden zweiten Tick alarmiert — ein zweiter Flatter-Pfad, der im ursprünglichen Befund noch nicht drin war und beim Umbau aufgefallen ist.

**Ein bestehender Test hat die falsche Entscheidung festgehalten** und wurde ersetzt: `testReturningToTheMiddleClearsTheCadence` behauptete „drifting low again is news, whatever the clock says". Genau dieses „whatever the clock says" *war* der Fehler — ein Puls sitzt nicht still auf der 15-%-Linie, er flattert darüber. Der Nachfolger `testACueThatLapsedForATickDoesNotStartOver` prüft beides: Flattern schweigt, und nach der eigenen Kadenz spricht es wieder. Dazu kommt `testDriftingLowAgainMuchLaterStillSpeaks`, damit die Gegenrichtung nicht still verlorengeht.

Drei neue Fälle für die beiden Flatter-Pfade. 190 Tests grün (vorher 187).

#### Link to completed work

https://github.com/candyscode/Currimus/commit/57906b3


### CUR-31: Der Demo-Pfad liest die echten Einstellungen

[ ] In Specification
[ ] Open
[ ] WIP
[X] Done

Aus dem Audit vom 30.07.2026. `RunStore.init` ruft `loadSettings()` unbedingt auf, und `persistSettings()` schreibt bewusst auch im Demo-Modus. Ein `-demo 1`-Lauf übernimmt damit, was eine frühere Debug-Sitzung in der App-Group hinterlassen hat.

Beobachtet: im App-Group des Watch-Simulators lag `maxHR: 136`. Deshalb stand die Zonenleiste im ganzen Demo-Lauf auf Zone 5, die Caption sagte dauerhaft „MAX" statt „RUN", und die Summary „mostly 5". Auf iOS dasselbe mit `maxHR: 187` aus einem `-zones derived`-Lauf.

Das ist mehr als ein Schönheitsfehler: die committeten Watch-Snapshot-Referenzen können gegen einen Fremdwert aufgenommen sein, und jede Beobachtung am Simulator ist unzuverlässig, solange das so ist. Der Demo-Pfad muss feste Zonen setzen statt die App-Group zu lesen.

#### Agent Comments

Beide Richtungen zugemacht: `loadSettings()` läuft im Demo-Modus nicht mehr, und `persistSettings()` hat jetzt denselben `!isDemo`-Guard wie jeder andere Schreibvorgang. Ein Demo-Store ist damit ein festes Bild und kein Fenster auf den echten.

**Die Begründung für das Schreiben trug nicht.** Sie lautete „das Widget hat keinen anderen Weg, das Ziel zu erfahren" — aber `write(runs)` wird im Demo-Modus längst übersprungen, das Widget sah also Demo-Einstellungen neben echten Läufen. Eine Mischung aus zwei Zuständen ist schlechter als jeder der beiden einzeln. Gekostet hat es dagegen etwas: den ganzen zone-5-Lauf auf der Uhr.

**Verifiziert am Simulator, mit dem Fremdwert absichtlich stehengelassen.** Die App-Group des Watch-Simulators enthält weiterhin `maxHR: 136`; der Demo-Lauf zeigt jetzt Caption „RUN", Zone 4 und die Nadel am unteren Rand — also die Zonen, die aus `HRZones()`-Defaults und dem simulierten Puls von ~157 folgen. Vorher: „MAX", Zone 5, Balken voll.

`docs/AGENT-NOTES.md` beschrieb den Leak als Tatsache, die man kennen muss. Der Abschnitt beschreibt jetzt die Abdichtung, behält aber das Symptom und den plist-Befehl — falls die Naht je wieder aufgeht, ist das die Spur.

Ein Test hält beide Richtungen fest. 191 Tests grün (vorher 190).

#### Link to completed work

https://github.com/candyscode/Currimus/commit/edf98e8


### CUR-32: Vier Zahlen, die etwas anderes behaupten, als sie messen

[ ] In Specification
[ ] Open
[ ] WIP
[X] Done

Aus dem Audit vom 30.07.2026.

1. **„MAX GRADE" im Trail-Detail ist im Wesentlichen GPS-Rauschen.** `maxGradePercent` unterstellt gleiche Distanzabstände zwischen den Höhensamples; die sind aber zeitgleich abgetastet (10 s, nach Dezimierung 20/40 s). Bergauf gegangen und bergab gelaufen liegen 10 m oder 80 m zwischen zwei Samples. Dazu enthält die Reihe Rohhöhen ohne die 1,5-m-Rauschgrenze — 2 m Jitter über 15 m Weg sind 13 % „Steigung". Ohne Distanz zu den Samples nicht reparierbar.
2. **Die Tanda-Marathonprognose teilt immer durch acht Wochen**, der Guard prüft aber acht *Läufe*. Acht Läufe in drei Wochen ergeben ~20 statt ~55 km/Woche, über den `exp`-Term ~21 s/km, also rund 15 Minuten zu langsam — und weil `headline = max(riegel, tanda)` gilt, wird genau diese Zahl die Schlagzeile.
3. **Ein 5-km-Rennen bekommt nie eine Prognose**, weil `predict` die Kandidaten auf `km < race.km * 0.95` filtert. Der Erklärtext verspricht sie trotzdem: „Run a 5 K, 10 K or half — and the prediction appears."
4. **„LAST 4 WEEKS ±x %" vergleicht ungleiche Fenster.** Aktuell sind es vier Kalenderwochen (am 30.07. = 25 Tage), das Vergleichsfenster ist ein glattes 28-Tage-Intervall, und zwischen beiden liegt eine Lücke von vier Tagen, die in keinem zählt. Am Montag: −21 % systematischer Fehler und sieben Tage Lücke.
5. **Herzfrequenz-Drift ohne Zeitfenster.** `hrAtPace` teilt das *gesamte* Log in „älter" und „neuer"; bei drei Jahren Historie vergleicht „than it used to be" Jahr 1 mit Jahr 3 und bewegt sich nie mehr. Zwei passende Läufe genügen für die Aussage.
6. **`HealthImport.distanceTrace` fragt ohne Quellenfilter ab.** `HKSampleQuery` dedupliziert nicht; schreiben Uhr und iPhone parallel `distanceWalkingRunning`, wird die Distanz addiert — rekonstruierte Splits wären doppelt so schnell und würden falsche Rekorde erzeugen. Plausibel, nicht bewiesen (der Pfad greift nur ohne Route). Ein Prädikat auf das Workout kostet nichts.

#### Agent Comments

**1 · „MAX GRADE" heißt jetzt „STEEPEST 100 M" und kommt aus der Route.** Die Höhenreihe konnte die Frage nicht beantworten — sie ist zeitgetaktet, nicht distanzgetaktet, und enthält Rohhöhen ohne Rauschgrenze. Die Route weiß, wo die Höhe gewonnen wurde, also wird sie gefragt (`RunAnalytics.steepestGradient`).

Das Fenster ist mit 100 m absichtlich fünfmal so lang wie `gradeSegmentKm`, und der Grund steckt im Wort „steilste": eine Steigungskorrektur summiert hunderte Segmente, das Rauschen darin hebt sich auf — ein Maximum tut das Gegenteil und sucht sich das rauschigste. Zwei Meter Wackeln über 20 m sind 10 %, über 100 m sind es 2 %. Ein Test legt genau das fest (`testElevationJitterIsNotAWall`). Läufe ohne Track zeigen „–" statt einer Zahl, die sie nicht belegen können.

**2 · Tanda rechnet über die Wochen, die das Log wirklich abdeckt** — und zwar in ganzen Wochen, aufgerundet. Der Zaunpfahl war die Falle: vier Läufe pro Woche über acht Wochen liegen 7,7 Wochen zwischen erstem und letztem Lauf, und durch 7,7 zu teilen hätte das Volumen jedes Mal um eine Wochenportion überschätzt. Die abgedeckten Wochen zu zählen ist die pfahlfreie Lesart und hält einen Taper korrekt: wer die letzten zwei Wochen eines langen Blocks ruht, teilt weiter durch acht, weil der Block acht Wochen alt ist. Dazu ein Minimum von vier Wochen — acht Läufe in einem Fortnight sind kein Trainingsblock, was die Arithmetik auch sagt. `weeksCovered` steckt jetzt im Ergebnis, damit der Satz auf dem Screen die Periode nennt, die er gelesen hat, statt acht Wochen zu behaupten.

**3 · Die Kandidatenliste enthält die Renndistanz selbst** (`<=` statt `< 0.95`), und Marathon ist dazugekommen — es fehlte aus demselben Grund. Riegel über die Identität gibt die Leistung zurück, was genau richtig ist: die beste 5 km ist die ehrliche Prognose für 5 km. Der Text sagt in diesem Fall „ist deine beste 5K-Leistung — die Distanz selbst, nichts zu skalieren", statt Riegel eine Identität zuzuschreiben.

**4 · Beide Vier-Wochen-Fenster liegen jetzt auf demselben Raster**: vier rollende 7-Tage-Eimer, direkt aneinander, ohne Loch und ohne Teilwoche auf einer Seite. Die Balken tragen seit immer die Labels W1…now und haben nie Kalenderwochen behauptet, also passen rollende Eimer dort besser als vorher. Am Simulator vorher/nachher: die „now"-Säule war ein angebrochener Donnerstag, jetzt eine ganze Woche (59/61/53/60 = 235 km), und die Prozentzahl steht auf **+13 %** statt auf einem Rückgang, den es nicht gab.

**5 · Der Drift hat ein Fenster** (180 Tage) und braucht vier Läufe statt zwei. Ohne Fenster verglich „than it used to be" bei langer Historie Jahr 1 mit Jahr 3 und bewegte sich nie mehr.

**6 · Ein Quellenfilter für die Distanzproben**, zweistufig, damit die bisherige Reichweite erhalten bleibt: erst die Proben, die am Workout hängen; wenn keine da sind — viele Apps hängen nichts an —, dieselbe *Quelle* im Zeitfenster des Workouts. Nicht mehr alles von jedem Gerät, was sich bei parallel schreibender Uhr und Telefon addierte.

12 neue Tests, 203 grün (vorher 191). Ein Test musste angepasst werden: keiner.

#### Link to completed work

https://github.com/candyscode/Currimus/commit/daeffa8


### CUR-33: Konsistenz — was die App über denselben Lauf zweimal verschieden sagt

[ ] In Specification
[ ] Open
[ ] WIP
[X] Done

Aus dem Audit vom 30.07.2026. Einzeln klein, zusammen der Unterschied zwischen „sorgfältig" und „ungefähr".

1. **Home und Log beschreiben denselben Lauf verschieden.** `RecentRow` färbt die Pace bei `< 310` orange — genau die feste Schwelle, die im Log verworfen wurde („meant nothing without knowing the runner's level"). Ein 6:00-Läufer sieht nie einen Akzent, ein 4:30-Läufer bei jedem Lauf. Dazu zeigt `RecentRow` `classification.label` auch für importierte Läufe (die keine Splits und Zonen haben, also immer „Easy" oder „Long"), während dieselbe Zeile im Log korrekt die Quelle nennt. Trail- und Indoor-Marker fehlen auf Home ganz.
2. **„60 / 70 / 80 / 90 % of your max" stimmt bei Zone 1 nicht** — `bounds` benutzt `0.605`, um ein Design-Mock zu treffen. Bei 187 ergibt das 113 statt 112.
3. **Das Zone-1-Label schließt einen Puls aus, der in Zone 1 liegt.** `zone(for: 113) == 1`, das Label sagt „< 113".
4. **Zonengrenzen lassen sich über Kreuz stellen.** `adjustBound` klemmt nur gegen 60 und `maxHR-1`, nicht gegen die Nachbargrenze — Ergebnis sind Labels wie „151 – 133" und `range()` mit `hi < lo`.
5. **„RACE DAY · <Name>" steht auch über „42 DAYS".** Derselbe Kicker für heute und für sechs Wochen vorher.
6. **Höhenmeter werden dreifach formatiert.** `Format.elevation` gruppiert mit „." (im englischen UI liest „1.024 m" als 1,024 Meter), `RunDetailView.grouped` mit Leerzeichen, `Format.km` immer mit POSIX-Punkt. Alle drei ignorieren das Locale.
7. **Zwei Trendlinien auf einem Screen, zwei Rechenmethoden.** Die 12-Wochen-Pace-Schlagzeile nimmt rohe erste-gegen-letzte Woche — bei ±10 s Wochenrauschen ist „−0:13" keine Aussage. Der Zone-2-Block darunter glättet korrekt mit `trendChange`. Ebenso fällt „since <Monat>" oben auf den Fensteranfang zurück statt auf den ersten vorhandenen Punkt.
8. **Die Trail-Steigrate ist ungewichtet** — eine Woche mit einem kurzen Lauf wiegt wie eine mit vier. Die Doku von `gradeAdjustedSummary` argumentiert im selben File gegen genau diese Mittelung.
9. **VoiceOver sagt „weeks" bei einem Monats-Chart** (`TrendChart.spokenSummary`).
10. **`HealthRebuild.settled` wird nicht persistiert**, also zählt die Settings-Zeile nach jedem Start wieder Läufe, für die Health nachweislich nichts mehr hat.

#### Agent Comments

**1 · `RecentRow` ist weg; Home zeichnet jetzt `LogRow`.** Das war der ehrlichste Fix: die beiden Zeilen widersprachen sich, weil es zwei Zeilen waren. Home bekommt damit auch die TRAIL- und INDOOR-Marker und die PR-Tags, die es vorher nicht hatte, und `LogRowText` beantwortet die Frage „wie liest sich dieser Lauf" an einer Stelle — gecacht, wie vorher schon fürs Log.

**2 · `0.605` ist `0.60`.** Ein Mock, der einen Schlag neben seiner eigenen behaupteten Arithmetik liegt, verliert gegen die Arithmetik — der Satz „at 60 / 70 / 80 / 90 %" steht direkt darunter. Zwei bestehende Tests hielten die 115 fest und wurden auf 114 gezogen; ihre Logik blieb unberührt. Ein neuer Test prüft die Behauptung jetzt gegen mehrere Maxima, damit die beiden nicht wieder auseinanderlaufen können.

**3 · Zone 1 heißt „≤ 114"** statt „< 114". Am selben Screen fing Zone 2 bei 115 an, der fehlende Schlag war also sichtbar.

**4 · Grenzen können nicht mehr über Kreuz.** Zwei Ebenen: der Stepper klemmt gegen die Nachbargrenze, und `HRZones.bounds` ignoriert `overrides`, die keine Leiter sind — Werte, die keine fünf Zonen beschreiben können, erreichen den Screen nicht, egal woher sie kommen (alter persistierter Wert, Payload von der Uhr).

**5 · „TARGET RACE · <Name>"** für den Countdown; „RACE DAY" bleibt dem Tag selbst.

**6 · Eine Zahlenformatierung.** `Format.elevation` gruppiert nach Locale statt mit fest verdrahtetem Punkt, `Format.km` und `Format.pacerDistance` ebenso, und der dritte Formatierer im Trail-Detail (Leerzeichen als Gruppierung) ist gelöscht.

> **Andi, das braucht dein Nein oder dein Ja:** dieser Punkt ändert *jede* Distanz auf dem Bildschirm für alle nicht-englischen Regionen. Auf diesem Mac (deutsche Region) liest Home jetzt „22,2 km" und „12,00 KM". Das ist das Verhalten, das iOS vorsieht — Zahlenformat folgt der Region, nicht der App-Sprache, und die App macht es bei Datumsangaben längst so („SAT 25. JUL"). Wenn dir die Mischung aus englischem Text und deutschem Komma nicht gefällt, ist es eine Zeile in `Format.km`, um auf ein festes Format zurückzugehen. Die Höhenmeter-Gruppierung sollte in jedem Fall locale-abhängig bleiben — dort war der alte Wert schlicht falsch.

**7 · Die 12-Wochen-Pace-Schlagzeile nutzt `trendChange`** wie der Zone-2-Block, und „since <Monat>" zeigt bei beiden Wochen-Charts auf die erste Woche, die wirklich einen Wert trägt (`firstWeekMonth`), nicht auf den Fensteranfang.

**8 · Die Steigrate ist Klettermeter über Stunden** statt Mittel der Wochenraten.

**9 · `TrendChart` hat ein `period`** und der Zone-2-Chart übergibt „months".

**10 · `settled` überlebt einen Start** (`AppDefaults.settledRebuildsKey`). `asked` bewusst nicht: ein gescheiterter Abruf lag oft am gesperrten Gerät, und eine neue Sitzung soll es erneut versuchen. „Health hat nichts mehr" hört dagegen nicht über Nacht auf, wahr zu sein.

Fünf neue Tests, 208 grün (vorher 203). UI-Tests grün. Snapshot-Referenzen für iOS und watchOS neu aufgenommen, weil hier absichtlich Screens verändert wurden.

#### Link to completed work

https://github.com/candyscode/Currimus/commit/f79bd9b


### CUR-34: Ein Testziel für watchOS

[ ] In Specification
[ ] Open
[ ] WIP
[X] Done

Aus dem Audit vom 30.07.2026, Punkt 6 der Testkritik. `RunSession` ist mit 925 Zeilen die zweitgrößte Datei der App und läuft in **keinem** Test — es gibt kein watchOS-Testziel. Was dort ungeprüft liegt, ist nicht Arithmetik (die steckt in `RunMetrics` und ist gut getestet), sondern alles, was ein Lauf *ist*:

- **Das Zusammensetzen des fertigen Laufs.** `end()` baut fünfzehn Felder aus vier Quellen zusammen. Ein Fehler darin ist ein falscher Logbucheintrag, und einer davon war schon da: `date` war `now - elapsed`, was bei jedem pausierten Lauf die Startzeit nach vorn wanderte.
- **Die Phasenmaschine.** `pause`/`resume`/`skipCountdown`/`reset` sind vier Wächter über sieben Zuständen, plus die Hardware-Geste, die die Session von außen pausiert.
- **Der Lebenszyklus des Coaches.** Der Kommentar in `resetMetrics` beschreibt einen echten Fehler: ein aus dem letzten Lauf übernommener Coach brachte seine Uhr mit, und `lastFired` auf der Elapsed-Zeit des Vorlaufs unterdrückte jeden Hinweis in der ersten halben Stunde des nächsten.
- **Die Pacer-Arithmetik.** `scheduleDelta` und `finishForecast` sind zwei Zeilen, die niemand nachgerechnet hat — und `finishForecast` unterstellt, dass die Restdistanz im Zieltempo gelaufen wird, was eine Festlegung ist und keine Nebensache.

Der `RunSimulator` deckt die Sekunde-für-Sekunde-Rechnung schon kopflos ab; dieses Ziel deckt die Hülle darum ab.

Umfang: neues Ziel `CurrimusWatchTests`, das `Shared` und **nur** `Watch/RunSession.swift` kompiliert — die übrigen Watch-Dateien sind Views, und `WatchApp.swift` trägt `@main`, was in einem Testbundle nicht vorkommen darf. Kommando in die Agent-Notes.

#### Agent Comments

`CurrimusWatchTests` steht, 27 Fälle, 1,2 Sekunden. Alles wird über `debugJumpScenario` getrieben, nie über `begin()`: `begin` startet einen echten 1-Hz-`Timer` auf dem Main-Run-Loop, und damit wäre jede Zusicherung danach ein Rennen. Ein Szenario läuft ohne Timer und ohne Zufall — dieselben Szenarien, auf die der kopflose Simulator schon zusichert.

Was jetzt abgedeckt ist: das Zusammensetzen des fertigen Laufs (inklusive der Startzeit, der Rundung, Zonen-Sekunden *und* Zonen-Distanz, Laufband ohne Route, Steigungskorrektur aus der eigenen Route, Kadenz als fehlende statt als Null-Messung), die Phasenmaschine samt der Wächter, die Pacer-Arithmetik, und was von einem Lauf in den nächsten übergeht.

**Mutationstests, weil ein Test, der nicht fehlschlagen kann, schlimmer ist als keiner.** Drei Mutationen eingebaut und wieder entfernt:

| Mutation | gefangen |
|---|---|
| `date: .now.addingTimeInterval(-elapsed)` (der alte Startzeit-Fehler) | **ja** — 3,5 h Abweichung, zwei Zusicherungen |
| `coachZone()` aus `scenarioSecond` entfernen | **ja** — drei Tests |
| `coach = …` aus `resetMetrics` entfernen | **nein**, siehe unten |

**Zwei Funde beim Schreiben der Tests:**

1. **`scenarioSecond` rief `coachZone()` nicht auf.** Die Szenario-Wiedergabe — das Werkzeug, mit dem man einen ganzen Lauf gegen eine *bekannte* Herzfrequenzkurve beobachtet — hat den Coach nie gefragt, während die Demo-Simulation daneben es tat. Der Kommentar aus CUR-6 („Cues also run in the watch simulator's demo runs… that is the only place this can be watched at all") stimmte nur für die andere Simulation. Behoben, ein Aufruf.

2. **Die Zeile in `resetMetrics`, die den Coach neu baut, ist defensiv und nicht tragend** — und das ist ehrlicher aufgeschrieben als eine Deckung zu behaupten, die es nicht gibt. Ein übernommener Coach erholt sich, sobald der Läufer wieder durch die Zielzone steigt, weil ein Cue *anderer Art* die Kadenz sofort unterbricht (`ZoneCoach.interrupts`) — und jeder Lauf steigt auf dem Weg nach oben durch seine Zielzone. Der beschriebene Effekt („unterdrückte jeden Hinweis in der ersten halben Stunde") ist damit auf dieser Strecke nicht beobachtbar. Die Zeile bleibt: sich auf diese Rettung zu verlassen heißt, sich auf ein Detail eines anderen Typs zu verlassen. Der Test sichert stattdessen das Ergebnis, auf das es ankommt — der zweite Lauf wird gecoacht, an derselben Sekunde wie der erste.

Ein Test musste angepasst werden, weil meine Annahme falsch war und nicht der Code: der Straßen-Szenario-Höhenverlauf ist eine Sinuswelle, dort wächst die Steigung nicht monoton mit der Distanz. Der Trail-Lauf ist der eindeutige Zeuge für „hat neu angefangen".

208 iOS-Tests, 27 watchOS-Tests, 3 UI-Tests, beide Ziele bauen.

#### Link to completed work

https://github.com/candyscode/Currimus/commit/7a14f3b


### CUR-35: Andis Entscheidungen zum Audit

[ ] In Specification
[ ] Open
[ ] WIP
[X] Done

Vier Entscheidungen zu den offenen Punkten aus dem Audit vom 30.07.2026 (CUR-29 … CUR-34).

1. **Zahlenformat: „22.2" bleiben lassen.** Also nicht der Region folgen.
2. **Löschhinweis generisch** — „wurde außerhalb von Currimus angelegt", ohne Nennung der genauen Quelle. Und **beim PR keine Vermerkung der Quelle**: „ist ja dem Nutzer egal wo er es aufgestellt hat, Hauptsache der Rekord ist da."
3. **Die „MAX"-Caption auf dem Run-Screen kann weg.**
4. **Der BPM-Stepper bleibt wie er ist.**

#### Agent Comments

**1 · Ein festes Format, nicht null Formate.** `Format.km` folgt nicht mehr der Region — aber der alte Zustand war nicht der Zielzustand, sondern drei Formatierer, die sich widersprachen. Alle drei laufen jetzt über ein festes `Locale(identifier: "en_US")`: Punkt als Dezimal-, Komma als Tausendertrennzeichen. Das ist in sich schlüssig (bei „22.2" *muss* die Gruppierung ein Komma sein, sonst liest „1.622 m" wieder als eineinhalb Meter), und weil es fest ist, hängen die UI-Snapshot-Referenzen nicht mehr an der Region der Maschine, die sie aufgenommen hat.

`en_US` und nicht `en_US_POSIX`: die POSIX-Variante ist für maschinenlesbare Ausgabe gedacht und schaltet die Gruppierung ganz ab — ein vierstelliger Höhenmeterwert kam als „1622" heraus. Ein Test hält jetzt beide Trennzeichen fest.

**2 · Löschhinweis ohne Quelle, an einer Stelle.** `DeletePrompt.importedExplanation` nennt keine Quelle mehr, und das Run-Detail benutzt jetzt dieselbe Funktion statt eines eigenen zweiten Satzes. Der Grund ist stärker als „generisch ist ruhiger": `sourceRevision.source.name` ist nur bei Fremd-Apps ein App-Name — bei einem von Apples Workout-App aufgezeichneten Lauf ist es der **Gerätename**, und „delete it in Apple Watch von Andreas" schickt jemanden zu einer Uhr, wenn die Antwort die Fitness-App auf dem Telefon ist. Ein Satz, der für Strava stimmt und für die Apple Watch nicht, ist schlechter als einer, der nichts nennt und auf Fitness zeigt.

**`DeletePrompt` ist nach `Shared/` gewandert.** Es war in `iOS/`, und das Testziel kompiliert `Tests` + `Shared` — nichts in `iOS/` ist von einem Test aus erreichbar. Text, der dem Nutzer etwas behauptet, gehört dorthin, wo ein Test ihn lesen kann; `LogRowText` liegt aus demselben Grund schon dort.

**3 · Der Rekord schlägt die Quelle.** In `LogRowText` wird der PR-Zweig jetzt *vor* dem Import-Zweig geprüft. Ein fremd aufgezeichneter Lauf, der die 10-km-Bestzeit hält, zeigt sie damit auch auf seiner eigenen Zeile — vorher stand sie auf dem Records-Screen und die Zeile trug kein Tag. Unterhalb eines Rekords macht die Quelle weiter ihre Arbeit: sie erklärt, warum die Zeile keine Zone nennt. „Longest" ist keine Benchmark-Zeit und verdrängt die Quelle nicht.

**4 · Die „MAX"-Caption ist weg**, der Run-Screen sagt immer „RUN". Dieselbe Form, die CUR-4 der Pace genommen hat: ein Zustand, der kommt und geht, in dem Slot, der überall sonst auf der Uhr den Screen benennt. Die Zonenleiste zwei Zentimeter darunter sagt dasselbe ruhiger und genauer.

**5 · Der BPM-Stepper bleibt unberührt**, wie entschieden.

Fünf neue Tests, 211 iOS-Tests grün, 27 watchOS-Tests grün, beide Ziele bauen, Snapshot-Referenzen neu aufgenommen (die Distanzen standen dort mit Komma).

#### Link to completed work

https://github.com/candyscode/Currimus/commit/7a4be7e


### CUR-36: Minor UI Improvements

[ ] In Specification
[ ] Open
[ ] WIP
[X] Done

1) In Home: bei "goal 55 km" die Möglichkeit vorsehen, direkt zur Einstellung des Goals zu kommen, z.B. kleiner Button "modify goal" oder so.

2) Importierter Lauf heißt immernoch Apple Watch von Andreas. Das wollten wir ja explizit nicht mehr haben. Lieber Morning Run, Afternoon Run, Easy Run oder Run in Neufahrn, Run in Munich irgendwas in die Richtung

3) Wenn ich in die Race Ansicht gehe und dann auf Back drücke komme ich ja wieder zu Home. Dann dauert es aber eine halbe Sekunde, bis die Tabbar unten wieder erscheint. Bitte fixen.

4) Im Detail View den Text unten "This run was recorded outside Currimus" entfernen, der Text, wenn man in Edit Run bei einem importierten Run geht ist ausreichend.

5) Im Log steht immernoch oft "Apple Watch von Andreas" in den Items. Kann ersatzlos weg. Auch dass bei Trailruns nochmal in der zweiten Zeile Trail steht kann weg, wir haben dafür ja dieses orange Trail Label.

6) In der zweiten Zeile im Log Item soll stehen Zeit und Haupt-Pulszone, wobei die dann ausgeschrieben werden kann, weil wir ja Platz haben "Zone 2" statt Z2.

7) Die ganzen Erklärungstexte (worauf basiert diese Berechnung?) sind zu lang geworden, um sie in der UI standardmäßig anzuzeigen. Mach lieber einen kleinen info-Button hin, der dann ein Modal mit der Erklärung öffnet.

8) In den Erklär-Texten sind teilweise wichtige Infos versteckt. Z.B. im Run Mode ist im ewig langen Fließtext die vorhergesagte Zeit nach Riegel. Solche Infos NIEMALS im Fließtext sondern die brauchen ein eigenes UI Feld. Dann bei jedem der Felder eine Möglichkeit, sich die Herleitung anzeigen zu lassen.

#### Agent Comments

Sieben der acht Punkte sind drin. **Punkt 3 nicht** — dazu unten, und das ist der einzige, bei dem ich Hilfe brauche.

**1 · „goal 55 km" öffnet das Ziel.** Ein `WeeklyGoalMenu` mit derselben Optionsliste, die Settings schon benutzt — jetzt an beiden Stellen dasselbe Menü statt zweier Kopien. Auf Home trägt die Zeile ein kleines Auf/Ab-Chevron als Affordanz und behält ihre gedämpfte Caption-Optik: die Zahl ist eine Nebeninformation, kein Button.

**2 · Importierte Läufe heißen nach der Tageszeit.** `RunNaming.defaultName` ist eine Regel für beide Quellen — die Uhr benannte ihre Läufe schon so, Health-Läufe nahmen `sourceRevision.source.name`. Night / Morning / Afternoon / Evening Run, plus „Indoor Run" fürs Laufband und „Trail run". Kein Reverse-Geocoding für „Run in Neufahrn", so verlockend das ist: die App macht keinerlei Netzwerkaufrufe, und das ist mehr wert als ein hübscheres Substantiv. Bestehende Einträge korrigieren sich von selbst, weil die importierte Liste bei jedem Foreground komplett ersetzt wird.

**4 · Der Hinweis im Detail ist weg.** Der Edit-Run-Text sagt es, und der sagt jetzt „Recorded outside Currimus" statt „Recorded by <Name>" — der Name ist ja inzwischen Currimus' eigener.

**5 + 6 · Die zweite Zeile im Log hat eine Form statt vier.** Zeit · Zone, ausgeschrieben, plus Höhenmeter beim Trail. Weg sind: der Quellenname, das Wort „Trail" neben dem orangen TRAIL-Label, und die Klassifikation — die kam aus Splits und Zonen, die importierte Läufe nicht haben, weshalb jeder von ihnen „Easy" hieß. **Sag Bescheid, wenn du die Klassifikation vermisst**; du hast in Punkt 6 „Zeit und Haupt-Pulszone" geschrieben, ich habe das wörtlich genommen.

**7 · Erklärungen hinter einem ⓘ.** Neu: `Explanation`, `InfoButton`, `ExplanationSheet` und `ExplainedStat` in `iOS/Explain.swift`. Der Button ist 13 pt und in `Theme.faint` — er sitzt neben einem Kicker und darf nicht mit der Zahl darüber konkurrieren —, hat aber ein 30-pt-Ziel darunter. Das Sheet kommt mit `.medium`-Detent, weil die meisten Erklärungen ein Absatz sind, und wächst für die, die es nicht sind. Umgestellt: die beiden Absätze auf dem Zonen-Screen (der passt jetzt ohne Scrollen), die Steigungskorrektur im Progress-Tab, und die Fußnote unter dem Zone-2-Chart. **Nicht umgestellt: die „NEXT TIME"-Karten im Run-Detail** — die sind Rat und nicht Herleitung, sie *sind* der Inhalt der Karte.

**8 · Die Prognosen sind Felder.** Der Race-Screen hatte eine Kachel „PREDICTED" und darunter einen Absatz, der beide Zahlen fett mitten im Satz trug. Jetzt: `FROM RACING` und `FROM TRAINING` nebeneinander, jede mit ⓘ. Der ganze Fließtext ist in die zwei Sheets gewandert, inklusive der Sätze über Stale-Basis, Extrapolation und — das ist der eigentliche Fund des Screens — wie weit die beiden Modelle auseinanderliegen und was das heißt.

**Nebenbei gefunden und behoben: `GlassIconButton` hatte keine Accessibility-Labels.** Back, Close und Settings wurden von VoiceOver als „button" angesagt, sonst nichts. Ein Screen, dessen einziger Ausgang keinen Namen hat, ist ein Screen ohne Ausgang.

#### Punkt 3 · die Tab-Bar-Verzögerung — behoben, nachdem sie messbar wurde

**Nachtrag.** Andi hat ein Bildschirmvideo geliefert, und damit wurde aus Raten Messen. Ich habe die Einzelbilder mit AVFoundation extrahiert und die Helligkeit des Tab-Bar-Streifens Bild für Bild gerechnet:

| | |
|---|---|
| Pop-Animation fertig | 1,467 s |
| Tab-Bar erscheint | 1,800 s |
| **Lücke** | **0,333 s** |

Und sie fährt nicht ein, sie **springt** — von einem 60-Hz-Bild aufs nächste. Es ist keine langsame Animation, es ist eine späte.

Dann dieselbe Messung auf dem Simulator nachgebaut (Bildschirmaufnahme während der UI-Test zurücktippt, Frames raus, Streifen messen). Der Simulator reproduziert es mit **0,483 s**, und damit ließen sich Kandidaten vergleichen statt vermuten:

| Variante | Lücke |
|---|---|
| unverändert | 0,483 s |
| Sichtbarkeit aus dem Navigationspfad (mein erster Versuch) | **2,300 s** — deutlich schlechter |
| `toolbarVisibility` statt `toolbar` (iOS-26-Schreibweise) | 0,500 s — unverändert |
| Swipe-Back-Probe aus dem gepushten Screen genommen | 0,400 s — fast unverändert |
| **gar nicht ausblenden** | **keine Lücke** |

Dein Vorschlag mit dem Einfaden war der richtige Instinkt und ich habe ihn gebaut: `TabBarFade`, die die Leiste selbst auf- und abblendet statt sie vom System verstecken zu lassen. Er ist wieder draußen, weil er **nicht erreichbar** ist: SwiftUI gibt keinen Griff auf die Leiste heraus, `tabBarController` ist von dort nil, und die schwebende iOS-26-Leiste ist auch keine `UITabBar`, nach der man die View-Hierarchie durchsuchen könnte. Was der Versuch immerhin gezeigt hat: bei Alpha 0 bleibt die Leiste im Accessibility-Baum — VoiceOver wäre auf einem gepushten Screen weiter darauf gelaufen.

Also die Variante, die du selbst ins Spiel gebracht hast: **die Leiste bleibt stehen.** Keine Lücke, weil nichts wiederhergestellt wird, und es ist ohnehin das Standardverhalten der Plattform — `hidesBottomBarWhenPushed` ist opt-in. Dein Einwand zum Verdecken trägt: man kann scrollen. Ein UI-Test prüft, dass das auch am Ende eines langen Screens gilt (der „Delete run"-Button im Run-Detail ist nach dem Scrollen erreichbar — der Safe-Area-Inset kommt automatisch, sobald die Leiste da ist).

Übrig bleibt eine Sache, die du sehen solltest: auf gepushten Screens leuchtet jetzt der Tab, aus dem man gekommen ist. Das ist iOS-Standard, aber es ist eine sichtbare Änderung am Design.

#### Punkt 3 · der erste Anlauf (zur Nachvollziehbarkeit)

Ich habe es versucht und **messbar nichts erreicht**, deshalb ist die Änderung wieder draußen statt als Fix verkauft.

Der Verdacht war richtig formuliert: die Sichtbarkeit wird auf dem *gepushten Ziel* deklariert, also fängt die Leiste erst an zurückzukommen, wenn dieses Ziel vom Schirm ist. Ich habe sie stattdessen aus dem Navigations-Pfad abgeleitet (`path.isEmpty`), was den Zustand sofort beim Back-Tap umlegt.

Gemessen mit einem neuen UI-Test: **1,81 s vorher, 1,82 s nachher.** Kein Unterschied. Und die Messung taugt auch nicht, um eine halbe Sekunde aufzulösen — `XCUIElement.tap()` kehrt erst zurück, wenn die App komplett still ist, die Zahl ist also „Tap-Synthese + alles Nachschwingen" und von beidem dominiert.

Was der Versuch immerhin gezeigt hat: **zwei `toolbar(_:for: .tabBar)`-Deklarationen in einem Stack komponieren nicht** — die äußere gewinnt, auch gegen `.automatic`. Der Markiermodus des Logs zeigte plötzlich beide Leisten übereinander. Das ist jetzt ein UI-Test, damit es niemandem noch einmal passiert.

**Was ich von dir bräuchte:** ein kurzes Bildschirmvideo vom Gerät (Back aus der Race-Ansicht). Daran kann ich abzählen, ob die Leiste *nach* dem Pop einschwebt oder ob sie mit ihm kommt und nur langsam einblendet — das sind zwei verschiedene Ursachen und zwei verschiedene Fixes. Ohne das rate ich, und ich habe schon einmal geraten.

Fünfzehn neue Tests (11 Unit, 4 UI). 219 iOS-Tests, 27 watchOS-Tests, 7 UI-Tests, beide Ziele bauen, Snapshot-Referenzen neu aufgenommen.

Drei bestehende Tests hielten das alte Verhalten fest und wurden nachgezogen: die „Z2"-Kurzform, der Quellenname in der Log-Zeile (den CUR-35 tags zuvor erst eingeführt hatte), und ein geschütztes Leerzeichen in meiner eigenen Erwartung.

#### Link to completed work

https://github.com/candyscode/Currimus/commit/d407a09 (Punkte 1, 2, 4–8)

https://github.com/candyscode/Currimus/commit/c55793b (Punkt 3 — die Leiste bleibt stehen)

### CUR-37: Ein Weg in die App statt zweier Sackgassen

[ ] In Specification
[ ] Open
[ ] WIP
[X] Done

Wenn ich die App zum ersten Mal starte, kann ich auf "Already have runs, bring them in" klicken. Wenn ich darauf klicke, dann wird der Button ausgegraut und man hat keine Progress- oder Statusanzeige. Das ist schlecht. Wir machen es anders auf dem Startscreen. Es gibt nur noch einen orangen Button ("Let's get started"). Dieser öffnet zunächst den Import-Dialog aus Settings / Apple Health mit Progress-Bar usw. Davor wird man vermutlich nach Apple-Health-Zugriff gefragt. Es soll also Standard sein, dass beim ersten Einrichten erstmal alles aus Apple Health gelesen wird. Wenn das fertig ist, kommt man in den Home-Tab. Wenn Apple Health abgelehnt wurde (das finden wir ja nicht direkt raus, aber wenn einfach nichts importiert wurde), soll dem Nutzer angezeigt werden, dass keine Läufe aus Apple Health importiert werden konnten. Wenn er Läufe auf seinem Gerät hat, kann das daran liegen, dass die Apple-Health-Freigabe nicht funktioniert hat. Er muss außerdem wissen, dass Currimus ohne diese Freigabe möglicherweise nicht ordnungsgemäß funktioniert. Der "Set up race, zones and pacer"-Button fällt einfach weg. Achte darauf, dass es ins Design und Look & Feel und Design System der App passt. Schreibe Tests wenn erforderlich.

#### Agent Comments

**Ein Knopf, und dahinter der ganze Vorgang.** „Let's get started" startet `RunStore.startFirstImport()`: Health-Freigabe erfragen, alle Lauf-Workouts des iPhones lesen, dann für jeden davon Herzfrequenz-Trace und GPS-Track nachladen. Das sind drei Schritte, aber für den Läufer ist es eine Sache, also ist es ein Zustand (`RunStore.FirstImport`) und ein Balken.

Der Balken hat zwei Modi, weil der Vorgang zwei hat: solange Health gefragt wird, gibt es nichts zu zählen — dort läuft ein unbestimmter Sweep. Sobald die Workout-Liste da ist, steht die Gesamtzahl fest und daraus wird „34 of 128" plus echter Fortschritt. Stoppen geht jederzeit; was gelesen ist, bleibt gelesen. Das Sheet ist dasselbe Muster wie `RebuildSheet` in Settings (gleiche Typo, gleicher Balken, gleiches Detent-Modal), aber ein eigener Typ: es sagt andere Dinge, und der Rebuild-Dialog hat weder einen unbestimmten Zustand noch einen Fehlschlag zu erklären.

**Der Fehlschlag hat einen eigenen Zustand, weil er der wahrscheinlichste ist.** Health beantwortet eine verweigerte Freigabe mit einer leeren Liste, nicht mit einem Fehler — absichtlich, damit aus einer Ablehnung keine Diagnose ableitbar ist. Die App kann also nie sagen „du hast abgelehnt". Sie sagt: nichts gekommen, wahrscheinlich die Freigabe, ohne sie hat Currimus kein Log, keine Rekorde und keinen Progress, hier ist der Pfad in den iOS-Einstellungen. Das steht einmal im Sheet und bleibt danach als Karte auf dem Startscreen stehen, wo der Knopf zu „Try Apple Health again" wird.

**Eine Abweichung von der Spec, bewusst:** in genau diesem Fehlerfall — und nur da — steht unter dem orangen Knopf noch ein leiser Textlink „Set up race, zones and pacer". Ohne ihn wäre die App für jemanden, der Health ablehnt und keine Uhr hat, eine Sackgasse ohne jeden Zugang zu den Einstellungen: der Tab-Bar-Zugang entsteht ja erst, wenn das Log etwas enthält. Im Normalfall ist der Startscreen genau ein Knopf, wie gewünscht.

**Zwei Dinge, die dabei kaputtgegangen wären:**
- Die ersten Läufe landen *mitten* im Import im Store, und `RootView` tauscht bei nicht-leerem Log die ganze Hierarchie gegen die Tabs aus — das hätte das Sheet mitgerissen. Der Startscreen bleibt jetzt stehen, solange ein Import läuft.
- Der Startscreen hatte für die Fehlerkarte keinen Platz: die Headline wurde auf zwei abgeschnittene Zeilen gequetscht („Simple. Beautiful…."). Im Fehlerzustand weicht deshalb die Vier-Punkte-Liste; wer liest, warum seine Läufe fehlen, ist über die Verkaufsargumente hinaus.

`refreshImportedRuns` hat einen `backfilling`-Schalter bekommen: der Erstimport schaltet den Zwölfer-Backfill ab, weil unmittelbar danach ohnehin das ganze Log mit sichtbarem Balken durchläuft — sonst wären zwölf Läufe zweimal aus Health gelesen worden, hinter einem Balken, der noch nicht läuft.

**Sechs neue Tests** (Zustandsmaschine über einen Demo-Store, der Health mit „sofort nichts" beantwortet — genau die Form des Pfads, um den es geht: doppeltes Starten, Stoppen, Clearen während des Laufs, der Bruch bei leerem Log). 225 iOS-Tests grün, beide Ziele bauen.

**Neue Debug-Flags** (`-noimport 1`, `-import reading|filling|done|nothing`), weil der Simulator keine Health-Daten hat und jeder echte Import dort fertig ist, bevor der Balken einmal gezeichnet wurde. Drei neue Snapshot-Referenzen hängen daran.

**Nebenbefund, und kein kleiner: die Snapshot-Harness hat zweimal gelogen.** Nach dem Umbau kam `first-launch.png` byteidentisch aus `record` zurück — also mit dem *alten* Startscreen, obwohl genau der geändert worden war. Ursache ist nicht der Build: `simctl io screenshot` verweigert die Aufnahme, solange der Simulator beschäftigt ist, und die erste Route nach einem Install ist genau dieser Moment. Der Fehler ging nach `/dev/null`, das Kandidatenbild vom *letzten Lauf* blieb liegen, wurde über die Referenz kopiert, und die Zeile meldete `rec`. Jede Referenz, die auf Platz eins der Routenliste stand, konnte damit beliebig alt sein, ohne dass es jemand sieht. Behoben: Kandidat vorher löschen, Screenshot bis zu dreimal versuchen, nach dem Install einmal warmlaufen lassen, und bei ausbleibendem Bild laut scheitern statt still zu kopieren.

#### Andis Review

Sieht gut aus, aber das Import-Overlay wirkt zu groß — unter dem Ladebalken ist sehr viel leerer Raum bis zum Button.

#### Agent Response

Stimmt: das Sheet hatte ein festes Detent von 420 pt, und die beiden Zustände ohne große Zahl (Reading, „Nothing to bring in") füllten das nie aus. Die Höhe wird jetzt am Inhalt gemessen (`onGeometryChange` → `presentationDetents([.height(gemessen)])`), plus dem Streifen für den Home-Indicator. Feste Werte pro Zustand wären das Naheliegende gewesen, taugen hier aber nicht: die Zustände wechseln unter dem geöffneten Sheet, und der Text wächst mit der Schriftgröße. Das Sheet wächst und schrumpft jetzt animiert mit dem, was es sagt.

#### Link to completed work

https://github.com/candyscode/Currimus/commit/40dc7aa

### CUR-38: Sechs Befunde aus der Benutzung

[ ] In Specification
[ ] Open
[ ] WIP
[X] Done

1) Im Race Mode: Entferne die "From Racing" estimation, behalte "From Training", benenne das aber um in "ESTIMATION", mit dem i-Icon daneben. Riegel-Estimation fällt also weg, nur noch Tanda. Die Erklär-Popups sind aber zu groß (zu viel Whitespace unter dem Text, also selbes Problem wie im letzten Prompt).

2) Im Log geht oft das Scrollen nicht, dann muss man zwei oder dreimal mit dem Finger ansetzen, dass man wirklich scrollt. Bitte fixen.

3) Wenn man im Log in den Filter-Pillen oben zwischen Road und Trail wechselt, sieht man in der Transition kurz den Delete-Button der Items. Das darf nicht sein.

4) Statt "IN ZONE 2..." bei Progress: "PACE IN ZONE 2...". Außerdem bei "Heart rate at" den cringen Anhang "that is fitness" streichen.

5) In Records die Kachel "Your Best 10K" flexibler machen. Sie soll den letzten Record-Run zeigen, unabhängig ob es ein 10K, 5K oder whatever ist. Wenn ich also kürzlich den ersten Marathon gelaufen bin, soll der da angezeigt werden. Wenn ich den Tag drauf einen 10K laufe, der schneller ist als mein letzter 10er, dann soll dieser in der Kachel angezeigt werden.

6) Ich verstehe den Text in Records, der mit "A 5K or 10K record is the..." beginnt, überhaupt nicht. Bitte erklären und hinterfragen, ob das so sinnvoll ist und ob die technische Logik, die er beschreibt, überhaupt sinnvoll ist.

Achte darauf, dass UI-Anpassungen zum Design der App passen.

#### Agent Comments

**1 · Eine Schätzung statt zweier.** „FROM RACING" ist weg, „FROM TRAINING" heißt jetzt `ESTIMATION` und trägt das ⓘ. Dahinter steht unverändert Tanda (2011): Wochenumfang und Trainingspace der letzten acht Wochen. Der Erklärtext hat den Absatz verloren, der die beiden Modelle gegeneinander gestellt hat — es gibt kein zweites mehr —, behält aber die beiden ehrlichen Warnungen (Extrapolation außerhalb der Studienwerte, längster Lauf weit unter Renndistanz).

**Zwei Konsequenzen, die du kennen solltest:**

- **Für 5 K, 10 K und Halbmarathon gibt es jetzt gar keine Schätzung mehr.** Tanda ist auf den Marathon gefittet und sagt über einen 10er nichts; Riegel war das Modell, das kürzere Distanzen bedient hat. Die Kachel steht dort auf „—", und das ⓘ sagt warum. Das ist die wörtliche Umsetzung deiner Ansage — sag Bescheid, wenn du für Nicht-Marathon-Rennen lieber Riegel unter demselben Label „ESTIMATION" zurück hättest (das ⓘ nennt ja ohnehin die Grundlage, es wäre also nicht unehrlich). `RunAnalytics.riegel` und `predict` bleiben inklusive Tests im Code, damit das ein Einzeiler ist.
- **Home zeigt dieselbe Zahl.** Die Kachel dort hieß „PREDICTED" und zeigte `max(Riegel, Tanda)` — nach der Änderung hätten Home und Race zwei verschiedene Zielzeiten für dasselbe Rennen gezeigt. Home heißt jetzt auch `ESTIMATION` und liest denselben Wert.

**1b · Die Erklär-Sheets messen ihre Höhe.** Sie standen auf `.medium`, also immer halber Bildschirm, egal ob drei Zeilen oder dreißig. Jetzt: Inhalt messen, Detent = gemessene Höhe, gedeckelt bei 560 pt — wer darüber liegt (der Records-Text), scrollt und lässt sich weiterhin auf volle Höhe ziehen. Neue Snapshot-Routen `race-explain` und `records-explain` halten das fest, sonst kann es unbemerkt zurückrutschen.

**2 · Das Log scrollt wieder — und der Fehler war größer, als du ihn beschrieben hast.** Ein neuer UI-Test (`LogScrollUITests`) wischt einmal von einer Zeile aus nach oben und misst, wie weit sich das Log bewegt hat. Vorher: **0,0 pt, zehnmal von zehn.** Der Kontrolltest — derselbe Wisch, nur nicht auf einer Zeile begonnen — scrollte problemlos. Es ist also nicht „geht oft nicht", es ging **nie**, wenn der Finger auf einer Zeile aufsetzte; was du als zweiten und dritten Versuch erlebt hast, war vermutlich das Treffen der schmalen Ränder zwischen den Zeilen.

Ursache: die Wisch-Geste der Zeile stand auf `minimumDistance: 14`. `simultaneousGesture` soll sich die Berührung mit dem ScrollView teilen und tut es nicht — wer zuerst erkennt, behält sie, und bei 14 pt war das immer die Zeile. Bei 30 pt fängt der ScrollView zuerst an, und beide Gesten funktionieren. Der Wert ist gemessen, nicht geraten: 14 → 0 pt, 30 → volle Scrollstrecke, zehn von zehn. Damit die Zeile dabei nicht 30 pt springt, wenn sie die Geste übernimmt, rechnet sie den bereits gelaufenen Weg heraus — sie folgt dem Finger ab dem Punkt, an dem sie ihn bekommt.

Der saubere Weg wäre `UIGestureRecognizerRepresentable` (iOS 18) mit einem Pan-Recognizer, der nur bei horizontaler Bewegung anspringt; das erlaubt eine kleinere Schwelle. Ist notiert, aber ohne Not: die drei Wisch-Tests laufen mit 30 pt unverändert grün.

**3 · Der Delete-Button in der Filter-Transition ist weg.** Die Kachel lag permanent hinter jeder Zeile und war nur von deren eigener deckender Füllung verdeckt — beim Filterwechsel blenden die Zeilen aus und geben sie frei. Sie wird jetzt nur noch gezeichnet, wenn die Zeile überhaupt verschoben ist.

**4 · Beide Texte geändert.** „PACE IN ZONE 2 · LAST 12 MONTHS", und der Halbsatz „— that is fitness" ist gestrichen. Der Rest des Satzes sagt dasselbe, ohne dem Läufer auf die Schulter zu klopfen.

**5 · Der Records-Banner kennt alle Distanzen.** Statt nur 5 und 10 km läuft er über alle fünf Benchmarks und zeigt den zuletzt gesetzten Rekord. Dein Marathon-Beispiel ist genau der Testfall, der dabei einen echten Fehler aufgedeckt hat: **ein Lauf setzt mehrere Rekorde gleichzeitig.** Ein erster Marathon hält auch den schnellsten Halbmarathon und den schnellsten Kilometer im Log — alle mit demselben Datum. Der Banner hätte davon „1 km" gezeigt, weil bei Datumsgleichstand die Reihenfolge der Aufzählung entschied. Jetzt: neuestes Datum zuerst, bei Gleichstand die längste Distanz. Ein Marathon meldet sich als Marathon.

**6 · Der Text, den du nicht verstanden hast — Erklärung, Bewertung und Konsequenz.**

Was er sagen wollte: ein Rekord ist eine **Zeit über eine Distanz**, und es gibt zwei Wege, wie ein Lauf einen hält.

- **Der schnellste Abschnitt im Lauf.** Für 1, 5 und 10 km sucht Currimus die schnellsten so-und-so-viel Kilometer *am Stück* irgendwo innerhalb eines Laufs. Die schnellsten 5 km eines 12-km-Laufs zählen, der Lauf muss dort nicht enden. Das ist Standard (Strava nennt es „best efforts") und sinnvoll.
- **Der ganze Lauf, skaliert.** Läufe aus anderen Apps kommen ohne Kilometer-Splits an — nur eine Distanz und eine Dauer. Dann wird die Durchschnittspace des ganzen Laufs auf die Benchmark gerechnet: 12 km zu 5:00 /km gelten als 10 km in 50:00. Der Deckel liegt bei 2,5× der Benchmark, weshalb ein Marathon als Beleg für einen Halben zählt und nie als 1-km-Rekord.

**Ist das sinnvoll? Weitgehend ja, und zwar aus einem Grund, der im alten Text nicht stand:** die skalierte Lesart kann einen Läufer nur *unterschätzen*, nie schmeicheln. Die schnellsten 10 km innerhalb eines 12-km-Laufs sind immer mindestens so schnell wie dessen Durchschnitt. Sie ist also eine untere Schranke und kann einen echten Rekord nie verdrängen — es gewinnt ohnehin die schnellere der beiden Lesarten.

**Wo der Text zu viel behauptet hat, und das ist der echte Fund:** „fastest continuous stretch" stimmt nicht ganz. Gerechnet wird über die Kilometer-Splits, der Abschnitt beginnt und endet also auf einem Kilometermarker. Ein tatsächlich schnellerer Abschnitt, der zwischen zwei Markern liegt, ist ein paar Sekunden schneller als das, was hier steht. Feiner geht es mit den vorhandenen Daten nicht — aber die App darf das dann auch nicht verschweigen. Steht jetzt drin.

**Und was ich geändert habe:** der Absatz ist aus der Ansicht raus. Vier Sätze grauer Fließtext unter den Zeilen sind genau das, was du in CUR-36 #7 abgeschafft hast. Übrig bleibt eine Zeile („Records come from your runs automatically. No badges, no confetti.") plus ein Kicker „HOW A RECORD IS FOUND" mit ⓘ; die vollständige Herleitung steht im Sheet — mit beiden Lesarten, dem Kilometermarker-Vorbehalt, der Begründung des 2,5×-Deckels und dem Hinweis, dass Halbmarathon und Marathon gar keine Abschnitts-Lesart haben, weil dort der ganze Lauf der Versuch ist.

**Tests.** Fünf neue (228 iOS gesamt): kein Estimate für ein 10-K-Rennen, Estimate für den Marathon-Aufbau, Banner führt mit einem ersten Marathon, Banner wechselt am Folgetag auf den schnelleren 10er, und die drei Scroll-Tests. 12 UI-Tests, 27 watchOS-Tests, beide Ziele bauen, Referenzbilder neu aufgenommen.

#### Link to completed work
