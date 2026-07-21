import SwiftUI

struct RunDetailView: View {
    @EnvironmentObject private var store: RunStore
    private let storedRun: Run

    init(run: Run) { storedRun = run }

    /// The log carries metadata only — the elevation series and the GPS track
    /// come out of the store's sidecar files, cached after the first ask.
    private var run: Run { store.hydrated(storedRun) }

    var body: some View {
        PushedScreen(title: run.isTrail ? "Trail run" : "Run") {
            if run.isTrail { trail } else { road }
        }
    }

    // MARK: - Road

    private var road: some View {
        VStack(alignment: .leading, spacing: 0) {
            dateLine
            Text(run.name).font(.sg(30, weight: .semibold)).kerning(-0.6).padding(.top, 4)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Format.km(run.distanceKm)).font(.stat(76)).kerning(-3.4)
                Text("km").font(.sg(20)).foregroundStyle(Theme.bright)
            }
            .padding(.top, 18)

            HStack(alignment: .top, spacing: 28) {
                DetailStat(value: Format.clock(run.duration), label: "TIME")
                DetailStat(value: Format.pace(run.paceSecPerKm), label: "AVG /KM", accent: true)
                DetailStat(value: "\(Int(run.climbMeters ?? 0)) m", label: "CLIMB")
            }
            .padding(.top, 18)

            MapCard(run: run, height: 160).padding(.top, 22)

            sectionLabel("SPLITS /KM").padding(.top, 26).padding(.bottom, 14)
            SplitBars(splits: run.splits)

            zonesSection.padding(.top, 26)
        }
    }

    // MARK: - Trail

    private var trail: some View {
        VStack(alignment: .leading, spacing: 0) {
            dateLine
            Text(run.name).font(.sg(30, weight: .semibold)).kerning(-0.6).padding(.top, 4)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(grouped(Int(run.climbMeters ?? 0)))
                    .font(.stat(76)).kerning(-3.4).foregroundStyle(Theme.signal)
                Text("m climb").font(.sg(20)).foregroundStyle(Theme.bright)
            }
            .padding(.top, 18)

            HStack(alignment: .top, spacing: 28) {
                DetailStat(value: Format.km(run.distanceKm, decimals: 1), label: "KM")
                DetailStat(value: Format.clock(run.duration), label: "TIME")
                DetailStat(value: "\(Int(climbRate))", label: "CLIMB M/H")
            }
            .padding(.top, 18)

            sectionLabel("ELEVATION").padding(.top, 28).padding(.bottom, 12)
            ElevationProfile(samples: run.altitudeSamples ?? [], height: 120)
            HStack {
                Text("0 km")
                Spacer()
                Text("high point · \(grouped(Int(run.highPointMeters ?? 0))) m")
                Spacer()
                Text("\(Format.km(run.distanceKm, decimals: 1)) km")
            }
            .font(.stat(12, weight: .regular)).foregroundStyle(Theme.muted).padding(.top, 6)

            Grid(alignment: .topLeading, horizontalSpacing: 20, verticalSpacing: 22) {
                GridRow {
                    DetailStat(value: Format.pace(run.paceSecPerKm), label: "AVG /KM").gridExpand()
                    DetailStat(value: Format.pace(RunAnalytics.gradeAdjustedPace(run)), label: "GRADE-ADJUSTED /KM", accent: true).gridExpand()
                }
                GridRow {
                    DetailStat(value: "\(grouped(Int(run.descentMeters ?? 0))) m", label: "DESCENT").gridExpand()
                    DetailStat(value: "\(maxGradePercent)%", label: "MAX GRADE").gridExpand()
                }
            }
            .padding(.top, 26)

            zonesSection.padding(.top, 26)
            Text("Uphill, pace lies — climb rate and grade-adjusted pace tell the truth. Same rule as on the watch.")
                .font(.sg(13)).foregroundStyle(Theme.muted).lineSpacing(3).padding(.top, 18)
        }
    }

    // MARK: - Shared

    private var dateLine: some View {
        let stamp = run.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased()
            + " · " + run.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        let tag = run.isTrail
            ? Text(" · TRAIL").foregroundStyle(Theme.signal).fontWeight(.semibold)
            : Text(verbatim: "")
        return Text("\(Text(stamp).foregroundStyle(Theme.bright))\(tag)")
            .font(.sg(13, weight: .medium)).kerning(13 * 0.12)
        .lineLimit(1).minimumScaleFactor(0.8)
    }

    private var zonesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("TIME IN ZONES").padding(.bottom, 14)
            ZoneHeatStrip(zoneSeconds: run.zoneSeconds, height: 12)
            HStack {
                ForEach(0..<5, id: \.self) { z in
                    Text("Z\(z + 1) · \(Int(run.zoneSeconds[z] / 60))m")
                        .font(.stat(12, weight: .regular)).foregroundStyle(Theme.muted)
                    if z < 4 { Spacer() }
                }
            }
            .padding(.top, 10)
        }
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t).kicker(13, color: Theme.bright, tracking: 0.12)
    }

    private var climbRate: Double { (run.climbMeters ?? 0) / max(run.duration / 3600, 0.01) }

    private var maxGradePercent: Int {
        guard let samples = run.altitudeSamples, samples.count > 1, run.distanceKm > 0 else { return 0 }
        let step = run.distanceKm * 1000 / Double(samples.count - 1)
        var maxGrade = 0.0
        for i in 1..<samples.count {
            maxGrade = max(maxGrade, abs(samples[i] - samples[i - 1]) / step)
        }
        return Int((maxGrade * 100).rounded())
    }

    private func grouped(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = " "
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

struct DetailStat: View {
    var value: String
    var label: String
    var accent: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.stat(24)).foregroundStyle(accent ? Theme.signal : Theme.ink).lineLimit(1)
            Text(label).kicker(13, color: Theme.bright, tracking: 0.12).fixedSize()
        }
    }
}

private extension View {
    func gridExpand() -> some View { frame(maxWidth: .infinity, alignment: .leading) }
}
