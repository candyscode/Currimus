# tvOS Companion App — Implementation Plan

> **Status:** ✅ Implemented on branch `feat/tv-os`. This document is now the
> design record for the code that exists; see "Implementation notes" at the end
> for what was actually built and what still needs Xcode.
> **Audience:** An engineer or AI agent working on the tvOS target for Currimus.
> **Written against:** `main` @ commit `28314bc` (2026-07-21), after the
> `tech/architecture-hardening` work (PR #1) landed.
> **Language note:** This doc is in English to match the repository (README,
> source, commit messages are all English).

---

## Decisions (settled — build to these)

These were the open questions; the product owner has answered them. Build to
these; do not re-litigate.

1. **Data bridge → CloudKit.** Private CloudKit database. Requires iPhone +
   Apple TV on the same iCloud account (near-universal for Apple TV).
2. **Distribution → Universal Purchase.** iOS + tvOS ship as one App Store
   product with the **same bundle id** (`com.currimus.app`); one purchase covers
   both.
3. **TV scope → full log + detail.** Dashboard, complete log, records, **and**
   per-run detail with route map + elevation profile. This means GPS tracks /
   altitude series **must** be synced (as `CKAsset`), not just metadata.
4. **Imported runs → sync `allRuns`.** Sync the merged/deduped list so the TV's
   totals match the phone exactly (the TV has no HealthKit and cannot derive
   them itself).
5. **Deployment target → tvOS 26.** Matches the iOS 26 / watchOS 11 baseline.

---

## Context — why this document exists

Currimus is a running app: **the Apple Watch records, the iPhone reads** (log,
stats, settings). The goal is a third surface — an **Apple TV app** that shows a
user's running data on the big screen (weekly volume, records, recent runs,
run detail with route/elevation).

The naive assumption is that tvOS behaves like watchOS — a "companion" bundled
with the iOS app. **It does not.** A tvOS app is always a **standalone app**
with its own bundle id and its own App Store binary. The only companion-like
tie is **Universal Purchase** (shared App Store record so one purchase covers
iOS + tvOS), which is a store/signing concern, not a runtime data link.

The hard problem is therefore **data access**, and this is where the current
architecture blocks a naive port. Everything below flows from that.

---

## The blocker: Currimus has no cross-device data layer today

All run data lives **device-locally**. There is no server, no CloudKit, no
iCloud sync anywhere in the codebase.

| Data | Where it lives | Source |
|---|---|---|
| Recorded runs (metadata) | App-Group `UserDefaults` (`group.com.currimus.app`) | `Shared/AppDefaults.swift`, `RunStore.persist()` |
| GPS track + altitude series | Sidecar files in the App-Group container | `Shared/RunSampleStore.swift`, `RunStore.storeSamples` |
| Runs from other apps (Strava, Nike…) | **HealthKit** | `Shared/HealthImport.swift` |
| Watch → iPhone run handoff | **WatchConnectivity** (`transferUserInfo`) | `Shared/RunSync.swift` |
| iPhone → Watch settings | **WatchConnectivity** (`updateApplicationContext`) | `Shared/RunSync.swift` |
| Cross-device / cloud sync | **Does not exist** | — |

Why none of these reach an Apple TV:

- **App Groups do not sync across devices.** They share data between targets on
  the *same* device only. Apple TV is a separate physical device — it never
  sees `group.com.currimus.app`.
- **HealthKit does not exist on tvOS.** There is no framework to link against.
  The entire `importedRuns` pipeline (`HealthImport`, `HeartRateProfile`) is
  unavailable.
- **WatchConnectivity does not exist on tvOS.** `WCSession` is iOS/watchOS only.
  `Shared/RunSync.swift` imports `WatchConnectivity` unconditionally (line 2),
  so it **will not even compile** for a tvOS target as-is.

**Conclusion:** Unlike the watch (coupled to the phone via WatchConnectivity +
a shared App-Group container), a tvOS app can reach the run data through **none**
of the existing mechanisms. A **new synchronizing data layer** must be added
first. That is the bulk of this work; the tvOS UI is comparatively easy.

---

## Recommended approach: CloudKit as the bridge

CloudKit fits the app's "local-first, no backend" design — it is pure Apple
infrastructure (no server to run, no hosting cost), and it is the natural way to
move a user's private data between their own devices.

```
Watch ──WatchConnectivity──▶ iPhone ──CloudKit (private DB)──▶ Apple TV
  (unchanged)                (RunStore)   (NEW: RunCloudSync)   (tvOS: read-only)
```

