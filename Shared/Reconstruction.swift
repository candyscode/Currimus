import Foundation

/// Everything Apple Health can put back into a run that the workout's own
/// summary does not carry.
///
/// This exists because adding one of these fields used to be five changes —
/// the sidecar file, its initialiser, the write-back after a fetch, the merge
/// onto a run, and the carry across a refresh — and twice the fifth was
/// missed, so a rebuilt value survived until the next time the app came to the
/// foreground and then quietly vanished. One type, one place that applies it,
/// one place that stores it.
struct Reconstruction: Codable, Equatable {
    /// Seconds per zone, rebuilt from the heart-rate trace.
    var zoneSeconds: [TimeInterval]?
    /// Distance per zone, from that trace paired with the distance over time.
    var zoneDistanceKm: [Double]?
    /// Per-kilometre splits recovered the same way.
    var splits: [TimeInterval]?
    /// Flat-equivalent pace from the run's own gradients.
    var gradeAdjustedSecPerKm: Double?
    /// The GPS track, which the log itself never holds.
    var route: [Coordinate]?

    var isEmpty: Bool {
        zoneSeconds == nil && zoneDistanceKm == nil && splits == nil
            && gradeAdjustedSecPerKm == nil && (route?.isEmpty ?? true)
    }

    /// What a run already carries, so it can be handed on across a refresh
    /// that replaces the run wholesale.
    init(of run: Run) {
        zoneSeconds = run.zoneSeconds.reduce(0, +) >= 1 ? run.zoneSeconds : nil
        zoneDistanceKm = run.zoneDistanceKm
        splits = run.splits.isEmpty ? nil : run.splits
        gradeAdjustedSecPerKm = run.gradeAdjustedSecPerKm
        route = run.route
    }

    init(zoneSeconds: [TimeInterval]? = nil, zoneDistanceKm: [Double]? = nil,
         splits: [TimeInterval]? = nil, gradeAdjustedSecPerKm: Double? = nil,
         route: [Coordinate]? = nil) {
        self.zoneSeconds = zoneSeconds
        self.zoneDistanceKm = zoneDistanceKm
        self.splits = splits
        self.gradeAdjustedSecPerKm = gradeAdjustedSecPerKm
        self.route = route
    }

    /// The run with this put back.
    ///
    /// The run always wins where it measured something itself: a recording
    /// Currimus made knows its own zones and splits better than anything
    /// reassembled afterwards. This only ever fills gaps.
    func applied(to run: Run) -> Run {
        var copy = run
        if run.zoneSeconds.reduce(0, +) < 1, let zoneSeconds, zoneSeconds.count == 5 {
            copy.zoneSeconds = zoneSeconds
        }
        if run.zoneDistanceKm == nil, let zoneDistanceKm, zoneDistanceKm.count == 5 {
            copy.zoneDistanceKm = zoneDistanceKm
        }
        if run.splits.isEmpty, let splits, !splits.isEmpty {
            copy.splits = splits
        }
        copy.gradeAdjustedSecPerKm = run.gradeAdjustedSecPerKm ?? gradeAdjustedSecPerKm
        copy.route = run.route ?? route
        return copy
    }
}

/// The bookkeeping behind rebuilding runs out of Health: who has been asked,
/// who is finished with, and what is still outstanding.
///
/// It used to be three predicates and two sets spread across `RunStore`, each
/// read by a different caller — the background fill, the on-demand hydration
/// and the Settings count — and four bugs in three days came out of exactly
/// that: one condition living in two places, changed in one. All three
/// questions are answered here now, so the answers cannot disagree.
struct HealthRebuild: Equatable {
    /// Asked in this session. Background work does not ask twice.
    private var asked: Set<UUID> = []
    /// Health answered in full and the run is still short of something — a
    /// route with no heart-rate trace beside it, or no route at all to take a
    /// gradient from. No later attempt can do better, so these stop being
    /// offered rather than sitting in the count for ever.
    private var settled: Set<UUID> = []

    /// Whether Health could still add anything to this run.
    static func canGain(_ run: Run) -> Bool {
        if run.zoneDistanceKm == nil { return true }
        // A gradient needs a track, and a treadmill run has none by
        // definition — no point asking Health to confirm it.
        return run.gradeAdjustedSecPerKm == nil && !run.isTreadmill
    }

    /// Everything still worth a rebuild — what the Settings row counts.
    func outstanding(in runs: [Run]) -> [Run] {
        runs.filter { Self.canGain($0) && !settled.contains($0.id) }
    }

    /// The next few to fetch in the background, newest first.
    func next(from runs: [Run], limit: Int) -> [Run] {
        outstanding(in: runs)
            .filter { !asked.contains($0.id) }
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .map { $0 }
    }

    /// Whether to put the question at all, for a single run.
    func shouldAsk(_ run: Run) -> Bool {
        Self.canGain(run) && !settled.contains(run.id) && !asked.contains(run.id)
    }

    mutating func asking(_ id: UUID) { asked.insert(id) }

    /// Health could not answer — the device may be locked, or access not yet
    /// granted. That is not an attempt: something has to try again.
    mutating func couldNotAsk(_ id: UUID) { asked.remove(id) }

    /// Health answered as fully as it can, and this is all there is.
    mutating func settle(_ id: UUID) { settled.insert(id) }
}
