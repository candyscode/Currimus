import Foundation
#if canImport(CloudKit)
import CloudKit
#endif

#if canImport(CloudKit)

/// The bridge that lets an Apple TV see runs recorded on the iPhone and watch.
///
/// Currimus is otherwise device-local: the watch records, hands the run to the
/// phone over WatchConnectivity, and the phone persists it in an App-Group
/// container. None of that reaches a TV — App Groups do not sync across
/// devices, and tvOS has neither HealthKit nor WatchConnectivity. So the phone
/// mirrors its log into the user's **private** CloudKit database, and the TV
/// reads it. Same iCloud account, no server to run, no data leaves the account.
///
/// - **Phone (writer):** `upsert` on every new run, `delete` when one is
///   removed, `backfill` once to seed the existing log.
/// - **TV (reader):** `fetchRuns` on launch / foreground. Never writes.
///
/// A run is stored as a JSON blob of its metadata (lossless and immune to
/// schema drift — the same `Codable` the local store already relies on) plus a
/// separate `date` field, with the GPS track and altitude series carried as a
/// `CKAsset` sidecar. That mirrors the local split (`RunSampleStore`): the TV
/// downloads a route only when it opens a run's detail.
///
/// Results are sorted client-side rather than with a `CKQuery` sort descriptor,
/// so the only schema requirement is the default queryable `recordName` index —
/// no custom index has to be provisioned in the CloudKit dashboard for reads to
/// work.
enum RunCloudSync {
    /// The private-database container. Must match the iCloud entitlement on the
    /// iOS and tvOS targets.
    static let containerIdentifier = "iCloud.com.currimus.app"

    enum Field {
        static let recordType = "Run"
        static let payload = "payload"   // Data: JSON of the metadata-only Run
        static let date = "date"         // Date: kept for readability/debugging
        static let samples = "samples"   // CKAsset: JSON of RunSamples (optional)
    }

    /// The metadata keys a list fetch needs — everything *except* the `samples`
    /// asset, so opening the log does not drag every run's GPS track and
    /// altitude series down with it. The asset is fetched per-run in detail.
    private static let listKeys = [Field.payload, Field.date]

    /// Built once. `CKContainer(identifier:)` is not free, and `backfill` calls
    /// through here once per run — recomputing it each time constructed a fresh
    /// container per run.
    private static let container = CKContainer(identifier: containerIdentifier)
    private static var database: CKDatabase { container.privateCloudDatabase }

    // MARK: - Account

    /// What the private database's reachability means for the UI. A signed-out
    /// account is a terminal state worth explaining; anything transient
    /// (determining, temporarily unavailable, or an error) should be retried,
    /// not shown as "sign in".
    enum AccountState {
        case available
        case signedOut     // no account / restricted — the explain-and-stop state
        case transient     // could-not-determine / temporarily-unavailable / error
    }

    static func accountState() async -> AccountState {
        do {
            switch try await container.accountStatus() {
            case .available:
                return .available
            case .noAccount, .restricted:
                return .signedOut
            case .couldNotDetermine, .temporarilyUnavailable:
                return .transient
            @unknown default:
                return .transient
            }
        } catch {
            Log.sync.error("iCloud account status unavailable: \(error.localizedDescription, privacy: .public)")
            return .transient
        }
    }

    // MARK: - Write (iPhone)

