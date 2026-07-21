import SwiftUI

struct LogView: View {
    @EnvironmentObject private var store: RunStore
    @Environment(\.pushRoute) private var push
    @State private var filter: RunStore.LogFilter = .all
    /// Set by the row's delete action; the confirmation reads it back.
    @State private var pendingDelete: Run?

    var body: some View {
        // Cached in the store — this used to recompute the fastest 5 K and
        // 10 K window across the whole log on every body pass.
        let holders = store.benchmarkHolders
        return TabScreen(topInset: 8) { EmptyView() } content: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Runs").font(.sg(38, weight: .semibold)).kerning(-0.8)
                    Spacer()
                    Text(verbatim: "\(Calendar.current.component(.year, from: .now)) · \(Int(store.yearKm)) km")
                        .font(.stat(13, weight: .regular)).foregroundStyle(Theme.muted)
                }
                .padding(.top, 6)

                SegmentChips(options: [(.all, "All"), (.road, "Road"), (.trail, "Trail")],
                             selection: $filter)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 250, alignment: .leading)
                    .padding(.top, 18)

                ForEach(store.runsByMonth(filter), id: \.month) { group in
                    Text(monthLabel(group).uppercased())
                        .kicker(13, color: Theme.bright, tracking: 0.12)
                        .padding(.top, 26).padding(.bottom, 12)
                        .overlay(alignment: .bottom) { Theme.hairline.frame(height: 1) }
                    ForEach(group.runs) { run in
                        Button { push(.runDetail(run)) } label: {
                            LogRow(run: run, prTag: holders[run.id])
                        }
                        .buttonStyle(.plain)
                        .contextMenu { deleteAction(run) }
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete this run?",
            isPresented: Binding(get: { pendingDelete != nil },
                                 set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { run in
            Button("Delete", role: .destructive) {
                store.delete(run)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { run in
            Text("\(Format.km(run.distanceKm)) km, \(run.date.formatted(.dateTime.day().month(.wide))). "
                 + "Every total and record is recalculated without it. The workout stays in Apple Health.")
        }
    }

    /// A mis-recorded run — a forgotten stop, a drive home still counting —
    /// used to be permanent, and it distorts every total, chart and record it
    /// touches. Long press rather than swipe: the log is a hand-built scroll
    /// view, not a `List`, and a hand-rolled swipe would fight the scroll.
    @ViewBuilder
    private func deleteAction(_ run: Run) -> some View {
        if run.isImported {
            // Currimus is only reading this one; it belongs to whoever wrote it.
            Text("Recorded by \(run.name). Delete it in Apple Health.")
        } else {
            Button(role: .destructive) { pendingDelete = run } label: {
                Label("Delete run", systemImage: "trash")
            }
        }
    }

    private func monthLabel(_ group: (month: Date, runs: [Run])) -> String {
        let name = group.month.formatted(.dateTime.month(.wide))
        let km = group.runs.reduce(0) { $0 + $1.distanceKm }
        return "\(name) · \(Format.km(km, decimals: 1)) km"
    }
}

struct LogRow: View {
    var run: Run
    var prTag: String?

    private var isFast: Bool { !run.isTrail && run.paceSecPerKm < 310 }

    var body: some View {
        HStack(spacing: 14) {
            Text(run.date.formatted(.dateTime.weekday(.abbreviated)).uppercased()
                 + "\n" + run.date.formatted(.dateTime.day(.twoDigits).month(.twoDigits)))
                .font(.sg(12)).foregroundStyle(Theme.muted).lineSpacing(3)
                .frame(width: 56, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("\(Format.km(run.distanceKm)) km").font(.stat(18))
                    if run.isTrail { TrailTag() }
                }
                detail
            }
            Spacer()
            Text(Format.pace(run.paceSecPerKm))
                .font(.stat(18))
                .foregroundStyle(isFast || prTag != nil ? Theme.signal : Theme.ink)
        }
        .frame(minHeight: 60)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Theme.hairline.frame(height: 1) }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var detail: some View {
        if run.isImported {
            // Another app recorded it: name the source instead of claiming
            // zone data Currimus never captured.
            Text("\(run.name) · \(Format.clock(run.duration))")
                .font(.stat(13, weight: .regular)).foregroundStyle(Theme.bright)
        } else if run.isTrail {
            Text("Trail · \(Format.clock(run.duration)) · +\(Int(run.climbMeters ?? 0)) m")
                .font(.stat(13, weight: .regular)).foregroundStyle(Theme.bright)
        } else if let prTag, prTag != "Longest" {
            (Text("\(Format.clock(run.duration)) · ") + Text(prTag).foregroundStyle(Theme.signal).fontWeight(.semibold))
                .font(.stat(13, weight: .regular)).foregroundStyle(Theme.bright)
        } else {
            Text("\(run.classification.label) · \(Format.clock(run.duration)) · Z\(run.dominantZone)")
                .font(.stat(13, weight: .regular)).foregroundStyle(Theme.bright)
        }
    }
}

struct TrailTag: View {
    var body: some View {
        Text("TRAIL")
            .font(.sg(10, weight: .bold)).kerning(1)
            .foregroundStyle(Theme.signal)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.signal.opacity(0.4), lineWidth: 1))
    }
}
