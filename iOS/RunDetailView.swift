import SwiftUI

struct RunDetailView: View {
    @EnvironmentObject private var store: RunStore
    @Environment(\.pushRoute) private var push
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    private let storedRun: Run

    init(run: Run) { storedRun = run }

    /// Looked up by id rather than held from the push, so an edit made one
    /// screen further in is reflected on the way back out. The log carries
    /// metadata only, so the track and elevation series come from the store's
    /// sidecar files, cached after the first ask.
    private var run: Run {
        store.hydrated(store.runs.first { $0.id == storedRun.id } ?? storedRun)
    }

    var body: some View {
        PushedScreen(title: run.isTrail ? "Trail run" : "Run") {
            VStack(alignment: .leading, spacing: 0) {
                if run.isTrail { trail } else { road }
                editCard
                deleteAction
            }
        }
        // Plain system alert, like the log's — one question, asked one way.
        .alert(
            DeletePrompt.title([run]),
            isPresented: $confirmingDelete
        ) {
            Button("Delete", role: .destructive) {
                store.delete(run)
                // Nothing is left to show — the screen reads a run that is no
                // longer in the log, so it leaves with it.
                dismiss()
            }
            Button("Cancel", role: .cancel) { confirmingDelete = false }
        } message: {
            Text(DeletePrompt.message([run]))
        }
    }

    private var editCard: some View {
        Button { push(.runEdit(storedRun)) } label: {
            GlassCard(cornerRadius: 20, padding: EdgeInsets(top: 18, leading: 22, bottom: 18, trailing: 22)) {
                HStack {
                    Text("Edit run").font(.sg(16, weight: .semibold))
                    Spacer()
                    Text(run.isImported ? "Imported" : run.classification.label)
                        .font(.sg(15)).foregroundStyle(Theme.bright)
                    Chevron()
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 30)
    }

    /// The last resort for a run that should never have been logged. Outlined
    /// rather than filled: it is the one thing on this screen that cannot be
    /// undone, so it does not get to look like the primary action.
    @ViewBuilder
    private var deleteAction: some View {
        if run.isImported {
            // Health owns it, and HealthKit will not let another app delete
            // another app's workout. Say where it can be done instead.
            Text("Recorded by \(run.name). This run belongs to Apple Health — delete it in the app that recorded it.")
                .font(.sg(13)).foregroundStyle(Theme.muted).lineSpacing(3)
                .padding(.top, 18)
        } else {
            Button { confirmingDelete = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trash").font(.system(size: 15, weight: .semibold))
                    Text("Delete run").font(.sg(16, weight: .semibold))
                }
                .foregroundStyle(Theme.signal)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Theme.glassCardFill, in: Capsule())
                .overlay(Capsule().stroke(Theme.signal.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
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

            // Cadence joins the row when the run measured it — a fourth column
            // rather than a replacement, since which of these three you came
            // for depends on the run.
            HStack(alignment: .top, spacing: run.cadenceSpm == nil ? 28 : 20) {
                DetailStat(value: Format.clock(run.duration), label: "TIME")
                DetailStat(value: Format.pace(run.paceSecPerKm), label: "AVG /KM", accent: true)
                DetailStat(value: "\(Int(run.climbMeters ?? 0)) m", label: "CLIMB")
                if let cadence = run.cadenceSpm {
                    DetailStat(value: "\(cadence)", label: "SPM")
                }
            }
            .padding(.top, 18)

            if isFastestPaceOfMonth {
                fastestPaceOfMonthLine.padding(.top, 12)
            }

            MapCard(run: run, height: 160).padding(.top, 22)

            splitsSection

            zonesSection.padding(.top, 26)
            hintsSection
        }
    }

    /// What the run says about how it was run, rather than how fast.
    ///
    /// Absent whenever there is nothing to say, which is most runs — a section
    /// that finds a correction every single time is one people stop reading.
    /// The list is whatever `RunHints` returns, so a second hint (or a written
    /// one) arrives here without this screen changing.
    @ViewBuilder
    private var hintsSection: some View {
        let hints = RunHints.all(for: run)
        if !hints.isEmpty {
            sectionLabel("NEXT TIME").padding(.top, 30).padding(.bottom, 14)
            VStack(spacing: 12) {
                ForEach(hints) { hint in
                    GlassCard(cornerRadius: 20,
                              padding: EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20)) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(hint.title).font(.sg(16, weight: .semibold))
                            Text(hint.body)
                                .font(.sg(13)).foregroundStyle(Theme.bright).lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    /// Nothing to fold down below two kilometres — and an imported run brings
    /// no splits at all, which used to render as a heading over empty space.
    @ViewBuilder
    private var splitsSection: some View {
        if run.splits.count >= 2 {
            sectionLabel("SPLITS").padding(.top, 26).padding(.bottom, 14)
            SplitsSummary(splits: run.splits)
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

            MapCard(run: run, height: 160).padding(.top, 22)

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

    /// Trail is excluded upstream — its pace never earns the accent, so this
    /// is only ever true on the road branch.
    private var isFastestPaceOfMonth: Bool { store.fastestPaceOfMonthHolders.contains(run.id) }

    private var fastestPaceOfMonthLine: some View {
        let month = run.date.formatted(.dateTime.month(.wide))
        let year = run.date.formatted(.dateTime.year(.twoDigits))
        return HStack(spacing: 6) {
            Image(systemName: "bolt.fill").font(.system(size: 11, weight: .semibold))
            Text("Fastest pace in \(month) \(year)").font(.sg(13, weight: .semibold))
        }
        .foregroundStyle(Theme.signal)
    }

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
            sectionLabel("TIME IN ZONES").padding(.bottom, 16)
            ZoneBreakdown(zoneSeconds: run.zoneSeconds)
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
