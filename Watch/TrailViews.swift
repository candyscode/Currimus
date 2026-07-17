import SwiftUI

/// Trail run: the glance plus climb, swipe left for the elevation page.
struct TrailRunPager: View {
    @ObservedObject var session: RunSession
    @State private var page = ["elevation", "elevation-noroute"]
        .contains(UserDefaults.standard.string(forKey: "screen") ?? "") ? 1 : 0

    var body: some View {
        // TabView pages size to fit their content, which would collapse the
        // spacers early in a run — pin every page to the full screen height.
        GeometryReader { proxy in
            TabView(selection: $page) {
                trailGlance
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .tag(0)
                TrailElevationView(session: session)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .contentShape(Rectangle())
        .onTapGesture { session.pause() }
        .overlay {
            if let alert = session.kilometerAlert {
                KilometerAlertView(alert: alert).transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.kilometerAlert)
    }

    private var trailGlance: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    TriangleMark().fill(Theme.signal).frame(width: 8, height: 7)
                    Text("TRAIL").kicker(8, color: Theme.bright, tracking: 0.1)
                }
                .padding(.bottom, 6)
                Text(Format.clock(session.elapsed))
                    .font(.stat(38))
                    .kerning(-1.7)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Grid(alignment: .topLeading, horizontalSpacing: 18, verticalSpacing: 10) {
                    GridRow {
                        BigStat(value: Format.km(session.distanceKm), label: "KM", size: 17)
                        BigStat(value: Format.pace(session.rollingPace), label: "PACE /KM", size: 17)
                    }
                    GridRow {
                        VStack(alignment: .leading, spacing: 2.5) {
                            ClimbStat(value: "\(Int(session.climbMeters))", size: 17)
                            Text("M CLIMBED").kicker(8, color: Theme.bright, tracking: 0.1)
                                .lineLimit(1).fixedSize()
                        }
                        BigStat(
                            value: "\(Int(session.climbRatePerHour))",
                            label: "M/H · LAST 10 MIN",
                            valueColor: Theme.signal, size: 17
                        )
                    }
                }
                .padding(.top, 11)
            }

            Spacer(minLength: 0)

            ZoneBar(zone: session.currentZone)
            HStack {
                Text("ZONE").kicker(8, color: Theme.bright, tracking: 0.1)
                Spacer()
                Text(session.currentZone > 0 ? "\(session.currentZone)" : "–")
                    .font(.stat(7.5))
                    .foregroundStyle(session.currentZone >= 3 ? Theme.signal : Theme.ink)
            }
            .padding(.top, 4.5)
        }
        // TabView pages don't stretch on their own — without this the
        // spacers collapse and the glance sticks to the top.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 2, leading: 22, bottom: 23, trailing: 22))
    }
}

/// Where am I on the mountain. With a planned route: the dot is you, gray is
/// what's left. Without one: the profile you have run so far, growing right.
struct TrailElevationView: View {
    @ObservedObject var session: RunSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                TriangleMark().fill(Theme.signal).frame(width: 8, height: 7)
                (Text("ELEVATION · ").foregroundStyle(Theme.bright)
                    + Text("\(Int(session.altitudeMeters)) m")
                        .foregroundStyle(Theme.ink).fontWeight(.semibold))
                    .font(.stat(8.5, weight: .regular))
            }
            .padding(.top, 8)

            Spacer(minLength: 0)

            chart
                .frame(height: 75)

            Spacer(minLength: 0)

            if let route = session.plannedRoute {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2.5) {
                        ClimbStat(value: "\(Int(session.climbMeters))", size: 15)
                        Text("CLIMBED").kicker(8, color: Theme.bright, tracking: 0.1)
                    }
                    VStack(alignment: .leading, spacing: 2.5) {
                        Text("\(max(Int(route.climbMeters - session.climbMeters), 0))")
                            .font(.stat(15))
                            .foregroundStyle(Theme.signal)
                        Text("M TO TOP").kicker(8, color: Theme.bright, tracking: 0.1)
                    }
                    VStack(alignment: .leading, spacing: 2.5) {
                        ClimbStat(value: "\(Int(session.descentMeters))", size: 15, pointingDown: true)
                        Text("DOWN").kicker(8, color: Theme.bright, tracking: 0.1)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 2.5) {
                        ClimbStat(value: "\(Int(session.climbMeters))", size: 15)
                        Text("CLIMBED").kicker(8, color: Theme.bright, tracking: 0.1)
                    }
                    VStack(alignment: .leading, spacing: 2.5) {
                        ClimbStat(value: "\(Int(session.descentMeters))", size: 15, pointingDown: true)
                        Text("DOWN").kicker(8, color: Theme.bright, tracking: 0.1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 2, leading: 22, bottom: 23, trailing: 22))
    }

    @ViewBuilder
    private var chart: some View {
        if let route = session.plannedRoute {
            let progress = min(session.distanceKm / route.distanceKm, 1)
            ZStack {
                LineChart(points: route.profile)
                    .stroke(Theme.track, style: .init(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                LineChart(points: RoutePoints.upTo(route.profile, fraction: progress))
                    .stroke(Theme.signal, style: .init(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                GeometryReader { proxy in
                    Circle()
                        .fill(Theme.ink)
                        .frame(width: 7, height: 7)
                        .position(
                            x: progress * proxy.size.width,
                            y: (1 - RoutePoints.elevation(route.profile, at: progress)) * proxy.size.height
                        )
                }
            }
        } else {
            let points = RoutePoints.normalized(session.altitudeProfile)
            ZStack {
                LineChart(points: points)
                    .stroke(Theme.signal, style: .init(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                if let last = points.last {
                    GeometryReader { proxy in
                        Circle()
                            .fill(Theme.ink)
                            .frame(width: 7, height: 7)
                            .position(
                                x: last.x * proxy.size.width,
                                y: (1 - last.y) * proxy.size.height
                            )
                    }
                }
            }
        }
    }
}

/// Helpers for elevation profiles.
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

    static func upTo(_ route: [CGPoint], fraction: Double) -> [CGPoint] {
        var result: [CGPoint] = []
        for point in route where point.x <= fraction { result.append(point) }
        if let last = result.last, last.x < fraction,
           let next = route.first(where: { $0.x > fraction }) {
            let t = (fraction - last.x) / (next.x - last.x)
            result.append(.init(x: fraction, y: last.y + (next.y - last.y) * t))
        }
        return result
    }

    static func elevation(_ route: [CGPoint], at fraction: Double) -> Double {
        Double(upTo(route, fraction: fraction).last?.y ?? 0)
    }
}