- The iPhone becomes the **writer**: when a run is added (`RunStore.add`), it
  also writes a `CKRecord` into the user's **private CloudKit database**.
- The Apple TV is a **reader**: same iCloud account → same private DB. It never
  writes.
- The Apple Watch is **unchanged** — it keeps handing runs to the phone over
  WatchConnectivity; the phone remains the source of truth and the only writer.

### Why the private database (not shared/public)

Running data is personal. The private DB is scoped to the signed-in iCloud
account, so iPhone and Apple TV signed into the same account see the same data
with zero sharing UI. Apple TV is almost always signed into the household's
primary iCloud account, so this is the common case.

### Data mapping

`Run` (`Shared/Models.swift`) is already `Codable`. Two viable encodings:

1. **Field-per-column** `CKRecord` (`distanceKm`, `duration`, `avgHR`, `date`,
   `type`, `name`, `splits`, `zoneSeconds`, `climb/descent/highPoint`). Best for
   querying/sorting server-side (e.g. sort by `date`). Recommended for the run
   **list/metadata**.
2. **Blob** — JSON-encode the `Run` into a single `CKRecord` field. Simplest,
   mirrors how `RunStore` already persists (`JSONEncoder().encode(runs)`), but
   opaque to CloudKit queries.

Recommended: **field-per-column for the queryable metadata**, and store the
heavy **GPS route + altitude series as a `CKAsset`** (they already live as a
separate sidecar per run via `RunSampleStore` — mirror that split into CloudKit
so the TV downloads a route only when showing run detail). Use the run's
existing `UUID` (`Run.id`) as the `CKRecord.ID` recordName for stable identity
and idempotent upserts.

### Sync semantics

- **Backfill:** on first enable, push all existing `RunStore.runs` to CloudKit.
- **Incremental:** push each new run in `RunStore.add`.
- **Imported runs?** `importedRuns` come from HealthKit on the phone. Decide
  whether the TV should see them too. **Recommended: yes** — sync `allRuns`
  (the merged, deduped list `RunStore` already computes) so the TV's totals
  match the phone exactly. The TV cannot derive them itself (no HealthKit).
- **Deletions:** when `RunStore.deleteRuns` removes an owned run, delete its
  `CKRecord`. (Imported runs are not deletable locally — see `deleteRuns`.)
- **TV fetch:** query the private DB sorted by `date` desc on launch and on
  foreground; optionally subscribe (`CKQuerySubscription`) for push-driven
  refresh, though poll-on-foreground is enough for a first version.

---

## What is reusable (a lot)

Most of `Shared/` is platform-neutral (pure SwiftUI/Foundation) and can be
compiled straight into the tvOS target:

| File | Reusable on tvOS? | Notes |
|---|---|---|
| `Shared/Models.swift` | ✅ Yes | `Run`, `Race`, `HRZones`, `RecordEntry`, `Format`, enums. Pure value types. |
| `Shared/RunMetrics.swift` | ✅ Yes | Pure arithmetic of a run. |
| `Shared/RunAnalytics.swift` | ✅ Yes | PRs, predictions, fastest-window. Pure. |
| `Shared/WeekSnapshot.swift` | ✅ Yes | Week aggregation. Pure. |
| `Shared/RunSampleStore.swift` | ⚠️ Adapt | File I/O against the App-Group container. On TV, samples arrive via CloudKit `CKAsset`, not the shared group — repoint or bypass. |
| `Shared/RunPalette.swift`, `Theme.swift`, `SharedComponents.swift` | ✅ Mostly | `Theme` is pure `Color`. `SharedComponents` has `#if os(watchOS)` branches — add tvOS branches or fall through to the default. |
| `Shared/FontLoader.swift` | ✅ Yes | `CoreText` `CTFontManagerRegisterFontsForURL` — cross-platform. Bundle the `Fonts/` into the tvOS target's resources. |
| `Shared/RunStore.swift` | ⚠️ Split | The **aggregation logic** (`weekKm`, `records`, `monthlyTotals`, `last4Weeks`, `benchmarkHolders`, `allRuns`) is pure and gold. The **persistence/sync** (App-Group defaults, HealthKit, WatchConnectivity) must be swapped for a CloudKit-backed read path. See "RunStore on tvOS" below. |
| `Shared/RunSync.swift` | ❌ No | `import WatchConnectivity` — does not exist on tvOS. Must be guarded (see below). |
| `Shared/HealthImport.swift`, `HeartRateProfile.swift` | ❌ No | `import HealthKit` — does not exist on tvOS. Must be guarded. |

