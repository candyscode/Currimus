import SwiftUI

/// The 10-foot home screen: this week's volume at a glance on the left, the
/// last run and freshest record on the right. A television is read at a
/// distance, so the layout is two wide columns of large type rather than the
/// iPhone's single scrolling stack.
struct TVDashboardView: View {
    @EnvironmentObject private var store: RunStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 48) {
                header

                HStack(alignment: .top, spacing: 48) {
                    weekPanel.frame(maxWidth: .infinity, alignment: .leading)
                        .scrollFocusable()
                    sidePanel.frame(width: 620)
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 60)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("CURRIMUS").font(.sg(24, weight: .bold)).kerning(3)
            Spacer()
            Text(verbatim: "\(Calendar.current.component(.year, from: .now)) · \(Int(store.yearKm)) km")
                .font(.stat(20, weight: .regular)).foregroundStyle(Theme.muted)
        }
    }

    // MARK: - Week

    private var weekPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                TVSectionLabel(text: "THIS WEEK")
                Spacer()
                Text("goal \(Int(store.weeklyGoalKm)) km")
                    .font(.stat(18, weight: .regular)).foregroundStyle(Theme.muted)
            }
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(Format.km(store.weekKm, decimals: 1)).font(.stat(120)).kerning(-5)
                Text("km").font(.sg(32)).foregroundStyle(Theme.bright)
                Spacer()
                Text("\(Int((store.weekGoalFraction * 100).rounded()))%")
                    .font(.stat(28)).foregroundStyle(Theme.signal)
            }
            .padding(.top, 8)

            TVWeekBars(kmPerDay: store.weekByDay).padding(.top, 28)
        }
    }

    // MARK: - Side (last run + record)

    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 40) {
            if let last = store.lastRun {
                VStack(alignment: .leading, spacing: 0) {
                    TVSectionLabel(text: "LAST RUN")
                    TVCard {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(last.name).font(.sg(26, weight: .semibold))
                                Spacer()
                                Text(last.date, format: .relative(presentation: .named))
                                    .font(.sg(18)).foregroundStyle(Theme.muted)
                            }
                            HStack(spacing: 44) {
                                TVStat(value: Format.km(last.distanceKm), label: "KM", valueSize: 44)
                                TVStat(value: Format.pace(last.paceSecPerKm), label: "/KM", valueSize: 44)
                                TVStat(value: "Z\(last.dominantZone)", label: "MOSTLY", accent: true, valueSize: 44)
                            }
                            .padding(.top, 24)
                            TVZoneHeatStrip(zoneSeconds: last.zoneSeconds, height: 14).padding(.top, 24)
                        }
                    }
                    .padding(.top, 16)
                }
                .scrollFocusable()
            }

            if let banner = store.latestBenchmark {
                VStack(alignment: .leading, spacing: 0) {
                    TVSectionLabel(text: "NEWEST RECORD")
                    recordBanner(banner).padding(.top, 16)
                }
                .scrollFocusable()
            }
        }
    }

    private func recordBanner(_ b: RunStore.LatestBenchmark) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("NEW · \(b.label)").kicker(18, color: Theme.signal, tracking: 0.14).fontWeight(.semibold)
                Spacer()
                Text(b.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.sg(18)).foregroundStyle(Theme.muted)
            }
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                Text(b.value).font(.stat(72)).kerning(-2.5)
                if let delta = b.delta {
                    Text(delta).font(.stat(20)).foregroundStyle(Theme.bright)
                }
            }
            .padding(.top, 14)
        }
        .padding(36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.signal.opacity(0.08), in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(Theme.signal.opacity(0.35), lineWidth: 1))
    }
}

#Preview {
    // Seeded store → the sample marathon build-up, no CloudKit needed. Lets the
    // 10-foot layout be judged in the Xcode canvas without a device or account.
    FontLoader.registerAll()
    return TVDashboardView()
        .environmentObject(RunStore(seeded: true))
        .preferredColorScheme(.dark)
}
