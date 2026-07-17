import SwiftUI

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
struct ZoneHeatStrip: View {
    var zoneSeconds: [TimeInterval]
    var height: CGFloat = 7

    var body: some View {
        GeometryReader { proxy in
            let total = max(zoneSeconds.reduce(0, +), 1)
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { index in
                    Theme.zoneHeat[index]
                        .frame(width: max(proxy.size.width * zoneSeconds[index] / total - 2, 2))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: height / 2))
        }
        .frame(height: height)
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

/// The mountain used across trail screens.
enum TrailProfile {
    static let route: [CGPoint] = [
        .init(x: 0.00, y: 0.07), .init(x: 0.10, y: 0.19), .init(x: 0.20, y: 0.16),
        .init(x: 0.31, y: 0.39), .init(x: 0.42, y: 0.35), .init(x: 0.53, y: 0.61),
        .init(x: 0.64, y: 0.56), .init(x: 0.75, y: 0.80), .init(x: 0.86, y: 0.72),
        .init(x: 1.00, y: 0.91),
    ]

    static func upTo(_ fraction: Double) -> [CGPoint] {
        var result: [CGPoint] = []
        for point in route where point.x <= fraction { result.append(point) }
        if let last = result.last, last.x < fraction,
           let next = route.first(where: { $0.x > fraction }) {
            let t = (fraction - last.x) / (next.x - last.x)
            result.append(.init(x: fraction, y: last.y + (next.y - last.y) * t))
        }
        return result
    }

    static func elevation(at fraction: Double) -> Double {
        Double(upTo(fraction).last?.y ?? 0)
    }
}
