import XCTest

/// What happens to a finished run between the watch and the phone.
///
/// This file exists because of CUR-40 finding 4: a two-hour trail run finished,
/// was saved to Apple Health, and never appeared in Currimus. Nothing in the
/// transfer path could report a failure or try again, so there is no way to
/// know now which of them it was — and every one of them is fixed here.
final class RunSyncTests: XCTestCase {

    /// A run with `points` GPS fixes on it, at full sensor precision.
    private func trailRun(points: Int) -> Run {
        var run = Run(date: .now, type: .trail, name: "Ridge trail",
                      distanceKm: 31.4, duration: 4 * 3_600, avgHR: 148)
        run.route = (0..<points).map { i in
            Coordinate(lat: 47.4271234567891 + Double(i) * 0.000123456789,
                       lon: 11.0913456789012 + Double(i) * 0.000098765432,
                       elevation: 1_204.6789012345 + Double(i % 400) * 1.23456789,
                       t: Double(i) * 7.2)
        }
        run.altitudeSamples = (0..<240).map { 800 + Double($0) * 1.234567891 }
        return run
    }

    /// The size ceiling, and the whole of finding 4's most likely cause: a
    /// four-hour run's track at full precision is six figures of JSON, and
    /// WatchConnectivity refuses a payload past a limit it does not publish.
    func testALongRunsPayloadIsBroughtUnderTheCeiling() throws {
        let big = trailRun(points: 2_000)
        XCTAssertGreaterThan(try JSONEncoder().encode(big).count, RunSync.maxPayloadBytes,
                             "the fixture is not big enough to exercise this")

        let payload = try XCTUnwrap(RunSync.payload(for: big))
        XCTAssertLessThanOrEqual(payload.count, RunSync.maxPayloadBytes)

        // And what comes out is still the same run, with a track that still
        // spans it — decimation keeps both ends.
        let decoded = try JSONDecoder().decode(Run.self, from: payload)
        XCTAssertEqual(decoded.id, big.id)
        XCTAssertEqual(decoded.distanceKm, big.distanceKm)
        XCTAssertGreaterThan(decoded.route?.count ?? 0, 200)
        XCTAssertEqual(decoded.route?.first?.t ?? -1, big.route?.first?.t ?? -2, accuracy: 1)
        XCTAssertEqual(decoded.route?.last?.t ?? -1, big.route?.last?.t ?? -2, accuracy: 1)
    }

    /// A run small enough to send is sent whole — nothing is thinned for the
    /// sake of it.
    func testAnOrdinaryRunKeepsEveryPointOfItsTrack() throws {
        let ordinary = trailRun(points: 300)
        let payload = try XCTUnwrap(RunSync.payload(for: ordinary))
        let decoded = try JSONDecoder().decode(Run.self, from: payload)
        XCTAssertEqual(decoded.route?.count, 300)
    }

    /// Rounding to the precision the fix was actually measured at is most of
    /// where the saving comes from, and it costs nothing anyone can see.
    func testRoundingCostsLessThanAMetreAndSavesMostOfThePayload() throws {
        let run = trailRun(points: 500)
        let full = try JSONEncoder().encode(run).count
        let rounded = try JSONEncoder().encode(run.roundedForTransfer).count
        XCTAssertLessThan(rounded, full * 3 / 4)

        let before = try XCTUnwrap(run.route?.first)
        let after = try XCTUnwrap(run.roundedForTransfer.route?.first)
        XCTAssertEqual(after.lat, before.lat, accuracy: 0.00001)     // ≈ 1 m
        XCTAssertEqual(after.lon, before.lon, accuracy: 0.00001)
        XCTAssertEqual(after.elevation, before.elevation, accuracy: 0.05)
    }

    // MARK: The outbox

    private func pending(_ id: String, daysAgo: Double) -> RunSync.Pending {
        RunSync.Pending(id: id, run: Data([1, 2, 3]),
                        queued: Date.now.addingTimeInterval(-daysAgo * 86_400))
    }

    func testTheOutboxKeepsARunAcrossAWeekendAndThenLetsItGo() {
        let kept = RunSync.trimmed([pending("fresh", daysAgo: 0),
                                    pending("weekend", daysAgo: 3),
                                    pending("ancient", daysAgo: 30)])
        XCTAssertEqual(kept.map(\.id), ["weekend", "fresh"])
    }

    /// A watch with no phone paired to it must not accumulate every run it has
    /// ever recorded.
    func testTheOutboxIsCapped() {
        let many = (0..<200).map { pending("run\($0)", daysAgo: Double(200 - $0) / 24) }
        let kept = RunSync.trimmed(many)
        XCTAssertEqual(kept.count, RunSync.outboxCapacity)
        // And it is the newest that survive.
        XCTAssertEqual(kept.last?.id, "run199")
    }
}