    /// Publish one run. Pass the run **with its samples still attached** (the
    /// hydrated run) so the route/altitude sidecar asset is written too.
    /// Idempotent: keyed on the run's own id, so re-publishing overwrites.
    static func upsert(_ run: Run) async {
        do {
            try await save(makeRecord(for: run))
        } catch {
            Log.sync.error("cloud upsert failed for \(run.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Remove a run the user deleted on the phone. A missing record is not an
    /// error — the run may never have synced.
    static func delete(id: UUID) async {
        do {
            try await database.deleteRecord(withID: recordID(id))
        } catch let error as CKError where error.code == .unknownItem {
            // Already gone; nothing to do.
        } catch {
            Log.sync.error("cloud delete failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Seed the whole log on first enable. Upserts sequentially: a personal
    /// running log is at most a few hundred runs, this runs once, and one call
    /// per run sidesteps the batch change-tag pitfalls of a bulk create against
    /// records that may already exist.
    static func backfill(_ runs: [Run]) async {
        for run in runs { await upsert(run) }
        Log.sync.notice("cloud backfill published \(runs.count) runs")
    }

    // MARK: - Read (Apple TV)

    /// Every run in the private database, newest first, **metadata only** — the
    /// GPS track and altitude series stay in the cloud until a detail screen
    /// asks for them via `fetchSamples(for:)`.
    ///
    /// Throws rather than returning `[]` on failure: an empty result and a
    /// failed fetch are not the same thing, and the caller must not overwrite a
    /// good local cache with the emptiness of a network blip.
    static func fetchRuns() async throws -> [Run] {
        let query = CKQuery(recordType: Field.recordType, predicate: NSPredicate(value: true))
        var collected: [Run] = []

        // desiredKeys omits the sample asset, so the list fetch never downloads
        // routes — the whole point of storing them as a separate CKAsset.
        var response = try await database.records(matching: query, desiredKeys: listKeys)
        collected.append(contentsOf: decode(response.matchResults))

        // Page through the rest — a query returns a cursor when the result
        // set exceeds one batch.
        while let cursor = response.queryCursor {
            response = try await database.records(continuingMatchFrom: cursor, desiredKeys: listKeys)
            collected.append(contentsOf: decode(response.matchResults))
        }

        return collected.sorted { $0.date > $1.date }
    }

    /// The GPS track and altitude series for one run, fetched on demand when its
    /// detail opens. Returns `nil` when the run has no sample asset or the fetch
    /// fails — the detail screen then simply draws its default route/empty
    /// profile, exactly as a locally recorded run with no track would.
    static func fetchSamples(for id: UUID) async -> RunSamples? {
        do {
            let record = try await database.record(for: recordID(id))
            guard let asset = record[Field.samples] as? CKAsset,
                  let url = asset.fileURL,
                  let data = try? Data(contentsOf: url) else { return nil }
            return try JSONDecoder().decode(RunSamples.self, from: data)
        } catch {
            Log.sync.error("cloud sample fetch failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Record mapping

    private static func recordID(_ id: UUID) -> CKRecord.ID {
        // The run's own UUID is the record name, which makes writes idempotent
        // and lets a delete address the record without a lookup.
        CKRecord.ID(recordName: id.uuidString)
    }

    private static func makeRecord(for run: Run) throws -> CKRecord {
        let record = CKRecord(recordType: Field.recordType, recordID: recordID(run.id))
        // Data and Date both conform to CKRecordValueProtocol, which is what
        // the record subscript takes — assign directly, no cast.
        record[Field.payload] = try JSONEncoder().encode(run.strippingSamples)
        record[Field.date] = run.date
        if run.carriesSamples {
            record[Field.samples] = try sampleAsset(for: run)
        }
        return record
    }

    /// Writes the run's samples to a temporary JSON file and wraps it as a
    /// `CKAsset`. CloudKit uploads the file's contents and manages its lifetime.
    private static func sampleAsset(for run: Run) throws -> CKAsset {
        let data = try JSONEncoder().encode(RunSamples(run))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(run.id.uuidString)-samples.json")
        try data.write(to: url, options: .atomic)
        return CKAsset(fileURL: url)
    }

    private static func decode(_ matches: [(CKRecord.ID, Result<CKRecord, Error>)]) -> [Run] {
        matches.compactMap { _, result in
            switch result {
            case .success(let record): return run(from: record)
            case .failure(let error):
                Log.sync.error("cloud record unreadable: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    /// Decode the metadata-only run from a list record. The sample asset is not
    /// part of a list fetch (see `listKeys`); a detail screen merges it in later
    /// through `fetchSamples(for:)`.
    private static func run(from record: CKRecord) -> Run? {
        guard let payload = record[Field.payload] as? Data else {
            Log.sync.error("cloud record \(record.recordID.recordName, privacy: .public) has no payload")
            return nil
        }
        do {
            return try JSONDecoder().decode(Run.self, from: payload)
        } catch {
            Log.sync.error("cloud payload unreadable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Save with upsert semantics

    /// Save a record, overwriting any existing one with the same id. A brand-new
    /// `CKRecord` carries no change tag, so if the server already holds that id
    /// CloudKit reports `.serverRecordChanged`; the recovery is to copy our
    /// fields onto the server's copy (which has the tag) and save that.
    private static func save(_ record: CKRecord) async throws {
        do {
            try await database.save(record)
        } catch let error as CKError where error.code == .serverRecordChanged {
            guard let server = error.serverRecord else { throw error }
            for key in record.allKeys() { server[key] = record[key] }
            try await database.save(server)
        }
    }
}

#endif
