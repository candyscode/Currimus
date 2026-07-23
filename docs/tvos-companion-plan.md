# tvOS Companion App — Implementation Plan

> **Status:** Design / planning only. No tvOS code exists yet.
> **Audience:** An engineer or AI agent implementing a tvOS target for Currimus.
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
- **Run detail:** stats, splits (`SplitBars`), zone strip, **route map** and
  **elevation** (`ElevationProfile`). MapKit is available on tvOS — the current
  iOS detail only draws a `RoutePath` placeholder (`MapCard`), so the TV can use
  either the same vector path or a real `Map`.

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

