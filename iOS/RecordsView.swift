import SwiftUI

struct RecordsView: View {
    @EnvironmentObject private var store: RunStore

    var body: some View {
        PushedScreen(title: "Records") {
            let banner = store.latestBenchmark
            VStack(alignment: .leading, spacing: 0) {
                if let banner {
                    newestBanner(banner)
                }
                VStack(spacing: 0) {
                    ForEach(store.records) { record in
                        recordRow(record)
                        if record.id != store.records.last?.id {
                            Theme.hairline.frame(height: 1)
                        }
                    }
                }
                .padding(.top, banner == nil ? 0 : 14)

                // "Why is my 10 K from last autumn, when I have run past ten
                // kilometres all summer?" — because a record is a time, not a
                // distance covered, and nothing since has been faster. Said
                // here rather than left to be worked out.
                Text("Records come from your runs automatically. No badges, no confetti.\n\nA 5 K or 10 K record is the fastest continuous stretch of that distance inside any run — the run does not have to end there. Runs another app recorded arrive without kilometre splits, so those count at their average pace over the whole run, which is fair evidence but rarely a record. A longer run beats one of these only by being genuinely faster over the distance.")
                    .font(.sg(13)).foregroundStyle(Theme.muted).lineSpacing(3).padding(.top, 16)
            }
        }
    }

    private func newestBanner(_ b: RunStore.LatestBenchmark) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(b.isRecent ? "NEW · \(b.label)" : "YOUR BEST · \(b.label)")
                    .kicker(13, color: b.isRecent ? Theme.signal : Theme.bright, tracking: 0.14)
                    .fontWeight(.semibold)
                Spacer()
                Text(b.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.sg(13)).foregroundStyle(Theme.muted)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(b.value).font(.stat(56)).kerning(-2.2)
                if let delta = b.delta {
                    Text(delta).font(.stat(14)).foregroundStyle(Theme.bright)
                }
            }
            .padding(.top, 10)
        }
        .padding(EdgeInsets(top: 22, leading: 24, bottom: 22, trailing: 24))
        .frame(maxWidth: .infinity, alignment: .leading)
        // The accent belongs to something that just happened. An old best is
        // still the headline of this screen, but it is not news.
        .background((b.isRecent ? Theme.signal.opacity(0.08) : Theme.glassCardFill),
                    in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24)
            .stroke(b.isRecent ? Theme.signal.opacity(0.35) : Theme.glassCardStroke, lineWidth: 1))
    }

    private func recordRow(_ record: RecordEntry) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(record.label).font(.sg(16))
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(record.value).font(.stat(19))
                    .foregroundStyle(record.isUnset ? Theme.muted : Theme.ink)
                Text(record.delta ?? record.date.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.sg(12))
                    .foregroundStyle(record.isRaceCountdown ? Theme.signal : Theme.muted)
            }
        }
        .padding(.vertical, 19)
    }
}
