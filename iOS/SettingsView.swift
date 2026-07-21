import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var store: RunStore
    @Environment(\.pushRoute) private var push
    @State private var exportURLs: [URL]?

    var body: some View {
        PushedScreen(title: "Settings") {
            VStack(alignment: .leading, spacing: 0) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No account. No ads. No tracking.").font(.sg(16, weight: .semibold))
                        Text("No data sales, no marketing pushes. Currimus stays out of the way so your running stays in front. Runs sync to Apple Health — nothing else, nowhere else.")
                            .font(.sg(13)).foregroundStyle(Theme.bright).lineSpacing(2)
                    }
                }

                section("RUN")
                group {
                    ChevronRow(title: "Countdown before run", subtitle: "3 seconds, on the watch", showsChevron: false) {
                        Toggle("Countdown before run", isOn: $store.countdownEnabled).toggleStyle(SignalToggleStyle())
                    }
                    hairline
                    ChevronRow(title: "Kilometer alert", showsChevron: false) {
                        Toggle("Kilometer alert", isOn: $store.kilometerAlert).toggleStyle(SignalToggleStyle())
                    }
                    hairline
                    Button { push(.pacerDefaults) } label: {
                        ChevronRow(title: "Pacer defaults") {
                            Text("\(Format.pace(store.pacerTargetSecPerKm)) /km · \(pacerDistanceLabel)")
                        }
                    }.buttonStyle(.plain)
                    hairline
                    // Says what it does *not* do as well: the watch dims the
                    // panel and drops to 1 Hz on its own either way.
                    ChevronRow(
                        title: "Dim screen when wrist is down",
                        subtitle: "Turns the run screen down while you are not looking. The watch dims and slows the display by itself regardless — this only stops Currimus reducing further.",
                        showsChevron: false
                    ) {
                        Toggle("", isOn: $store.alwaysOnReduced).toggleStyle(SignalToggleStyle())
                    }
                }

                section("RACE & ZONES")
                group {
                    Button { push(.raceSetup) } label: {
                        ChevronRow(title: "Target race") { Text(raceLabel) }
                    }.buttonStyle(.plain)
                    hairline
                    Button { push(.hrZones) } label: {
                        ChevronRow(title: "Heart rate zones") { Text("Max \(store.zones.maxHR)") }
                    }.buttonStyle(.plain)
                    hairline
                    Menu {
                        ForEach(Array(stride(from: 20, through: 90, by: 5)), id: \.self) { goal in
                            Button("\(goal) km") { store.weeklyGoalKm = Double(goal) }
                        }
                    } label: {
                        ChevronRow(title: "Weekly goal") { Text("\(Int(store.weeklyGoalKm)) km") }
                    }
                }

                section("PREFERENCES")
                group {
                    Button { push(.gpsAccuracy) } label: {
                        ChevronRow(title: "GPS accuracy") { Text(store.gpsAccuracy.label) }
                    }.buttonStyle(.plain)
                    hairline
                    ChevronRow(title: "Apple Health", showsChevron: false) {
                        Text("Connected").foregroundStyle(Theme.signal)
                    }
                    hairline
                    // Recording lives on the watch, so whether there is one is
                    // worth stating rather than leaving the user to infer it
                    // from a log that never fills.
                    ChevronRow(title: "Apple Watch", subtitle: watchSubtitle, showsChevron: false) {
                        Text(watchLabel).foregroundStyle(watchTint)
                    }
                    hairline
                    Button(action: exportRuns) {
                        ChevronRow(title: "Export all runs", showsChevron: false) { Text("GPX / CSV") }
                    }.buttonStyle(.plain)
                }
            }
        }
        .sheet(item: Binding(get: { exportURLs.map(ExportPayload.init) }, set: { exportURLs = $0?.urls })) { payload in
            ActivityView(items: payload.urls)
        }
    }

    private var pacerDistanceLabel: String {
        store.pacerDefaultDistanceKm.map { $0 == 21.0975 ? "21.1 km" : "\(Int($0)) km" } ?? "Off"
    }

    private var watchLabel: String {
        switch store.watchState {
        case .ready: return "Ready"
        case .appMissing: return "App missing"
        case .noWatch: return "None paired"
        case .unknown: return "—"
        }
    }

    private var watchSubtitle: String? {
        switch store.watchState {
        case .appMissing: return "Install Currimus from the Watch app, under Available Apps."
        case .noWatch: return "Without a watch, Currimus reads your Apple Health runs but cannot record."
        case .ready, .unknown: return nil
        }
    }

    private var watchTint: Color {
        store.watchState == .ready ? Theme.signal : Theme.bright
    }

    private var raceLabel: String {
        guard let race = store.race else { return "None" }
        return "\(race.distance.name) · \(race.daysUntil()) days"
    }

    private func exportRuns() {
        do {
            // GPX needs the tracks, which live outside the log.
            exportURLs = try RunExport.exportFiles(store.runs.map(store.hydrated))
        } catch {
            Log.store.error("export failed: \(error.localizedDescription, privacy: .public)")
            exportURLs = nil
        }
    }

    private func section(_ t: String) -> some View {
        Text(t).kicker(13, color: Theme.bright, tracking: 0.12).padding(.top, 26)
    }

    private func group<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 0) { content() }.padding(.top, 4)
    }

    private var hairline: some View { Theme.hairline.frame(height: 1) }
}