### iOS UI as a reference, not a drop-in

`iOS/Charts.swift` shapes (`WeekBars`, `MonthBars`, `WeekVolumeBars`,
`TrendChart`, `SplitBars`, `ElevationProfile`, `RoutePath`, `GridPattern`) are
almost pure SwiftUI and translate well to the 10-foot UI — they are the best
starting point for the TV dashboard's charts. But the screen layouts
(`iOS/HomeView.swift`, `LogView`, `ProgressTabView`, `Scaffold`, `Glass.swift`)
are tuned for iPhone portrait, Liquid Glass tab bars, `NavigationStack` push
routing, and Dynamic Type. **tvOS needs its own layouts** built around:

- the **focus engine** (remote-driven focus, `.focusable`, focus effects),
- a **landscape 10-foot layout** with large type and generous safe-area insets
  (tvOS overscan margins),
- **no HealthKit permission flow, no settings authoring** (the TV is read-only;
  settings remain owned by the phone).

---

## Concrete work items

### 1. Make `Shared/` compile on tvOS (platform guards)

- `Shared/RunSync.swift`: wrap the whole file (or at least the `import
  WatchConnectivity` and the `WCSession` usage) in `#if canImport(WatchConnectivity)`.
  Provide a no-op or absent `RunSync` on tvOS.
- `Shared/HealthImport.swift`, `Shared/HeartRateProfile.swift`: wrap in
  `#if canImport(HealthKit)`.
- `Shared/RunStore.swift`: the HealthKit block is **already** `#if canImport(HealthKit)`
  (good). The `pushSettings()`/`RunSync` calls are `#if os(iOS)`/`#if os(watchOS)`
  — verify nothing WatchConnectivity-related is reachable on tvOS. The `RunSync.shared`
  references in `init` need a tvOS-safe path.
- Audit `SharedComponents.swift` `#if os(watchOS)` branches for a sensible tvOS
  fallback.

### 2. Add `RunCloudSync` (new, in `Shared/`)

- `#if canImport(CloudKit)` (available on iOS, tvOS, macOS, watchOS).
- iOS side: `upsert(_ run: Run)`, `delete(id: UUID)`, `backfill(_ runs: [Run])`.
  Called from `RunStore.add` / `deleteRuns` / a one-time backfill on first enable.
- tvOS side: `fetchRuns() async -> [Run]`, optional `CKQuerySubscription`.
- Map `Run` ↔ `CKRecord` (metadata fields + `CKAsset` for route/altitude).
- Handle the standard CloudKit realities: account-status check
  (`CKContainer.accountStatus`), not-signed-in state, network errors, and
  partial failures on batch ops.

### 3. tvOS `RunStore` read path

Rather than fork `RunStore`, factor its **aggregates** so they operate on an
injected `[Run]`. Two options:

- **Minimal:** give the tvOS target a lightweight store that holds
  `@Published var runs: [Run]` filled from `RunCloudSync.fetchRuns()`, and reuse
  the aggregate computed-properties by moving them onto an extension over a
  protocol (e.g. `RunAggregating` with `var allRuns: [Run]`). The pure aggregate
  methods in `RunStore` (lines ~357–555) depend only on `allRuns` + `Calendar`.
- **Pragmatic:** compile `RunStore` into the tvOS target with persistence/sync
  stubbed (no App-Group writes, no HealthKit, no WatchConnectivity), and feed it
  runs from CloudKit. Faster to stand up; carries dead code.

Recommended: the **protocol-extraction** route for a clean read-only TV store.

### 4. New tvOS target in `project.yml` (XcodeGen)

The project is generated — **edit `project.yml`, then run `xcodegen generate`**.
Do **not** hand-edit `Currimus.xcodeproj/project.pbxproj`.

Add a target roughly:

```yaml
options:
  deploymentTarget:
    iOS: "26.0"
    watchOS: "11.0"
    tvOS: "26.0"          # add

targets:
  CurrimusTV:
    type: application
    platform: tvOS
    sources:
      - TV                # new folder: tvOS-only views + store
      - Shared            # reused, now tvOS-safe after step 1
      - path: Fonts
        buildPhase: resources
      - path: Resources/Localizable.xcstrings
        buildPhase: resources
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.currimus.app        # Universal Purchase: same as iOS
        INFOPLIST_KEY_CFBundleDisplayName: Currimus
    entitlements:
      path: TV/CurrimusTV.entitlements
      properties:
        com.apple.developer.icloud-container-identifiers: [iCloud.com.currimus.app]
        com.apple.developer.icloud-services: [CloudKit]
        # NO healthkit, NO app-groups needed on TV (no shared local container to read)
```

