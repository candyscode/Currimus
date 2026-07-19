import Foundation

/// GPX / CSV export — the "no lock-in" promise. CSV summarises every run;
/// GPX writes one `<trk>` per run from the locally stored GPS track.
enum RunExport {

    static func csv(_ runs: [Run]) -> String {
        var lines = ["date,type,name,distance_km,duration_s,avg_pace_s_per_km,avg_hr,climb_m,descent_m"]
        let iso = ISO8601DateFormatter()
        for run in runs.sorted(by: { $0.date < $1.date }) {
            let fields: [String] = [
                iso.string(from: run.date),
                run.classification.rawValue,
                "\"\(run.name.replacingOccurrences(of: "\"", with: "'"))\"",
                String(format: "%.2f", run.distanceKm),
                String(Int(run.duration.rounded())),
                String(Int(run.paceSecPerKm.rounded())),
                String(run.avgHR),
                String(Int((run.climbMeters ?? 0).rounded())),
                String(Int((run.descentMeters ?? 0).rounded())),
            ]
            lines.append(fields.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func gpx(_ runs: [Run]) -> String {
        let iso = ISO8601DateFormatter()
        var out = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Currimus" xmlns="http://www.topografix.com/GPX/1/1">
        """
        for run in runs.sorted(by: { $0.date < $1.date }) {
            guard let route = run.route, !route.isEmpty else { continue }
            out += "\n  <trk>\n    <name>\(xml(run.name))</name>\n    <trkseg>"
            for point in route {
                let time = iso.string(from: run.date.addingTimeInterval(point.t))
                out += """

                      <trkpt lat="\(String(format: "%.6f", point.lat))" lon="\(String(format: "%.6f", point.lon))">
                        <ele>\(String(format: "%.1f", point.elevation))</ele>
                        <time>\(time)</time>
                      </trkpt>
                """
            }
            out += "\n    </trkseg>\n  </trk>"
        }
        out += "\n</gpx>\n"
        return out
    }

    /// Writes both files to a temp directory and returns their URLs for sharing.
    static func exportFiles(_ runs: [Run]) throws -> [URL] {
        let dir = FileManager.default.temporaryDirectory
        let csvURL = dir.appendingPathComponent("currimus-runs.csv")
        let gpxURL = dir.appendingPathComponent("currimus-runs.gpx")
        try csv(runs).write(to: csvURL, atomically: true, encoding: .utf8)
        try gpx(runs).write(to: gpxURL, atomically: true, encoding: .utf8)
        return [csvURL, gpxURL]
    }

    private static func xml(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
