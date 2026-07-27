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
[X] Open
[ ] WIP
[ ] Done

iOS App Run Detail Ansicht: Stelle die Zeit in den Pulszonen nicht mehr als einen einzelnen horizontalen Indicator mit prozentualen Anteilen der Zeit in den Pulszonen, sondern anstelle das als fünf horizontale Balken untereinander dar, wo man dann Zone 1 bis 5 untereinander aufgeschlüsselt sieht. Auf der Apple Watch gibt es ja auch diesen einen Pulszonen Übersichts-Balken (den wir auf iOS ersetzen). Auf der Apple Watch soll er bleiben. Dann bezüglich der Splits, die Verbrauchen aktuell bei langen Runs sehr viel Platz. (Halbmarathon = mind. 21 Balken untereinander). Dementsprechend überleg dir für die Splits eine Möglichkeit, nur das Allerwichtigste bezüglich den Splits des Runs anzuzeigen, also vielleicht irgendwie durchschnittliche Split-Zeit und schnellste Split-Zeit oder so (deine Entscheidung, was für einen Läufer halt sinnvoll ist). Und das Ganze als Button, wo man dann drauf tippen kann und dann bekommt man die Anzeige mit den ganzen Splits, die wir aktuell schon haben. Einfach, dass wir im Run Detail View weniger Platz verschenken. Achte dabei darauf, dass die UI-Changes ins Look & Feel der App und zum Design System passen.

### CUR-4: Remove feature in run mode to  change pace color to orange

[ ] In Specification
[X] Open
[ ] WIP
[ ] Done

Apple Watch: Im Run-Modus wird die Pace, die dort angezeigt wird, manchmal rot. Dieses Feature versteht man nicht als Kunde. Bitte ausbauen, die Pace soll einfach immer weiß angezeigt werden.

### CUR-5: Show heart rate zone indicator also when user is not looking

[ ] In Specification
[X] Open
[ ] WIP
[ ] Done 
Nur Apple Watch: Im abgedunkelten Modus (isLuminanceReduced), soll bitte weiterhin die Pulszonenanzeige hell bleiben und auch der Indicator (weiße Nadel) soll weiter angezeigt werden. 

### CUR-6: Vibration-based heart rate zone indication

[ ] In Specification
[X] Open
[ ] WIP
[ ] Done

Wir bauen ein Feature ein, mit dem man ohne auf die Watch zu schauen in der entsprechenden Puls zurück bleiben kann. Und zwar kann man das in den Einstellungen der App in iOS einschalten und sagen, man möchte Vibrationshinweise für eine Pulszone. Und dann kann man auswählen, welche Pulszone man haben möchte, an die man erinnert wird, wenn man dabei ist, sie zu verlassen. Zum Beispiel Zone 2. Achte dabei darauf, dass die UI-Changes ins Look & Feel der App und zum Design System passen. 
Und dann läuft es wie folgend: Wenn man noch innerhalb der Zone 2 ist, aber in den unteren 15%, dann gibt es einen Vibrationshinweis der schnell hintereinander pulsiert, um dem Nutzer zu sagen: lauf etwas schneller. Das Vibrationsmuster läuft dauerhaft, solange er in dieser 15% Scheibe ist. 

Und wenn man den oberen 15% ist, wird wieder ein Vibrationsmuster abgespielt.  Diesmal aber mit langsameren Vibrationspulsen, um dem Nutzer zu sagen: lauf etwas langsamer.

Das soll ihm dann helfen, auch ohne auf die Uhr zu schauen, immer zu wissen, wo er sich innerhalb der Pulszone befindet 

Und wenn er die Pulszone verlässt (z.B. er möchte in Zone 2 bleiben und jetzt in Zone 3 ist) dann gibt's eine Dauer Vibration für 3 Sekunden und eine Full-Screen Display-Warnung ähnlich wie die Split-Anzeige (in die Richtung: "Du bist jetzt in Zone 3, werde langsamer").

Entferne alle Tonsignale, die die Apple Watch von sich gibt. Da haben wir aktuell so einen Bimmelton. Wir arbeiten ab sofort nur noch mit Vibrationen. 

### CUR-7: Show progress over pace in heart rate zone 2

[ ] In Specification
[X] Open
[ ] WIP
[ ] Done

As a runner, I want to track my progress on my pace while running in zone 2. So additional to the graph for avg. pace in the last 12 months, which we already have, I want another graph showing the avg. pace but only the paces are counted which were achieved while running in heart rate zone 2. For both of those graphs also runs from other running apps stored in Apple Health shall be taken into account. Make sure the UI changes fit into the look and feel of the app and the design system. Also make sure, that the two graphs stacked over each other in the progress tab look nice. If they don't, you are free to redesign the progress view.

### CUR-8: Show hints to improve running style in run detail view

[ ] In Specification
[X] Open
[ ] WIP
[ ] Done

This, for now, only applies to the Run and Pacer mode, not the trailrun mode (so all modes which track more or less horizontal runs not on a mountain). Create a section in the run detail view that shows hints to the user on how to improve next time. If there is nothing to improve, the section is not shown. For now, there is only one hint to be shown. The app shall tell the user when the cadence (steps per minute) is too slow for the avg. pace he had during this run. Find the ideal cadences yourself (do an internet research). The hint shall be like "Good work! To further improve your running style and to save your joints try to do more and smaller steps. Try to think you are running on a slippery surface like ice, this may help" (of cource find a better wording!)

In the future, we will include more hint types and might even integrate AI-generated hints, so make the UI hint section extensible. Make sure the UI changes fit into the look and feel of the app and the design system.

Also, show the avg. cadence also in run detail view, regardless if there is a hint or not. 

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
[X] Open
[ ] WIP
[ ] Done

IMPORTANT: For now, please do NOT implement anything but include the implementation plan in the agent comments below. I will review the proposal and then give you the ok, to start implementing.

Currently, we loose a not of customers which do not have the iOS version that introduced liquid glass. Create a fall-back version of the liquid glass ui that enables the minimum iOS version of Currimus to be much lower than currently. The look and feel shall be very close to the liquid glass ui we have right now. Of course, this change also applies to the Apple Watch part of the app.

Choose a sensible minimum iOS and watchOS target that is a good tradeoff between user base and still modern enough UI framework to have a good / similar match to the current UI.

### CUR-12: iOS Widgets
 [X] In Specification
[ ] Open
[ ] WIP
[ ] Done

To be designed by Claude Design.

### CUR-13: Optimize for smaller Apple Watches
 [ ] In Specification
[X] Open
[ ] WIP
[ ] Done

IMPORTANT: For now, please do NOT implement anything but include the implementation plan in the agent comments below. I will review the proposal and then give you the ok, to start implementing.

Currently, we are very focussed on Apple Watch Ultra screen sizes. Make an evaluation on how the app looks on medium and small sized Apple Watches and make improvement suggestions. 

The main customer base uses Apple Watch Ultras however, so this is the focus. 

The UI must not change at all to what it currently looks like on Apple Watch Ultra, but should simply improve on smaller Watches.

### CUR-14: Hiking mode
 [X] In Specification
[ ] Open
[ ] WIP
[ ] Done

Maybe based on trail run mode but with different metrics? How to exclude from progress page? How to make this clear in the UI?