> **Bundle id / Universal Purchase:** to ship iOS + tvOS as one App Store
> product, both use the **same** bundle id `com.currimus.app` with
> `TARGETED_DEVICE_FAMILY` distinguishing them, OR distinct records if you don't
> want Universal Purchase. Confirm with the App Store Connect setup you want
> (see Open Questions).

### 5. Add CloudKit to the **iOS** target too

The iOS target currently has only HealthKit + App-Group entitlements
(`iOS/Currimus.entitlements`). Add:

```
com.apple.developer.icloud-container-identifiers: [iCloud.com.currimus.app]
com.apple.developer.icloud-services: [CloudKit]
```

so the phone can **write** to the same container the TV reads.

### 6. tvOS UI (new `TV/` folder)

SwiftUI, dark theme, `Theme.signal` accent — same design language. Screens:

- **Dashboard / Home:** this-week volume (`WeekBars` adapted), week total + goal
  %, last run summary, recent runs. (Mirror `iOS/HomeView.swift` content, TV
  layout.)
- **Log:** runs grouped by month (`RunStore.runsByMonth`), focusable rows.
- **Progress / Records:** monthly bars (`MonthBars`), records
  (`RunStore.records`), 4-week readiness (`WeekVolumeBars`), trend
  (`TrendChart`).
- **Run detail:** stats, splits (`SplitBars`), zone strip, **route** and
  **elevation** (`ElevationProfile`). MapKit is available on tvOS, but the TV
  draws the vector track rather than a map — see `TV/RouteShapes.swift`.

Build for the **focus engine** and 10-foot readability; do not reuse the iPhone
`TabView`/`NavigationStack` scaffolding verbatim.

---

## Alternatives considered

- **Local network (Bonjour + Network.framework / MultipeerConnectivity):** phone
  streams to the TV only when both are on the same Wi-Fi. Avoids iCloud, but no
  offline access, more fragile pairing, and more code. Only worth it if iCloud
  is explicitly undesirable.
- **Custom backend / REST API:** most flexible, but breaks the serverless design
  and is far more work (hosting, auth, ops). Not recommended.

CloudKit is the clear first choice.

---

## Verification / testing

1. **Compile guards:** after step 1, `xcodegen generate` and build the existing
   iOS + watchOS targets — confirm the platform guards didn't break them.
2. **iOS write path:** on device/simulator signed into an iCloud account, record
   or add a run; confirm a `CKRecord` appears in the **CloudKit Console**
   (private DB) for that account.
3. **Backfill:** enable sync with an existing log; confirm all runs land in
   CloudKit.
4. **tvOS read path:** run `CurrimusTV` in the tvOS simulator/device signed into
   the **same** iCloud account; confirm the run list, weekly totals, and records
   **match the phone** (this validates that `allRuns` — including imported runs —
   was synced, since the TV has no HealthKit).
5. **Run detail assets:** open a run with a GPS route on the TV; confirm the
   route/elevation `CKAsset` downloads and renders.
6. **Unit tests:** the pure aggregate logic reused from `RunStore`/`RunMetrics`/
   `RunAnalytics` is already covered by `Tests/`. If aggregates are extracted to
   a protocol (step 3), point the existing tests at the protocol so coverage
   carries over. Add a `RunCloudSync` round-trip test (`Run` → `CKRecord` → `Run`
   equality) — note `CKRecord` needs a real/CKMock container, so this may be an
   integration test rather than a unit test.
7. **No-account / offline:** confirm the TV shows a sensible empty/error state
   when not signed into iCloud or offline (CloudKit `accountStatus` +
   network-error handling).

---

## Decisions

All prior open questions are settled — see **Decisions (settled)** near the top
of this document. In short: CloudKit private DB · Universal Purchase (shared
bundle id) · full log + per-run detail (route/elevation synced as `CKAsset`) ·
sync `allRuns` (incl. imported) · tvOS 26. Build to those.

---

## Key file references (for the implementing agent)

- Data model: `Shared/Models.swift` (`Run` at line 77, `Format` at 370)
- Aggregates to reuse: `Shared/RunStore.swift` lines ~357–555
- Persistence keys & App-Group: `Shared/AppDefaults.swift`
- Sample (route/altitude) storage split: `Shared/RunSampleStore.swift`,
  `RunStore.samples(for:)` / `hydrated(_:)`
