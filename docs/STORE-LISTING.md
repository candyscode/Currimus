# App Store listing — draft

Paste-ready copy for App Store Connect, drawn from the app's own voice (the
first-launch screen is the pitch) and the features that actually ship in 1.0.
Everything here is editable — it is a starting point, not a decree. Character
limits are noted; App Store Connect enforces them.

---

## Name (max 30)

```
Currimus
```

## Subtitle (max 30)

```
Running, nothing else
```

Alternatives: `Your runs, and nothing else` · `Private running, done right`

## Promotional text (max 170 — editable any time without review)

```
No account, no ads, no tracking. Your Apple Watch records the run; your iPhone
shows what matters — pace, zones, splits, climb. Everything stays on your devices.
```

## Keywords (max 100, comma-separated, no spaces after commas)

```
run tracker,running,pace,heart rate,zones,trail,gpx,splits,marathon,pacer,elevation,cadence,watch
```

Notes: don't repeat the app name or the category ("Fitness") — they're indexed
already. Trim to fit 100 characters after any edits.

## Category

- Primary: **Health & Fitness**
- Secondary: (optional) Sports

## Description (max 4000)

```
Currimus is a running app with a single idea: show you the numbers that matter,
and nothing else. No account. No ads. No feed. No tracking, no data sales, no
spam. It stays out of the way so your running stays in front.

Your Apple Watch records the run. Your iPhone reads it back and shows you where
you stand. Runs sync to Apple Health — nothing else, nowhere else. The app makes
no network calls of any kind.

ON THE WATCH
— A clean live glance: time, distance, pace, and a heart-rate zone bar that
  shows where you are inside a zone, not just a number.
— Trail runs are measured honestly: climb, grade-adjusted pace, and a live
  elevation read, because uphill your pace lies.
— Pacer: set a target pace and distance and a simple gauge tells you fast or
  slow at a glance, with a finish forecast as you go.
— Kilometre alerts, a start countdown, and full always-on-display support so the
  screen stays readable with your wrist down without burning the battery.

ON THE iPHONE
— Home puts the one thing that matters up front: a race countdown when you have
  one, your week's volume when you don't.
— A log of every run, road and trail, with automatic session types you can
  correct.
— Progress that tells the truth: your average pace over the last twelve weeks,
  heart rate at your own steady pace (aerobic drift), grade-adjusted trail pace,
  and monthly volume.
— Records that appear on their own — 1K to marathon, longest run, most climb.
  No badges, no confetti.
— A target race with an honest prediction based on your own benchmark runs.
— Your recorded route on a real map, per-kilometre splits, and time in zones.
— Export every run as GPX or CSV, whenever you want, wherever you want it.

Currimus also reads the running workouts other apps saved to Apple Health, so
every total counts what you actually ran — not only what you recorded here.

PRIVACY
There is no account because there is nothing to sign in to. There are no
trackers and no third-party code. Your runs, heart rate and routes live in Apple
Health and in the app's own storage on your devices, and go nowhere else. The
privacy policy says the same thing the app does, because they are the same thing.

Currimus records on the Apple Watch and needs one paired to your iPhone.
Everything on the iPhone still reads your Apple Health runs without it.
```

## What's New — version 1.0 (max 4000)

```
The first release of Currimus.

Record runs, trail runs and paced runs on your Apple Watch; read them back on
your iPhone with pace trends, heart-rate zones, splits, elevation, records and a
target-race prediction. No account, no ads, no tracking — runs sync to Apple
Health and nowhere else.
```

---

## App Review notes (the box in App Store Connect — read this before writing it)

A reviewer without an Apple Watch will otherwise conclude the app does nothing,
so state plainly:

```
Recording happens on the Apple Watch, not the iPhone. The iPhone app reads and
analyses runs; it does not record them. To see a recording flow you need an
Apple Watch paired to the test device.

Starting a run requires Health permission: distance and heart rate both come
from the workout (HKLiveWorkoutBuilder), so without access there is nothing to
record — the app says so at the start rather than filing an empty run. Please
allow Health access when prompted on the watch.

The iPhone app reads existing running workouts from Apple Health and shows totals
and records from them, so it is usable on its own with a Health history present.

The app makes no network requests. There is no account, no login, and no server.
```

## Other App Store Connect answers (for consistency)

- **App Privacy**: Data Not Collected. Must agree with `Resources/PrivacyInfo.xcprivacy`
  and the privacy policy — all three currently say the same thing.
- **Age rating**: complete the questionnaire; the app is not directed at children
  and contains no objectionable content (expected 4+).
- **Export compliance**: already answered by `ITSAppUsesNonExemptEncryption = NO`
  in the build — no per-upload click.
- **Privacy Policy URL / Support URL**: from the hosted `docs/privacy.html` and
  `docs/support.html` (replace the `support@currimus.app` placeholder first).
- **Pricing**: (your call — free / paid / one-time.)
```
