import SwiftUI

/// Trail run: the glance plus climb, swipe left for the elevation page.
struct TrailRunPager: View {
    @ObservedObject var session: RunSession
    @State private var page = ["elevation", "elevation-noroute"]
        .contains(UserDefaults.standard.string(forKey: "screen") ?? "") ? 1 : 0

    var body: some View {
        // Hand-rolled pager instead of TabView: TabView reserves ~20pt at the
        // bottom even with the index hidden, which pushed the zone bar out of
        // line with the plain run screen. A plain HStack + drag keeps both
        // modes layout-identical.
        GeometryReader { proxy in
            HStack(spacing: 0) {
                trailGlance
                    .frame(width: proxy.size.width, height: proxy.size.height)
                TrailElevationView(session: session)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .offset(x: page == 0 ? 0 : -proxy.size.width)
            .animation(.snappy(duration: 0.3), value: page)
        }
        // Clip only horizontally (hide the neighbouring page); leave vertical
        // overflow so the hero pulled up under the caption isn't cut off.
        .mask { Rectangle().padding(.vertical, -120) }
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 15)
                .onEnded { value in
                    if value.translation.width < -25 {
                        page = 1
                    } else if value.translation.width > 25 {
                        page = 0
                    }
                }
        )
        .onTapGesture { session.pause() }
        .overlay {
            if let alert = session.kilometerAlert {
                KilometerAlertView(alert: alert).transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.kilometerAlert)
        // One caption for the pager, driven by the visible page. Hidden while
        // the kilometer alert owns the canvas.
        .topBarCaption {
            if session.kilometerAlert == nil {
                if page == 0 {
                    TopBarCaption(text: "TRAIL", mark: true)
                } else {
                    TopBarCaption(text: "ELEVATION · \(Int(session.altitudeMeters)) m", mark: true)
                }
            }
        }
    }

    private var trailGlance: some View {
        RunScaffold {
            VStack(alignment: .leading, spacing: 0) {
                // Same 52 pt hero box as Run/Pacer (shrinks to fit long trail
                // times), so the value sits at an identical height on all three.
                Text(Format.clock(session.elapsed))
                    .font(.stat(52))
                    .kerning(-2.3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                    .animation(.linear(duration: 0.25), value: session.elapsed)

                // The design's 1fr 1fr grid — grouped right under the timer so
                // the free space pools above the zone bar.
                Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        BigStat(value: Format.km(session.distanceKm), label: "KM", size: 17)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        BigStat(value: Format.pace(session.rollingPace), label: "PACE /KM", size: 17)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GridRow {
                        VStack(alignment: .leading, spacing: 2.5) {
                            ClimbStat(value: "\(Int(session.climbMeters))", size: 17)
                            Text("M CLIMBED").kicker(8, color: Theme.bright, tracking: 0.1)
                                .lineLimit(1).fixedSize()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        BigStat(
                            value: "\(Int(session.climbRatePerHour))",
                            label: "M/H · LAST 10 MIN",
                            valueColor: Theme.signal, size: 17
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 12)
            }
        } footer: {
            ZoneFooter(zone: session.currentZone)
        }
    }
}

/// Where am I on the mountain. With a planned route: the dot is you, gray is
/// what's left. Without one: the profile you have run so far, growing right.
struct TrailElevationView: View {
    @ObservedObject var session: RunSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            chart
                .frame(height: 96)

            Spacer(minLength: 14)

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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(EdgeInsets(top: 8, leading: 20, bottom: 16, trailing: 20))
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

