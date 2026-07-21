import SwiftUI

/// Evenly distributed stat columns — the design's `1fr 1fr 1fr` grid.
/// Each column claims an equal share, leading-aligned.
struct StatRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Group { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Inline hard-edged triangle + number, e.g. "▲ 642".
struct ClimbStat: View {
    var value: String
    var size: CGFloat
    var color: Color = Theme.ink
    var pointingDown = false

    var body: some View {
        HStack(alignment: .center, spacing: size * 0.28) {
            TriangleMark(pointingDown: pointingDown)
                .fill(color)
                .frame(width: size * 0.62, height: size * 0.52)
            Text(value)
                .font(.stat(size))
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }
}

/// Five-segment live zone indicator. The active zone lights up; zone 5 sets
/// the whole bar burning, per the design.
struct ZoneBar: View {
    var zone: Int
    var height: CGFloat = 6
    var gap: CGFloat = 3

    var body: some View {
        HStack(spacing: gap) {
            ForEach(1...5, id: \.self) { segment in
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(color(for: segment))
                    .frame(height: height)
                    .shadow(
                        color: zone == 5 && segment == 5 ? Theme.signal.opacity(0.5) : .clear,
                        radius: 7
                    )
            }
        }
        .animation(.easeInOut(duration: 0.3), value: zone)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate zone")
        .accessibilityValue(zone > 0
            ? "\(zone) of 5, \(HRZones.zoneNames[zone - 1])"
            : "no reading yet")
    }

    private func color(for segment: Int) -> Color {
        if zone >= 5 {
            return [Theme.signal.opacity(0.25), Theme.signal.opacity(0.4), Theme.signal.opacity(0.6),
                    Theme.signal.opacity(0.8), Theme.signal][segment - 1]
        }
        return segment == zone ? Theme.zoneSegment(active: zone) : Theme.track
    }
}

/// Proportional time-in-zones heat strip (summary + iPhone views).
/// Without zone data (no HR reading) it stays a quiet empty track.
struct ZoneHeatStrip: View {
    var zoneSeconds: [TimeInterval]
    var height: CGFloat = 7

    var body: some View {
        GeometryReader { proxy in
            let total = zoneSeconds.reduce(0, +)
            if total < 1 {
                Capsule().fill(Theme.trackIdle)
                    .frame(width: proxy.size.width, height: height)
            } else {
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { index in
                        Theme.zoneHeat[index]
                            .frame(width: max(proxy.size.width * zoneSeconds[index] / total - 2, 0))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: height / 2))
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time in heart rate zones")
        .accessibilityValue(spokenSummary)
    }

    /// Proportions are the whole point of this strip, so say them — zones with
    /// no time in them are noise and stay out.
    private var spokenSummary: String {
        let total = zoneSeconds.reduce(0, +)
        guard total >= 1 else { return "No heart rate recorded" }
        return zoneSeconds.enumerated()
            .filter { $0.element >= 30 }
            .map { index, seconds in
                "zone \(index + 1) \(Int((seconds / total * 100).rounded()))%"
            }
            .joined(separator: ", ")
    }
}

/// Polyline chart used for elevation profiles and trend lines.
struct LineChart: Shape {
    /// Normalized points, x and y in 0…1 (y = 0 is the bottom).
    var points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: point(first, in: rect))
        for p in points.dropFirst() {
            path.addLine(to: point(p, in: rect))
        }
        return path
    }

    private func point(_ p: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + p.x * rect.width, y: rect.maxY - p.y * rect.height)
    }
}

/// Helpers for elevation profiles (shared by watch + iPhone).
enum RoutePoints {
    /// Altitude series → normalized chart points (x spread 0…1, y padded).
    static func normalized(_ altitudes: [Double]) -> [CGPoint] {
        guard altitudes.count > 1,
              let low = altitudes.min(), let high = altitudes.max() else { return [] }
        let span = max(high - low, 10)
        return altitudes.enumerated().map { index, altitude in
            CGPoint(
                x: Double(index) / Double(altitudes.count - 1),
                y: 0.08 + 0.84 * (altitude - low) / span
            )
        }
    }

}

