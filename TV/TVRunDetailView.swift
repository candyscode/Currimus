import SwiftUI

/// One run in full, on the big screen. Road runs lead with distance, the route
/// map and per-km splits; trail runs lead with climb, the elevation profile and
/// the grade stats — the same split the iPhone's `RunDetailView` draws, laid
/// out in two columns for a television.
///
/// The run arrives from the log carrying metadata only; `store.hydrated` puts
/// its GPS track and altitude series back from the sidecar the TV populated
/// when CloudKit's sample asset came down.
struct TVRunDetailView: View {
    @EnvironmentObject private var store: RunStore
    private let storedRun: Run

    init(run: Run) { storedRun = run }

    private var run: Run { store.hydrated(storedRun) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 44) {
                headline
                if run.isTrail { trailBody } else { roadBody }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 60)
        }
    }

    // MARK: - Headline

    private var headline: some View {
        VStack(alignment: .leading, spacing: 8) {
            dateLine
            Text(run.name).font(.sg(48, weight: .semibold)).kerning(-1).padding(.top, 4)
        }
    }

    private var dateLine: some View {
        let stamp = run.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased()
            + " · " + run.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        return (
            Text(stamp).foregroundStyle(Theme.bright)
            + (run.isTrail
               ? Text(" · TRAIL").foregroundStyle(Theme.signal).fontWeight(.semibold)
               : Text(verbatim: ""))
        )
        .font(.sg(20, weight: .medium)).kerning(20 * 0.12)
    }

    // MARK: - Road

    private var roadBody: some View {
        HStack(alignment: .top, spacing: 60) {
            VStack(alignment: .leading, spacing: 36) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(Format.km(run.distanceKm)).font(.stat(104)).kerning(-4)
                    Text("km").font(.sg(30)).foregroundStyle(Theme.bright)
                }
                HStack(spacing: 52) {
                    TVStat(value: Format.clock(run.duration), label: "TIME", valueSize: 40)
                    TVStat(value: Format.pace(run.paceSecPerKm), label: "AVG /KM", accent: true, valueSize: 40)
                    TVStat(value: "\(Int(run.climbMeters ?? 0)) m", label: "CLIMB", valueSize: 40)
                }
                zonesSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 20) {
                TVRouteCard(run: run)
                if !run.splits.isEmpty {
                    TVSectionLabel(text: "SPLITS /KM").padding(.top, 12)
                    TVSplitBars(splits: run.splits)
                }
            }
            .frame(width: 640)
        }
    }

    // MARK: - Trail

    private var trailBody: some View {
        VStack(alignment: .leading, spacing: 44) {
            HStack(alignment: .top, spacing: 60) {
                VStack(alignment: .leading, spacing: 36) {
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text(grouped(Int(run.climbMeters ?? 0)))
                            .font(.stat(104)).kerning(-4).foregroundStyle(Theme.signal)
                        Text("m climb").font(.sg(30)).foregroundStyle(Theme.bright)
                    }
                    HStack(spacing: 52) {
                        TVStat(value: Format.km(run.distanceKm, decimals: 1), label: "KM", valueSize: 40)
                        TVStat(value: Format.clock(run.duration), label: "TIME", valueSize: 40)
                        TVStat(value: "\(Int(climbRate))", label: "CLIMB M/H", valueSize: 40)
                    }
                    HStack(spacing: 52) {
                        TVStat(value: Format.pace(run.paceSecPerKm), label: "AVG /KM", valueSize: 40)
                        TVStat(value: Format.pace(RunAnalytics.gradeAdjustedPace(run)),
                               label: "GRADE-ADJUSTED /KM", accent: true, valueSize: 40)
                        TVStat(value: "\(grouped(Int(run.descentMeters ?? 0))) m", label: "DESCENT", valueSize: 40)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 16) {
                    TVSectionLabel(text: "ELEVATION")
                    TVElevationProfile(samples: run.altitudeSamples ?? [])
                    HStack {
                        Text("0 km")
                        Spacer()
                        Text("high point · \(grouped(Int(run.highPointMeters ?? 0))) m")
                        Spacer()
                        Text("\(Format.km(run.distanceKm, decimals: 1)) km")
                    }
                    .font(.stat(16, weight: .regular)).foregroundStyle(Theme.muted)
                }
                .frame(width: 640)
            }
            zonesSection
        }
    }

    // MARK: - Shared

    private var zonesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            TVSectionLabel(text: "TIME IN ZONES").padding(.bottom, 16)
            TVZoneHeatStrip(zoneSeconds: run.zoneSeconds, height: 22)
            HStack {
                ForEach(0..<5, id: \.self) { z in
                    Text("Z\(z + 1) · \(Int(run.zoneSeconds[z] / 60))m")
                        .font(.stat(16, weight: .regular)).foregroundStyle(Theme.muted)
                    if z < 4 { Spacer() }
                }
            }
            .padding(.top, 14)
        }
    }

    private var climbRate: Double { (run.climbMeters ?? 0) / max(run.duration / 3600, 0.01) }

    private func grouped(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = " "
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