struct ExportPayload: Identifiable {
    let urls: [URL]
    var id: String { urls.map(\.lastPathComponent).joined() }
}

/// UIActivityViewController bridge for the share sheet.
struct ActivityView: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Pacer defaults

struct PacerDefaultsView: View {
    @EnvironmentObject private var store: RunStore

    private let distances: [Double?] = [nil, 5, 10, 15, 21.0975]

    var body: some View {
        PushedScreen(title: "Pacer defaults") {
            VStack(alignment: .leading, spacing: 0) {
                fieldLabel("DEFAULT PACE")
                PaceDefaultWheel(seconds: $store.pacerTargetSecPerKm).padding(.top, 10)

                fieldLabel("DEFAULT DISTANCE").padding(.top, 30)
                HStack(spacing: 10) {
                    ForEach(Array(distances.enumerated()), id: \.offset) { _, d in
                        let active = d == store.pacerDefaultDistanceKm
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { store.pacerDefaultDistanceKm = d }
                        } label: {
                            Text(d.map { $0 == 21.0975 ? "21.1" : "\(Int($0))" } ?? "Off")
                                .font(.sg(15, weight: active ? .bold : .semibold))
                                .foregroundStyle(active ? Theme.bg : Theme.bright)
                                .frame(maxWidth: .infinity).frame(height: 48)
                                .background {
                                    if active { Capsule().fill(Theme.signal) }
                                    else { Capsule().fill(Theme.chipFill).overlay(Capsule().stroke(Theme.chipStroke, lineWidth: 1)) }
                                }
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.top, 14)

                fieldLabel("AT THESE DEFAULTS").padding(.top, 30)
                VStack(spacing: 0) {
                    projection("10 km", store.pacerTargetSecPerKm * 10)
                    hairline
                    projection("Half marathon", store.pacerTargetSecPerKm * 21.0975)
                }
                .padding(.top, 4)

                Text("The watch starts every Pacer setup with these values — change either with the crown before you run. Syncs instantly.")
                    .font(.sg(13)).foregroundStyle(Theme.muted).lineSpacing(3).padding(.top, 18)
            }
        }
    }

    private func projection(_ label: String, _ seconds: TimeInterval) -> some View {
        HStack {
            Text(label).font(.sg(16))
            Spacer()
            Text(Format.clock(seconds)).font(.stat(16))
        }
        .frame(minHeight: 52)
    }

    private func fieldLabel(_ t: String) -> some View { Text(t).kicker(13, color: Theme.bright, tracking: 0.12) }
    private var hairline: some View { Theme.hairline.frame(height: 1) }
}

/// Five-row pace wheel, 5 s steps.
struct PaceDefaultWheel: View {
    @Binding var seconds: TimeInterval
    private let step: TimeInterval = 5
    @State private var drag: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            ghost(seconds + 2 * step, 20, 0x3d3d3d)
            ghost(seconds + step, 24, 0x575757)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Spacer()
                Text(Format.pace(seconds)).font(.stat(56)).kerning(-1.7).contentTransition(.numericText())
                Text("/km").font(.sg(16)).foregroundStyle(Theme.bright)
                Spacer()
            }
            .padding(.vertical, 12)
            .overlay(alignment: .top) { Theme.buttonBorder.frame(height: 1) }
            .overlay(alignment: .bottom) { Theme.buttonBorder.frame(height: 1) }
            ghost(seconds - step, 24, 0x575757)
            ghost(seconds - 2 * step, 20, 0x3d3d3d)
        }
        .contentShape(Rectangle())
        .gesture(DragGesture()
            .onChanged { v in
                let d = v.translation.height - drag
                if abs(d) > 18 { shift(d > 0 ? 1 : -1); drag = v.translation.height }
            }
            .onEnded { _ in drag = 0 })
    }

    private func ghost(_ v: TimeInterval, _ size: CGFloat, _ hex: UInt32) -> some View {
        Button { withAnimation(.snappy(duration: 0.18)) { seconds = clamp(v) } } label: {
            Text(Format.pace(v)).font(.stat(size)).foregroundStyle(Color(hex: hex))
                .frame(maxWidth: .infinity).padding(.vertical, 8)
        }.buttonStyle(.plain)
    }
    private func shift(_ dir: Int) { withAnimation(.snappy(duration: 0.18)) { seconds = clamp(seconds + Double(dir) * step) } }
    private func clamp(_ v: TimeInterval) -> TimeInterval { min(max(v, 180), 600) }
}