- Must-guard for tvOS: `Shared/RunSync.swift` (WatchConnectivity),
  `Shared/HealthImport.swift` + `Shared/HeartRateProfile.swift` (HealthKit)
- Chart shapes to port: `iOS/Charts.swift`
- iOS screen layouts (reference only): `iOS/HomeView.swift`, `iOS/CurrimusApp.swift`
- Project generation: `project.yml` + `xcodegen generate` (never hand-edit the
  `.pbxproj`)

---

## Implementation notes (what was actually built)

Built on branch `feat/tv-os`. The approach deviated from the plan in one useful
way: instead of extracting `RunStore`'s aggregates into a protocol, the **whole
`RunStore` is compiled into the tvOS target unchanged** and gets one small,
tvOS-only injection point. The TV therefore reuses the phone's records / week /
month math byte-for-byte, and the change to shared code is purely additive and
platform-guarded — lowest risk for the shipping iOS and watchOS apps.

**New files**
- `Shared/RunCloudSync.swift` — the CloudKit bridge (`#if canImport(CloudKit)`).
  `upsert` / `delete` / `backfill` (phone) and `fetchRuns` / `fetchSamples` /
  `accountState` (TV). `Run` ↔ `CKRecord` maps the metadata as a JSON payload
  blob keyed on `Run.id`, samples as a `CKAsset`. **List fetches use
  `desiredKeys` to omit the sample asset** — routes/altitude download only when
  a detail screen calls `fetchSamples(for:)`. `fetchRuns` **throws** on failure
  (never returns `[]`), so a network blip can't wipe the local cache.
  `accountState` distinguishes signed-out from transient statuses. Async
  CKDatabase APIs, cursor paging, client-side sort (no custom index needed),
  cached `CKContainer`, `serverRecordChanged` upsert recovery, `unknownItem`-
  tolerant delete.
- `TV/RouteShapes.swift` — `RouteShape` + `GridShape`, the drawn-track geometry
  behind `TVRouteCard`. TV-only: the iPhone's `MapCard` draws a real dark
  `MKMapView`, which it can pan and zoom by touch. MapKit exists on tvOS, so the
  TV could too — it deliberately does not: there is nothing to explore with a
  Siri Remote at four metres, and the drawn track needs no network.
- `TV/TVApp.swift` — `@main`, tab shell (Home · Log · Progress), loading /
  signed-out / empty states, quiet refresh spinner overlay.
- `TV/TVSync.swift` — `@MainActor` loading-state driver around `RunCloudSync` +
  `RunStore.replaceAllFromCloud`. Failure is non-destructive: a transient
  account status or fetch error leaves the on-screen/cached log untouched.
- `TV/TVComponents.swift` — 10-foot chart/row components (own copies, sized for
  a TV; the iOS `Charts.swift` shapes are iPhone-point-sized and iOS-target).
  Also `scrollFocusable()`: makes read-only sections focusable so the Siri
  Remote can scroll a text-only screen (tvOS only scrolls toward focusable
  content — without this, anything below the first screenful of the dashboard /
  progress screens would be unreachable with the remote).
- `TV/TVDashboardView.swift`, `TVLogView.swift`, `TVRunDetailView.swift`
  (fetches its route/altitude on `.task`), `TVProgressView.swift` — the screens,
  focus-engine driven, landscape. The dashboard and progress panels carry
  `scrollFocusable()` so they scroll with the remote.
- `TV/CurrimusTV.entitlements` — CloudKit only.

The TV components carry VoiceOver `accessibilityLabel`/`Value` mirroring the
iPhone charts (tvOS has VoiceOver too), each screen has a `#Preview` seeded with
`RunStore(seeded: true)` so the 10-foot layout renders in the Xcode canvas
without CloudKit or a device, and `TVStatusView` copy is `LocalizedStringKey`
so it extracts into `Localizable.xcstrings` like the rest of the app.

**Changed files**
- `Shared/RunSync.swift` — WatchConnectivity guarded; tvOS gets a no-op `RunSync`
  stub with the identical public API so `RunStore` compiles untouched.
- `Shared/HealthImport.swift` — pure `merging(_:with:)` hoisted out of the
  HealthKit guard (tvOS `RunStore` still dedupes); everything `HK*` guarded.
