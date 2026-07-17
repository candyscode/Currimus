import SwiftUI

struct RunDetailView: View {
    @Environment(\.dismiss) private var dismiss
    var run: Run

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(title: "Log") { dismiss() }

                Text(run.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased()
                     + " · " + run.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()))
                    .kicker(12)
                    .padding(.top, 16)
                Text(run.name)
                    .font(.sg(26, weight: .semibold))
                    .kerning(-0.5)
                    .padding(.top, 4)

                HStack(spacing: 28) {
                    DetailStat(value: Format.km(run.distanceKm), label: "KM")
                    DetailStat(value: Format.clock(run.duration), label: "TIME")
                    DetailStat(value: Format.pace(run.paceSecPerKm), label: "AVG PACE", color: Theme.signal)
                    if run.type == .trail, let climb = run.climbMeters {
                        VStack(alignment: .leading, spacing: 5) {
                            ClimbStat(value: "\(Int(climb))", size: 30)
                            Text("CLIMB").kicker(11)
                        }
                    }
                }
                .padding(.top, 22)

                MapCard()
                    .padding(.top, 22)

                Text("SPLITS /KM").kicker(12).padding(.top, 26).padding(.bottom, 12)
                SplitsChart(splits: run.splits)

                Text("TIME IN ZONES").kicker(12).padding(.top, 26).padding(.bottom, 12)
                ZoneHeatStrip(zoneSeconds: run.zoneSeconds, height: 10)
                HStack {
                    ForEach(0..<5, id: \.self) { zone in
                        Text("Z\(zone + 1) · \(Int(run.zoneSeconds[zone] / 60))m")
                            .font(.stat(11, weight: .regular))
                            .foregroundStyle(Theme.muted)
                        if zone < 4 { Spacer() }
                    }
                }
                .padding(.top, 8)
            }
            .padding(28)
        }
        .background(Theme.bg)
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct BackLink: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("‹ \(title)")
                .font(.sg(14))
                .foregroundStyle(Theme.signal)
        }
        .buttonStyle(.plain)
    }
}

struct DetailStat: View {
    var value: String
    var label: String
    var color: Color = Theme.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.stat(30)).foregroundStyle(color).lineLimit(1)
            Text(label).kicker(11)
        }
    }
}

/// Route placeholder — grid paper with the run's path. Swap for MapKit once
/// real GPS traces sync over.
struct MapCard: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            GridPattern()
                .stroke(Color(hex: 0x1A1A1A), lineWidth: 1)
            RoutePath()
                .stroke(Theme.signal, style: .init(lineWidth: 3, lineCap: .round))
            GeometryReader { proxy in
                Circle().fill(Theme.ink).frame(width: 10, height: 10)
                    .position(x: 0.12 * proxy.size.width, y: 0.76 * proxy.size.height)
                Circle().fill(Theme.signal).frame(width: 10, height: 10)
                    .position(x: 0.89 * proxy.size.width, y: 0.39 * proxy.size.height)
            }
            Text("MAP")
                .font(.sg(10, weight: .medium))
                .kerning(1)
                .foregroundStyle(Color(hex: 0x4A4A4A))
                .padding([.bottom, .trailing], 12)
        }
        .frame(height: 170)
        .background(Color(hex: 0x111111))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.cardBorder, lineWidth: 1))
    }
}

struct GridPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 34
        var x = rect.minX
        while x <= rect.maxX {
            path.move(to: .init(x: x, y: rect.minY))
            path.addLine(to: .init(x: x, y: rect.maxY))
            x += step
        }
        var y = rect.minY
        while y <= rect.maxY {
            path.move(to: .init(x: rect.minX, y: y))
            path.addLine(to: .init(x: rect.maxX, y: y))
            y += step
        }
        return path
    }
}

struct RoutePath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: .init(x: 0.12 * w, y: 0.76 * h))
        path.addCurve(
            to: .init(x: 0.30 * w, y: 0.38 * h),
            control1: .init(x: 0.21 * w, y: 0.65 * h),
            control2: .init(x: 0.20 * w, y: 0.42 * h)
        )
        path.addCurve(
            to: .init(x: 0.56 * w, y: 0.55 * h),
            control1: .init(x: 0.42 * w, y: 0.34 * h),
            control2: .init(x: 0.45 * w, y: 0.57 * h)
        )
        path.addCurve(
            to: .init(x: 0.79 * w, y: 0.24 * h),
            control1: .init(x: 0.67 * w, y: 0.52 * h),
            control2: .init(x: 0.68 * w, y: 0.26 * h)
        )
        path.addCurve(
            to: .init(x: 0.89 * w, y: 0.39 * h),
            control1: .init(x: 0.85 * w, y: 0.23 * h),
            control2: .init(x: 0.89 * w, y: 0.31 * h)
        )
        return path
    }
}

/// Pace per kilometer as horizontal bars — the fastest split burns.
struct SplitsChart: View {
    var splits: [TimeInterval]

    var body: some View {
        let slowest = splits.max() ?? 1
        let fastest = splits.min() ?? 0
        VStack(spacing: 9) {
            ForEach(Array(splits.enumerated()), id: \.offset) { index, split in
                let isFastest = split == fastest && splits.count > 1
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.stat(11, weight: .regular))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 18, alignment: .leading)
                    GeometryReader { proxy in
                        let spread = max(slowest - fastest, 1)
                        let fraction = 0.55 + 0.45 * (split - fastest) / spread
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isFastest ? Theme.signal : Theme.track)
                            .frame(width: proxy.size.width * fraction)
                    }
                    .frame(height: 14)
                    Text(Format.pace(split))
                        .font(.stat(12.5, weight: .regular))
                        .foregroundStyle(isFastest ? Theme.signal : Theme.ink)
                }
            }
        }
    }
}