// MARK: - Heart rate zones

struct HRZonesView: View {
    @EnvironmentObject private var store: RunStore

    var body: some View {
        PushedScreen(title: "Heart rate zones") {
            VStack(alignment: .leading, spacing: 0) {
                Text("MAX HEART RATE").kicker(13, color: Theme.bright, tracking: 0.12)
                HStack(spacing: 20) {
                    Text("\(store.zones.maxHR)").font(.stat(72)).kerning(-2.9)
                    Spacer()
                    stepButton("−") { setMax(store.zones.maxHR - 1) }
                    stepButton("+") { setMax(store.zones.maxHR + 1) }
                }
                .padding(.top, 14)

                if let derivation = store.zones.derivation {
                    Text(derivation.maxExplanation)
                        .font(.sg(13)).foregroundStyle(Theme.muted).lineSpacing(3)
                        .padding(.top, 10)
                }

                if let resting = store.zones.restingHR {
                    HStack {
                        Text("Resting heart rate").font(.sg(16))
                        Spacer()
                        Text("\(resting) bpm").font(.stat(16, weight: .regular)).foregroundStyle(Theme.bright)
                    }
                    .frame(minHeight: 52)
                    .padding(.top, 8)
                    .overlay(alignment: .bottom) { Theme.hairline.frame(height: 1) }
                }

                Button {
                    Task { await store.refreshHeartRateZones(force: true, requestingAccess: true) }
                } label: {
                    Text(store.zones.derivation == nil
                         ? "Calculate from Apple Health"
                         : "Recalculate from Apple Health")
                        .font(.sg(15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Theme.chipFill, in: Capsule())
                        .overlay(Capsule().stroke(Theme.chipStroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.top, 18)

                Text("ZONES").kicker(13, color: Theme.bright, tracking: 0.12).padding(.top, 34)
                VStack(spacing: 0) {
                    ForEach(1...5, id: \.self) { zone in
                        zoneRow(zone)
                        if zone < 5 { Theme.hairline.frame(height: 1) }
                    }
                }
                .padding(.top, 6)

                Text(zoneExplanation)
                    .font(.sg(13)).foregroundStyle(Theme.muted).lineSpacing(3).padding(.top, 18)
            }
        }
    }

    /// Says plainly where the boundaries came from — a personalised number the
    /// user cannot account for is worse than a generic one.
    private var zoneExplanation: String {
        let tail = " Tap any zone to override — the watch shows zone position, never BPM."
        if store.zones.overrides != nil {
            return "You set these boundaries by hand. Recalculating from Apple Health replaces them."
        }
        guard let derivation = store.zones.derivation else {
            return "Boundaries follow max HR automatically, at 60 / 70 / 80 / 90 % of it." + tail
        }
        return derivation.zoneExplanation(usesReserve: store.zones.usesReserve) + tail
    }

    private func zoneRow(_ zone: Int) -> some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 7).fill(Theme.zoneHeat[zone - 1]).frame(width: 30, height: 14)
            Text("Zone \(zone) · \(HRZones.zoneNames[zone - 1])").font(.sg(16))
            Spacer()
            if zone < 5 {
                Menu {
                    Button("Lower bound") { adjustBound(zone, by: -1) }
                    Button("Raise bound") { adjustBound(zone, by: 1) }
                } label: {
                    Text(store.zones.label(forZone: zone)).font(.stat(16, weight: .regular)).foregroundStyle(Theme.bright)
                }
            } else {
                Text(store.zones.label(forZone: zone)).font(.stat(16, weight: .regular)).foregroundStyle(Theme.bright)
            }
        }
        .frame(minHeight: 58)
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(symbol).font(.system(size: 26)).foregroundStyle(Theme.ink)
                .frame(width: 52, height: 52)
                .background(Theme.chipFill, in: Circle())
                .overlay(Circle().stroke(Theme.chipStroke, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private func setMax(_ value: Int) {
        var z = store.zones
        z.maxHR = min(max(value, 140), 220)
        z.overrides = nil   // recompute from the new max
        // The number is the user's now — stop attributing it to Health.
        z.derivation = z.derivation.map {
            HRDerivation(maxSource: .manual, maxDate: nil, age: $0.age,
                         restingHR: $0.restingHR, restingSampleDays: $0.restingSampleDays)
        }
        store.zones = z
    }

    private func adjustBound(_ zone: Int, by delta: Int) {
        var z = store.zones
        var bounds = z.overrides ?? z.bounds
        bounds[zone - 1] = min(max(bounds[zone - 1] + delta, 60), z.maxHR - 1)
        z.overrides = bounds
        store.zones = z
    }
}

// MARK: - GPS accuracy

/// The one setting that trades recording precision for battery life, so it
/// says plainly what each step costs rather than hiding behind a label.
struct GPSAccuracyView: View {
    @EnvironmentObject private var store: RunStore

    var body: some View {
        PushedScreen(title: "GPS accuracy") {
            VStack(alignment: .leading, spacing: 0) {
                Text("GPS is the largest single battery draw of a recorded run — "
                     + "far more than the screen. Lowering it buys hours; it costs "
                     + "detail on tight, winding routes.")
                    .font(.sg(14)).foregroundStyle(Theme.bright).lineSpacing(3)

                VStack(spacing: 0) {
                    ForEach(GPSAccuracy.allCases) { option in
                        Button { store.gpsAccuracy = option } label: { row(option) }
                            .buttonStyle(.plain)
                        if option != GPSAccuracy.allCases.last { Theme.hairline.frame(height: 1) }
                    }
                }
                .padding(.top, 22)

                Text("Elevation and climb come from GPS too, so trail runs are worth "
                     + "keeping on High.")
                    .font(.sg(13)).foregroundStyle(Theme.muted).lineSpacing(3).padding(.top, 18)
            }
        }
    }

    private func row(_ option: GPSAccuracy) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(option.label).font(.sg(16, weight: .semibold))
                    if option == .high {
                        Text("DEFAULT").font(.sg(10, weight: .bold)).kerning(1)
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Theme.chipFill, in: Capsule())
                    }
                }
                Text(option.detail)
                    .font(.sg(13)).foregroundStyle(Theme.muted).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Image(systemName: store.gpsAccuracy == option ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(store.gpsAccuracy == option ? Theme.signal : Theme.chipStroke)
                .padding(.top, 2)
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }
}
