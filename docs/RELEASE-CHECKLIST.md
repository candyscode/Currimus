# Release checklist

Everything in the repo that could be automated has been. What is left needs an
Apple account, a browser, a credit card or a real wrist — so it is written down
rather than done.

Ordered so that nothing blocks on something further down.

---

## 1. Before anything else

- [ ] **Apple Developer Program membership is active** (99 €/year). Team
      `88U4UH4ASG` is already in `project.yml`; confirm it is current and
      whether the account is **Individual** or **Organization**. That decides
      the seller name buyers see, an Organization needs a D-U-N-S number, and
      it cannot be changed later without support.
- [ ] **Register the identifiers** in the developer portal, all three plus the
      group:
      - `com.currimus.app`
      - `com.currimus.app.watchkitapp`
      - `com.currimus.app.watchkitapp.widgets`
      - App Group `group.com.currimus.app`
- [ ] Enable **HealthKit** and **App Groups** on the two app IDs. HealthKit
      cannot use a wildcard profile — without this, device builds fail on the
      entitlement.
- [ ] **Reserve the name "Currimus"** in App Store Connect. Names are
      first-come; check for a trademark collision at the same time.

## 2. The one thing that has to be tested on hardware

- [ ] **A real run, at least 30 minutes, wrist down for most of it.** This is
      the only way to confirm A1: GPS now keeps recording in the background
      (`allowsBackgroundLocationUpdates` plus the `location` background mode).
      The simulator cannot show it, and a run cannot be repeated. Check
      afterwards that the route covers the whole run and that the climb figure
      is plausible, not just the first few minutes.
- [ ] Confirm the **route map** looks right on a device. The simulator renders
      a flat vector fallback and ignores tile styling, so the dark map has
      never actually been seen (B1).
- [ ] Pause mid-run, resume, finish — then **export the GPX** and check the
      timestamps span the real elapsed time including the pause (A11).
- [ ] Deny location at the start of a run and confirm the run still records
      distance, pace and zones, and says what it lost.

## 3. Hosting the two required URLs

- [ ] Publish `docs/privacy.html` and `docs/support.html` — see
      `docs/README.md`. GitHub Pages from `/docs` is two clicks.
- [ ] **Replace the placeholder `support@currimus.app`** with an address that
      receives mail. App Review opens the support page.
- [ ] Both URLs must resolve *before* submitting.

## 4. App Store Connect

- [ ] Create the app record; bundle ID `com.currimus.app`.
- [ ] **App Privacy**: answer **Data Not Collected**. This has to agree with
      `Resources/PrivacyInfo.xcprivacy` and with the privacy policy — all three
      currently say the same thing, and they must be changed together if that
      ever stops being true.
- [ ] Privacy Policy URL and Support URL from step 3.
- [ ] Category: Health & Fitness.
- [ ] **Age rating**: the questionnaire is short, but note the app is not
      directed at children.
- [ ] Description, keywords, promotional text. The app's own copy is the best
      source — the first-launch screen is already the pitch.
- [ ] **Screenshots.** The DEBUG routes exist for exactly this; see the routing
      section in the README. iPhone 6.9" and 6.5" are required, plus watch.
      Useful ones: `-demo 1` alone (Home), `-tab log`, `-tab progress`,
      `-push detailRoad`, `-push records`, and on the watch `-screen run`,
      `-screen trail`, `-screen pacer-run`.
- [ ] **Review notes**: say plainly that recording happens on the Apple Watch
      and needs a paired device, that Health permission is required for a run
      to start, and why (distance and heart rate both come from the workout
      builder). A reviewer without a watch will otherwise conclude the app does
      nothing.
- [ ] Export compliance is answered by the Info.plist key (C4) — no click
      needed per build.

## 5. First upload

- [ ] `xcodebuild archive` then **Validate** in the Organizer before
      distributing. This has never been run, and validation is where
      ITMS errors surface — the privacy manifest, icon sizes, and the
      iOS/watch version match are all checked there.
- [ ] Ship to **TestFlight** and put it on a real wrist for a week. Everything
      in section 2 is easier to catch there than in review.

## 6. Decisions still open

- [ ] **Deployment target.** iOS 26 excludes every phone that has not updated.
      That was the deliberate choice for 1.0 (the Liquid Glass tab bar), but it
      is worth revisiting with actual adoption numbers before launch, not
      after.
- [ ] **German.** The string catalogue is wired up and extracts cleanly, but
      English is the only language in it. German strings run ~30 % longer and
      the watch layouts are measured to the half point, so this is a real
      piece of work rather than a translation pass.
- [ ] **Crash reports.** There is no crash reporting, deliberately — it is what
      lets the privacy policy make the claim it makes. Xcode Organizer will
      still show crashes from users who opted into sharing with developers.
      Adding anything more means editing the privacy policy, the privacy
      manifest and the App Privacy answers in the same change.