- `Shared/HeartRateProfile.swift` — whole file HealthKit-guarded.
- `Shared/AppDefaults.swift` — tvOS reads `.standard` instead of the app-group
  suite. The TV has no widget to share with and no app-group entitlement, so the
  group suite resolved to a container it cannot write and the offline cache of
  the mirrored log never survived a launch.
- `Shared/RunStore.swift` — tvOS-only `replaceAllFromCloud(_:)` (rebuilds the
  own/imported split from `Run.imported`, repopulates `RunSampleStore` so the
  detail map/elevation work); iOS-only `backfillCloud()` + `cloudUpsert` /
  `cloudDelete` / `cloudSyncImportedDelta` hooked into `add` / `deleteRuns` /
  `refreshImportedRuns` via detached tasks; no-op stubs elsewhere.
- `iOS/CurrimusApp.swift` — one-time `backfillCloudIfNeeded()`; the store owns
  the flag, and only sets it once the backfill has actually landed.
- `iOS/Currimus.entitlements` — added CloudKit container.
- `TV/Assets.xcassets` — the layered tvOS icon and both Top Shelf banners,
  rendered by `Assets/make_tv_icon.swift` from the same mark as the phone icon.
- `project.yml` — `tvOS: "26.0"` deployment target + `CurrimusTV` target and
  scheme (sources `TV` + `Shared`, Fonts + xcstrings + privacy manifest, shared
  bundle id for Universal Purchase, CloudKit entitlement, brand-asset icon).

**Verified in Xcode / the simulator** *(merge of `main` into this branch)*
- All four targets build (Xcode 26.5, iOS 26.5 / watchOS 26.5 / tvOS 26.5 SDKs)
  and the 97-case suite passes.
- The TV app runs on an Apple TV 4K (3rd generation) simulator: dashboard, log,
  progress and both run details render, and the icon shows on the home screen.
  `-demo 1` (seeded store, no CloudKit) and `-tab` / `-push` routing make each
  screen reachable without an iCloud account, which the tvOS simulator has not.
- Three defects the branch could not have seen without a build: `CKContainer`
  traps in a bundle with no iCloud entitlement, which crashed all seven
  `RunStoreTests` (the store now takes an explicit `mirrorsToCloud`); the
  `cloudBackfilled` flag was set before the backfill succeeded, so one offline
  first launch hid the whole history from the TV forever; and the app-group
  defaults suite is not writable on tvOS.

**Still open**
1. **CloudKit dashboard:** the container `iCloud.com.currimus.app` must exist and
   the `Run` record type's schema is created on first write (development
   environment) — deploy the schema to production before release. The reader
   relies only on the default `recordName` queryable index; no custom index is
   required. *Not exercised here: the simulator has no iCloud account, so every
   run against real CloudKit is still untested.*
2. **Signing:** `CurrimusTV` inherits `DEVELOPMENT_TEAM` from `settings.base`,
   but CloudKit needs a real provisioning profile, same as HealthKit does for
   the phone and watch. Simulator builds do not prove this.
3. **End-to-end test:** run the iOS app signed into iCloud, confirm records
   appear in the CloudKit Console, then run `CurrimusTV` on the same account and
   confirm the log, totals and a run's route/elevation match the phone.
4. **Focus / remote navigation:** the dashboard and progress panels carry
   `scrollFocusable()` so the remote can scroll them, and the log rows are
   `NavigationLink`s. This was *not* driven with a remote — automating the
   simulator's arrow keys needs macOS accessibility permission that was not
   granted — so confirm by hand that focus moves sensibly between panels and
   that nothing below the first screenful is stranded.
5. **10-foot legibility:** the type sizes are still guesses; check them from
   across a room. The `.tabItem` tab bar is functional but generic — it does not
   use the iPhone's design glyphs.
6. **UI snapshots:** `scripts/ui-snapshot.sh` has no tvOS routes yet. The debug
   routing added here (`-demo 1 -tab … -push …`) is what a `tv-routes.txt` would
   need.
7. **String catalogue:** the TV's copy ("Sign in to iCloud", "Can't reach
   iCloud", …) is `LocalizedStringKey`, but `Resources/Localizable.xcstrings`
   does not list it yet — `xcodebuild` extracts into the build directory and
   only the IDE writes the source catalogue back. Open the project in Xcode and
   build `CurrimusTV` once to fold the keys in. Harmless until then: the
   catalogue has no translations at all yet, so every key falls back to its
   English source either way.
8. **Optional:** a `CKQuerySubscription` for push-driven refresh — today the TV
   polls on foreground, which is enough for a first version.

