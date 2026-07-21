import Foundation

/// The heavy half of a run — the GPS track and the altitude series.
struct RunSamples: Codable, Equatable {
    var altitude: [Double]?
    var route: [Coordinate]?

    static let empty = RunSamples()

    var isEmpty: Bool { (altitude?.isEmpty ?? true) && (route?.isEmpty ?? true) }

    init(altitude: [Double]? = nil, route: [Coordinate]? = nil) {
        self.altitude = altitude
        self.route = route
    }

    init(_ run: Run) {
        self.init(altitude: run.altitudeSamples, route: run.route)
    }
}

/// One file per run, holding everything the log itself does not need.
///
/// Why not keep them in the log blob: the log lives in App-Group
/// `UserDefaults` so the widget can read it, and `UserDefaults` faults its
/// entire backing plist into memory on first touch — in *every* process that
/// opens the suite, including a widget extension with a hard memory budget.
/// A recorded route is up to 2 000 coordinates; a year of them is megabytes
/// the widget never looks at, re-encoded on the main thread on every single
/// mutation of the log.
///
/// So metadata (small, read constantly, needed by the widget) stays in
/// defaults, and samples (large, read only by a detail screen or an export)
/// move here.
enum RunSampleStore {
    /// App-group container so phone, watch and widgets agree on the location;
    /// caches as a fallback keeps a missing entitlement from being fatal.
    static let directory: URL = {
        let base = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.currimus.app")
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("RunSamples", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            Log.store.error("sample directory unavailable: \(error.localizedDescription, privacy: .public)")
        }
        return dir
    }()

    private static func url(_ id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    static func load(_ id: UUID) -> RunSamples? {
        let url = url(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try JSONDecoder().decode(RunSamples.self, from: Data(contentsOf: url))
        } catch {
            Log.store.error("sample read failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func save(_ samples: RunSamples, for id: UUID) {
        guard !samples.isEmpty else { return delete(id) }
        do {
            let data = try JSONEncoder().encode(samples)
            try data.write(to: url(id), options: .atomic)
        } catch {
            Log.store.error("sample write failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    static func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(id))
    }

    /// Drops sidecars whose run is gone — deleting a run must not leak its
    /// track onto disk forever.
    static func prune(keeping ids: Set<UUID>) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" {
            let name = file.deletingPathExtension().lastPathComponent
            guard let id = UUID(uuidString: name), !ids.contains(id) else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Test seam: wipe everything this store owns.
    static func removeAll() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}

extension Run {
    /// The run as the log stores it: metadata only, samples on disk.
    var strippingSamples: Run {
        var copy = self
        copy.altitudeSamples = nil
        copy.route = nil
        return copy
    }

    /// The run with its samples put back, for a detail screen or an export.
    func merging(_ samples: RunSamples) -> Run {
        var copy = self
        copy.altitudeSamples = samples.altitude ?? altitudeSamples
        copy.route = samples.route ?? route
        return copy
    }

    var carriesSamples: Bool {
        !(altitudeSamples?.isEmpty ?? true) || !(route?.isEmpty ?? true)
    }
}
