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

    /// Finding 4's most likely cause: a four-hour run's track at full precision
    /// is six figures of JSON, and `transferUserInfo` refuses a payload past a
    /// limit it does not publish. Such a run goes as a file — **whole**. It is
    /// not thinned to fit, because a marathon arriving with half its GPS points
    /// would be the same silent failure wearing a different hat.
    func testAMarathonsTrackTravelsWholeAsAFile() throws {
        let big = trailRun(points: 2_000)
        XCTAssertGreaterThan(try JSONEncoder().encode(big).count, RunSync.maxPayloadBytes,
                             "the fixture is not big enough to exercise this")

        let delivery = try XCTUnwrap(RunSync.delivery(for: big))
        guard case .file(let data) = delivery else {
            return XCTFail("a run over the dictionary limit has to go as a file")
        }
        let decoded = try JSONDecoder().decode(Run.self, from: data)
        XCTAssertEqual(decoded.id, big.id)
        XCTAssertEqual(decoded.distanceKm, big.distanceKm)
        XCTAssertEqual(decoded.route?.count, 2_000, "every point of the track has to survive")
    }

    /// A run small enough for the dictionary queue takes it — the file path is
    /// for the ones that need it, not for everything.
    func testAnOrdinaryRunGoesThroughTheDictionaryQueue() throws {
        let ordinary = trailRun(points: 300)
        let delivery = try XCTUnwrap(RunSync.delivery(for: ordinary))
        guard case .userInfo(let data) = delivery else {
            return XCTFail("an ordinary run does not need a file")
        }
        XCTAssertEqual(try JSONDecoder().decode(Run.self, from: data).route?.count, 300)
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

    // MARK: The barometer's state between runs

    /// One `RunSession` — and so one altimeter — outlives every run in an app
    /// session. A reading left behind by the last run is the altitude of
    /// somewhere else: the next run takes it for a current one on its first
    /// tick, seeds the filter with it, and banks the drive to the trailhead as
    /// climb. It also deadens the grace period that catches a barometer which
    /// has gone silent, because the reading is then never nil again.
    @MainActor
    func testStoppingTheAltimeterForgetsItsReading() {
        let altimeter = BarometricAltimeter()
        altimeter.debugRecord(500, isRelative: true)
        XCTAssertEqual(altimeter.altitude, 500)

        altimeter.stop()
        XCTAssertNil(altimeter.altitude, "the next run must start with no reading at all")
        XCTAssertFalse(altimeter.isRelative)
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
