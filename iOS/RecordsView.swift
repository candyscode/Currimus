import SwiftUI

struct RecordsView: View {
    @EnvironmentObject private var store: RunStore
    @State private var explaining: Explanation?

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

                // The four sentences that used to sit here explained the whole
                // mechanism in one block of grey text and were, in Andi's
                // words, not understandable at all (CUR-38). One sentence
                // stays; the mechanism moved behind the ⓘ, like every other
                // derivation in the app.
                HStack(spacing: 2) {
                    Text("HOW A RECORD IS FOUND")
                        .kicker(13, color: Theme.bright, tracking: 0.12).fixedSize()
                    InfoButton(label: "a record") { explaining = Self.method }
                        .padding(.leading, -6)
                }
                .padding(.top, 26)

                Text("Records come from your runs automatically. No badges, no confetti.")
                    .font(.sg(13)).foregroundStyle(Theme.muted).lineSpacing(3).padding(.top, 8)
            }
        }
        .explanationSheet($explaining)
        .onAppear { if DebugFlags.opensExplanation { explaining = Self.method } }
    }

    /// What "record" means here, in full.
    ///
    /// Two readings, and both are worth knowing about: the one inside a run is
    /// tied to kilometre markers, and the one from a whole run can only ever
    /// understate the runner. Neither was said out loud before.
    private static let method = Explanation(
        title: String(localized: "How a record is found"),
        body: String(localized: """
        A record here is a **time over a distance** — the fastest you have covered it. Not a distance you have run past: a 15 km easy run does not touch your 10 km record unless the fastest ten kilometres of it were quicker than that record.

        There are two ways a run can hold one, and the faster of the two wins, so an estimate never displaces a real effort.

        **The fastest stretch inside a run.** For 1, 5 and 10 km, Currimus looks for the fastest run of that many kilometres *in a row* anywhere inside a run — the run does not have to end there, and the fastest 5 km of a 12 km run counts. It reads the per-kilometre splits, so the stretch begins and ends on a kilometre marker; a genuinely faster stretch that straddles two markers can be a handful of seconds quicker than what is filed here.

        **The whole run, scaled.** Runs another app recorded arrive as one distance and one duration, with no splits to search. All that can be read is the average pace over the whole run, held against the benchmark — a 12 km run at 5:00 /km stands as a 10 km in 50:00. That is deliberately cautious: the fastest 10 km inside that run was quicker than its average, so this reading can only ever understate you. Only runs up to two and a half times the benchmark are read this way, which is why a marathon counts as evidence for a half and never as a 1 km.

        The half marathon and the marathon have no splits reading at all — over those distances the whole run *is* the effort.
        """))

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
