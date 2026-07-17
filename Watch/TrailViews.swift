import SwiftUI

/// Trail run: the glance plus climb, swipe left for the elevation page.
struct TrailRunPager: View {
    @ObservedObject var session: RunSession
    @State private var page = UserDefaults.standard.string(forKey: "screen") == "elevation" ? 1 : 0

    var body: some View {
        TabView(selection: $page) {
            trailGlance.tag(0)
            TrailElevationView(session: session).tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
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
            RunHeader(title: "TRAIL", heartRate: session.heartRate, mark: true)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 0) {
                Text(Format.clock(session.elapsed))
                    .font(.stat(38))
                    .kerning(-1.7)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Grid(alignment: .topLeading, horizontalSpacing: 18, verticalSpacing: 10) {
                    GridRow {
                        BigStat(value: Format.km(session.distanceKm), label: "KM", size: 17, labelSize: 7)
                        BigStat(value: Format.pace(session.rollingPace), label: "PACE /KM", size: 17, labelSize: 7)
                    }
                    GridRow {
                        VStack(alignment: .leading, spacing: 2.5) {
                            ClimbStat(value: "\(Int(session.climbMeters))", size: 17)
                            Text("M CLIMBED").kicker(7, tracking: 0.12)
                        }
                        BigStat(
                            value: "\(Int(session.climbRatePerHour))",
                            label: "M/H · LAST 10 MIN",
                            valueColor: Theme.signal, size: 17, labelSize: 7
                        )
                    }
                }
                .padding(.top, 11)
            }

            Spacer(minLength: 0)

            ZoneBar(zone: session.currentZone)
            HStack {
                Text("ZONE").kicker(7.5, tracking: 0.12)
                Spacer()
                Text("\(session.currentZone)")
                    .font(.stat(7.5))
                    .foregroundStyle(session.currentZone >= 3 ? Theme.signal : Theme.ink)
            }
            .padding(.top, 4.5)
        }
        .padding(EdgeInsets(top: 2, leading: 22, bottom: 23, trailing: 22))
    }
}

/// Where am I on the mountain — planned profile, the dot is you.
struct TrailElevationView: View {
    @ObservedObject var session: RunSession
    private let routeKm = 14.2
    private let routeClimb = 918.0

    var body: some View {
        let progress = min(session.distanceKm / routeKm, 1)
        let currentAltitude = 704 + session.climbMeters - session.descentMeters

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 5) {
                    TriangleMark().fill(Theme.signal).frame(width: 8, height: 7)
                    Text("ELEVATION").kicker(8.5)
                }
                Spacer()
                Text("\(Int(currentAltitude)) m")
                    .font(.stat(8.5, weight: .regular))
                    .foregroundStyle(Theme.muted)
            }

            Spacer(minLength: 0)

            ZStack {
                LineChart(points: TrailProfile.route)
                    .stroke(Theme.track, style: .init(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                LineChart(points: TrailProfile.upTo(progress))
                    .stroke(Theme.signal, style: .init(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                GeometryReader { proxy in
                    Circle()
                        .fill(Theme.ink)
                        .frame(width: 7, height: 7)
                        .position(
                            x: progress * proxy.size.width,
                            y: (1 - TrailProfile.elevation(at: progress)) * proxy.size.height
                        )
                }
            }
            .frame(height: 75)

            Spacer(minLength: 0)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 2.5) {
                    ClimbStat(value: "\(Int(session.climbMeters))", size: 15)
                    Text("CLIMBED").kicker(6.5, tracking: 0.1)
                }
                VStack(alignment: .leading, spacing: 2.5) {
                    Text("\(max(Int(routeClimb - session.climbMeters), 0))")
                        .font(.stat(15))
                        .foregroundStyle(Theme.signal)
                    Text("M TO TOP").kicker(6.5, tracking: 0.1)
                }
                VStack(alignment: .leading, spacing: 2.5) {
                    ClimbStat(value: "\(Int(session.descentMeters))", size: 15, pointingDown: true)
                    Text("DOWN").kicker(6.5, tracking: 0.1)
                }
            }
        }
        .padding(EdgeInsets(top: 2, leading: 22, bottom: 23, trailing: 22))
    }
}
