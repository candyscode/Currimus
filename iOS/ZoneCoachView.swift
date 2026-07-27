import SwiftUI

/// Switching on the one thing a watch can do that a phone cannot: tell you
/// where your heart rate is without you looking at anything.
///
/// The setting lives here rather than on the watch because it is a decision
/// made before a run, with room to explain what the two patterns mean — the
/// watch's job is to play them.
struct ZoneCoachView: View {
    @EnvironmentObject private var store: RunStore

    private var isOn: Bool { store.zoneCoachTarget != nil }

    var body: some View {
        PushedScreen(title: "Zone coaching") {
            VStack(alignment: .leading, spacing: 0) {
                Text("Most of a run is spent not looking at the watch, and an easy "
                     + "run drifts out of zone 2 slowly enough that nobody notices "
                     + "until it is over. Switch this on and the watch tells your "
                     + "wrist instead.")
                    .font(.sg(14)).foregroundStyle(Theme.bright).lineSpacing(3)

                ChevronRow(title: "Vibration cues", showsChevron: false) {
                    Toggle("Vibration cues", isOn: Binding(
                        get: { isOn },
                        // Zone 2 is where this matters most — it is the zone
                        // people actually try to hold, and the one they lose.
                        set: { store.zoneCoachTarget = $0 ? (store.zoneCoachTarget ?? 2) : nil }
                    ))
                    .toggleStyle(SignalToggleStyle())
                }
                .padding(.top, 10)
                .overlay(alignment: .bottom) { Theme.hairline.frame(height: 1) }

                if isOn {
                    Text("HOLD ME IN").kicker(13, color: Theme.bright, tracking: 0.12)
                        .padding(.top, 30)
                    VStack(spacing: 0) {
                        ForEach(1...5, id: \.self) { zone in
                            Button { store.zoneCoachTarget = zone } label: { row(zone) }
                                .buttonStyle(.plain)
                            if zone < 5 { Theme.hairline.frame(height: 1) }
                        }
                    }
                    .padding(.top, 6)

                    Text("WHAT YOU WILL FEEL").kicker(13, color: Theme.bright, tracking: 0.12)
                        .padding(.top, 30)
                    VStack(alignment: .leading, spacing: 14) {
                        pattern(title: "Quick pulses",
                                detail: "You are in the bottom 15 % of the zone. Pick it up a little.")
                        pattern(title: "Slow pulses",
                                detail: "You are in the top 15 %. Ease off before you lose the zone.")
                        pattern(title: "Three seconds of buzzing",
                                detail: "The zone is gone. The screen says which one you are in and which way to go.")
                    }
                    .padding(.top, 14)

                    Text("The cues repeat while you stay at the edge, and stop the moment "
                         + "you are back in the middle of the zone. Nothing sounds — "
                         + "Currimus speaks in vibration only.")
                        .font(.sg(13)).foregroundStyle(Theme.muted).lineSpacing(3).padding(.top, 22)
                }
            }
        }
    }

    private func row(_ zone: Int) -> some View {
        let selected = store.zoneCoachTarget == zone
        return HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 7).fill(Theme.zoneHeat[zone - 1])
                .frame(width: 30, height: 14)
            VStack(alignment: .leading, spacing: 3) {
                Text("Zone \(zone) · \(HRZones.zoneNames[zone - 1])").font(.sg(16))
                Text(range(zone)).font(.stat(13, weight: .regular)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 12)
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(selected ? Theme.signal : Theme.chipStroke)
        }
        .frame(minHeight: 58)
        .contentShape(Rectangle())
    }

    /// The zone in beats, so the choice is made against real numbers rather
    /// than a name — these are the runner's own boundaries, not a table.
    private func range(_ zone: Int) -> String {
        let bounds = store.zones.range(forZone: zone)
        return zone == 5
            ? String(localized: "\(bounds.lower)+ bpm")
            : String(localized: "\(bounds.lower)–\(bounds.upper) bpm")
    }

    private func pattern(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.signal)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.sg(15, weight: .semibold))
                Text(detail).font(.sg(13)).foregroundStyle(Theme.muted).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
