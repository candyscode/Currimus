import SwiftUI

/// Trail run: the glance plus climb, swipe left for the elevation page.
struct TrailRunPager: View {
    @ObservedObject var session: RunSession

    var body: some View {
        TabView {
            trailGlance
            TrailElevationView(session: session)
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
            RunHeader(title: "▲ TRAIL", heartRate: session.heartRate)

            Spacer(minLength: 0)

            Text(Format.clock(session.elapsed))
                .font(.stat(32))
                .kerning(-0.8)

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow {
                    BigStat(value: Format.km(session.distanceKm), label: "KM", size: 17)
                    BigStat(value: Format.pace(session.rollingPace), label: "PACE /KM", size: 17)
                }
                GridRow {
                    BigStat(value: "▲ \(Int(session.climbMeters))", label: "M CLIMBED", size: 17)
                    BigStat(
                        value: "\(Int(session.climbRatePerHour))",
                        label: "M/H · LAST 10 MIN",
                        valueColor: Theme.signal, size: 17
                    )
                }
            }
            .padding(.top, 8)

            Spacer(minLength: 0)

            ZoneBar(zone: session.currentZone)
            HStack {
                Text("ZONE").kicker(8)
                Spacer()
                Text("\(session.currentZone)")
                    .font(.stat(9))
                    .foregroundStyle(session.currentZone >= 3 ? Theme.signal : Theme.ink)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 4)
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
            HStack {
                Text("▲ ELEVATION").kicker(9)
                Spacer()
                Text("\(Int(currentAltitude)) m")
                    .font(.stat(10, weight: .regular))
                    .foregroundStyle(Theme.muted)
            }

            Spacer(minLength: 0)

            ZStack {
                LineChart(points: TrailProfile.route)
                    .stroke(Theme.track, style: .init(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                LineChart(points: TrailProfile.upTo(progress))
                    .stroke(Theme.signal, style: .init(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                GeometryReader { proxy in
                    Circle()
                        .fill(Theme.ink)
                        .frame(width: 8, height: 8)
                        .position(
                            x: progress * proxy.size.width,
                            y: (1 - TrailProfile.elevation(at: progress)) * proxy.size.height
                        )
                }
            }
            .frame(height: 66)

            Spacer(minLength: 0)

            HStack(alignment: .top, spacing: 16) {
                BigStat(value: "▲ \(Int(session.climbMeters))", label: "CLIMBED", size: 15)
                BigStat(
                    value: "\(max(Int(routeClimb - session.climbMeters), 0))",
                    label: "M TO TOP", valueColor: Theme.signal, size: 15
                )
                BigStat(value: "▼ \(Int(session.descentMeters))", label: "DOWN", size: 15)
            }
        }
        .padding(.horizontal, 4)
    }
}
