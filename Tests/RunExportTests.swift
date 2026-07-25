import XCTest
@testable import Currimus

final class RunExportTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    /// A track whose points straddle a five-minute pause: the gap in `t` has
    /// to survive into the exported timestamps, because that is how every tool
    /// reading the file derives moving time.
    private var pausedRun: Run {
        Run(
            date: start, name: "Paused", distanceKm: 2, duration: 720, avgHR: 140,
            route: [
                Coordinate(lat: 48.0000, lon: 7.8000, elevation: 250, t: 0),
                Coordinate(lat: 48.0010, lon: 7.8010, elevation: 252, t: 300),
                // 300 s of standing still, then the run resumes.
                Coordinate(lat: 48.0020, lon: 7.8020, elevation: 254, t: 900),
            ]
        )
    }

    func testGPXTimestampsFollowWallClockOffsets() throws {
        let gpx = RunExport.gpx([pausedRun])
        let formatter = ISO8601DateFormatter()
        for (offset, expected) in [(0.0, "0"), (300.0, "300"), (900.0, "900")] {
            let stamp = formatter.string(from: start.addingTimeInterval(offset))
            XCTAssertTrue(gpx.contains("<time>\(stamp)</time>"),
                          "missing point at +\(expected) s")
        }
    }

    func testGPXSkipsRunsWithoutATrack() {
        let noRoute = Run(date: start, name: "Treadmill", distanceKm: 5,
                          duration: 1500, avgHR: 150)
        let gpx = RunExport.gpx([noRoute])
        XCTAssertFalse(gpx.contains("<trk>"))
        XCTAssertTrue(gpx.contains("</gpx>"))
    }

    func testCSVEscapesQuotesInNames() {
        let awkward = Run(date: start, name: "The \"big\" one", distanceKm: 5,
                          duration: 1500, avgHR: 150)
        let csv = RunExport.csv([awkward])
        XCTAssertTrue(csv.contains("\"The 'big' one\""))
        XCTAssertEqual(csv.split(separator: "\n").count, 2)   // header + one row
    }
}
