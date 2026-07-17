import SwiftUI

/// Everything on one screen — the run itself lives on the watch.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: RunStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(title: "Home") { dismiss() }

                Text("Settings")
                    .font(.system(size: 26, weight: .semibold))
                    .kerning(-0.5)
                    .padding(.top, 16)

                Text("HEART RATE ZONES · MAX \(store.zones.maxHR)").kicker(12).padding(.top, 28)
                VStack(spacing: 0) {
                    ForEach(1...5, id: \.self) { zone in
                        if zone > 1 { Theme.hairline.frame(height: 1) }
                        HStack(spacing: 14) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Theme.zoneHeat[zone - 1])
                                .frame(width: 26, height: 12)
                            Text("Zone \(zone)").font(.system(size: 14))
                            Spacer()
                            Text(store.zones.label(forZone: zone))
                                .font(.stat(14, weight: .regular))
                                .foregroundStyle(Theme.muted)
                        }
                        .padding(.vertical, 11)
                    }
                }
                .padding(.top, 14)

                Text("PREFERENCES").kicker(12).padding(.top, 28)
                VStack(spacing: 0) {
                    SettingsRow(label: "Units") {
                        Text(store.usesKilometers ? "Kilometers" : "Miles")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.muted)
                    }
                    Theme.hairline.frame(height: 1)
                    SettingsRow(label: "Kilometer alert") {
                        Toggle("", isOn: $store.kilometerAlert)
                            .labelsHidden()
                            .tint(Theme.signal)
                    }
                    Theme.hairline.frame(height: 1)
                    NavigationLink(value: "pacer") {
                        SettingsRow(label: "Pacer target") {
                            Text("\(Format.pace(store.pacerTargetSecPerKm)) /km ›")
                                .font(.stat(14, weight: .regular))
                                .foregroundStyle(Theme.muted)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Theme.hairline.frame(height: 1)
                    SettingsRow(label: "Weekly goal") {
                        Text("\(Int(store.weeklyGoalKm)) km")
                            .font(.stat(14, weight: .regular))
                            .foregroundStyle(Theme.muted)
                    }
                    Theme.hairline.frame(height: 1)
                    SettingsRow(label: "Apple Health") {
                        Text("Connected")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.signal)
                    }
                }
                .padding(.top, 6)
            }
            .padding(28)
        }
        .background(Theme.bg)
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct SettingsRow<Trailing: View>: View {
    var label: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(label).font(.system(size: 14))
            Spacer()
            trailing
        }
        .padding(.vertical, 13)
    }
}

/// Set it here, run it on the watch.
struct PacerTargetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: RunStore

    private let paces: [TimeInterval] = stride(from: 240.0, through: 420.0, by: 5.0).map { $0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(title: "Settings") { dismiss() }

                Text("Pacer target")
                    .font(.system(size: 26, weight: .semibold))
                    .kerning(-0.5)
                    .padding(.top, 16)

                PaceWheel(target: $store.pacerTargetSecPerKm, paces: paces)
                    .padding(.top, 24)

                Text("AT THIS PACE").kicker(12).padding(.top, 26)
                VStack(spacing: 0) {
                    PaceProjection(label: "5 km", seconds: store.pacerTargetSecPerKm * 5)
                    Theme.hairline.frame(height: 1)
                    PaceProjection(label: "10 km", seconds: store.pacerTargetSecPerKm * 10)
                    Theme.hairline.frame(height: 1)
                    PaceProjection(label: "Half marathon", seconds: store.pacerTargetSecPerKm * 21.0975)
                }
                .padding(.top, 6)

                Text("Syncs to your Apple Watch. You can still change it there with the crown.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .lineSpacing(3)
                    .padding(.top, 14)
            }
            .padding(28)
        }
        .background(Theme.bg)
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct PaceProjection: View {
    var label: String
    var seconds: TimeInterval

    var body: some View {
        HStack {
            Text(label).font(.system(size: 14))
            Spacer()
            Text(Format.clock(seconds)).font(.stat(14))
        }
        .padding(.vertical, 13)
    }
}

/// The neighborhood wheel — drag or tap the neighbors to move in 5 s steps.
struct PaceWheel: View {
    @Binding var target: TimeInterval
    var paces: [TimeInterval]
    @State private var dragAccumulator: CGFloat = 0

    private func shift(_ steps: Int) {
        guard let index = paces.firstIndex(of: target) else {
            target = paces.min(by: { abs($0 - target) < abs($1 - target) }) ?? 315
            return
        }
        let next = min(max(index + steps, 0), paces.count - 1)
        withAnimation(.snappy(duration: 0.18)) { target = paces[next] }
    }

    var body: some View {
        VStack(spacing: 0) {
            ghostRow(target - 10, size: 17, color: Theme.ghost, step: -2)
            ghostRow(target - 5, size: 20, color: Color(hex: 0x575757), step: -1)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Format.pace(target))
                    .font(.stat(44))
                    .kerning(-1.2)
                    .contentTransition(.numericText())
                Text("/km").font(.system(size: 14)).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .overlay(alignment: .top) { Theme.buttonBorder.frame(height: 1) }
            .overlay(alignment: .bottom) { Theme.buttonBorder.frame(height: 1) }
            ghostRow(target + 5, size: 20, color: Color(hex: 0x575757), step: 1)
            ghostRow(target + 10, size: 17, color: Theme.ghost, step: 2)
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    let delta = value.translation.height - dragAccumulator
                    if abs(delta) > 24 {
                        shift(delta > 0 ? -1 : 1)
                        dragAccumulator = value.translation.height
                    }
                }
                .onEnded { _ in dragAccumulator = 0 }
        )
    }

    private func ghostRow(_ pace: TimeInterval, size: CGFloat, color: Color, step: Int) -> some View {
        Button { shift(step) } label: {
            Text(Format.pace(pace))
                .font(.stat(size))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .opacity(paces.contains(pace) ? 1 : 0)
    }
}
