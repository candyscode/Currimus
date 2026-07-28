import SwiftUI

struct LogView: View {
    @EnvironmentObject private var store: RunStore
    @Environment(\.pushRoute) private var push
    @State private var filter: RunStore.LogFilter = .all
    /// Set by a delete action; the confirmation reads it back. One run or many
    /// — the marking mode deletes in bulk and asks the same question.
    @State private var pendingDelete: PendingDelete?
    /// Which row currently has its delete action swiped open, if any.
    @State private var openRow: UUID?
    /// An imported run whose greyed delete tile was pressed — the alert reads
    /// it back to explain why the delete cannot happen here.
    @State private var notDeletable: Run?
    @State private var isSelecting = DebugFlags.opensLogSelection
    @State private var selection: Set<UUID> = []

    var body: some View {
        // Cached in the store — this used to recompute the fastest 5 K and
        // 10 K window across the whole log on every body pass.
        let holders = store.benchmarkHolders
        let fastestOfMonth = store.fastestPaceOfMonthHolders
        return TabScreen(topInset: 8) { EmptyView() } content: {
            // Deliberately eager. A `LazyVStack` here leaves the swipe tile
            // without a definite height — it lives in a background of the
            // offset row and stretches to whatever the lazy container
            // proposes — and the delete button stops being hittable. The cost
            // of building every row is paid down in what a row costs instead
            // (see `RunStore.logText`), not by making them lazy.
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Runs").font(.sg(38, weight: .semibold)).kerning(-0.8)
                    Spacer()
                    Text(verbatim: "\(Calendar.current.component(.year, from: .now)) · \(Int(store.yearKm)) km")
                        .font(.stat(13, weight: .regular)).foregroundStyle(Theme.muted)
                }
                .padding(.top, 6)

                HStack(spacing: 10) {
                    SegmentChips(options: [(.all, "All"), (.road, "Road"), (.trail, "Trail")],
                                 selection: $filter)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 250, alignment: .leading)
                    Spacer(minLength: 8)
                    selectChip
                }
                .padding(.top, 18)

                if let notice = store.healthNotice { healthNotice(notice) }
                if isSelecting, showsImportedFootnote { importedFootnote }

                ForEach(store.runsByMonth(filter), id: \.month) { group in
                    Text(monthLabel(group).uppercased())
                        .kicker(13, color: Theme.bright, tracking: 0.12)
                        .padding(.top, 26).padding(.bottom, 12)
                        .overlay(alignment: .bottom) { Theme.hairline.frame(height: 1) }
                    ForEach(group.runs) { run in
                        row(run, prTag: holders[run.id],
                            isFastestPaceOfMonth: fastestOfMonth.contains(run.id))
                    }
                }
            }
            // Room for the floating delete bar, so the last run of the log is
            // never parked underneath it.
            .padding(.bottom, isSelecting ? 80 : 0)
        }
        // The bar takes the tab bar's place while marking, the way a selection
        // mode does everywhere else on the phone. "Done" gives it back.
        .toolbar(isSelecting ? .hidden : .visible, for: .tabBar)
        .overlay(alignment: .bottom) { if isSelecting { deleteBar } }
        .animation(.snappy(duration: 0.25), value: isSelecting)
        // A plain system alert. This was an action sheet, which is the other
        // standard answer and read as something the app had drawn itself.
        .alert(
            DeletePrompt.title(pendingDelete?.runs ?? []),
            isPresented: Binding(get: { pendingDelete != nil },
                                 set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { pending in
            Button("Delete", role: .destructive) { confirm(pending) }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { pending in
            Text(DeletePrompt.message(pending.runs))
        }
        .alert("Recorded by \(notDeletable?.name ?? "another app")",
               isPresented: Binding(get: { notDeletable != nil },
                                    set: { if !$0 { notDeletable = nil } }),
               presenting: notDeletable) { _ in
            Button("OK", role: .cancel) { notDeletable = nil }
        } message: { run in
            Text(DeletePrompt.importedExplanation(run))
        }
    }

    // MARK: - Rows

    /// A mis-recorded run — a forgotten stop, a drive home still counting —
    /// used to be permanent, and it distorts every total, chart and record it
    /// touches. Two ways to reach the same delete: a swipe for one run, the
    /// marking mode for many.
    ///
    /// Every row swipes, imported ones included. Theirs reveals a greyed tile
    /// that explains why Currimus cannot carry the delete out — a row that
    /// silently refuses the gesture reads as broken, not as protected. The
    /// long-press menu that was here first is gone with it: a context menu on
    /// the same view fights the drag for the touch, which is what stopped the
    /// swipe from staying open.
    @ViewBuilder
    private func row(_ run: Run, prTag: String?, isFastestPaceOfMonth: Bool) -> some View {
        let content = LogRow(text: store.logText(for: run, prTag: prTag),
                             isFastestPaceOfMonth: isFastestPaceOfMonth)
        if isSelecting {
            selectableRow(run) { content }
        } else {
            SwipeToRevealRow(id: run.id, label: "Delete", systemImage: "trash",
                             isMuted: run.isImported,
                             openRow: $openRow,
                             action: { run.isImported ? explain(run) : ask(for: [run]) },
                             onTap: { push(.runDetail(run)) }) {
                // One element per row: VoiceOver reads a run as a run rather
                // than as five loose labels, and the swipe test has something
                // to take hold of.
                content
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("log-row")
            }
        }
    }

    @ViewBuilder
    private func selectableRow(_ run: Run, @ViewBuilder content: () -> some View) -> some View {
        let selected = selection.contains(run.id)
        Button { toggle(run) } label: {
            HStack(spacing: 14) {
                Image(systemName: mark(for: run, selected: selected))
                    .font(.system(size: 22))
                    .foregroundStyle(markColor(for: run, selected: selected))
                content()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(run.isImported)
        // Dimmed rather than hidden: the log still has to add up to what the
        // month totals say, even while some of it cannot be selected.
        .opacity(run.isImported ? 0.45 : 1)
    }

    private func mark(for run: Run, selected: Bool) -> String {
        if run.isImported { return "circle.slash" }
        return selected ? "checkmark.circle.fill" : "circle"
    }

    private func markColor(for run: Run, selected: Bool) -> Color {
        if run.isImported { return Theme.track }
        return selected ? Theme.signal : Theme.chipStroke
    }

    // MARK: - Marking mode

    private var selectChip: some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) {
                isSelecting.toggle()
                selection = []
                openRow = nil
            }
        } label: {
            Text(isSelecting ? "Done" : "Select")
                .font(.sg(14, weight: .semibold))
                .foregroundStyle(isSelecting ? Theme.bg : Theme.bright)
                .padding(.horizontal, 16)
                .frame(height: 42)
                .background {
                    if isSelecting {
                        Capsule().fill(Theme.ink)
                    } else {
                        Capsule().fill(Theme.chipFill)
                            .overlay(Capsule().stroke(Theme.chipStroke, lineWidth: 1))
                    }
                }
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    private var deleteBar: some View {
        HStack(spacing: 14) {
            Text(selection.isEmpty
                 ? String(localized: "Pick the runs to delete")
                 : String(localized: "\(selection.count) selected"))
                .font(.sg(15)).foregroundStyle(Theme.bright)
            Spacer(minLength: 8)
            Button { ask(for: selectedRuns) } label: {
                // Dimmed-out signal orange over glass reads as a smudge, so
                // the inactive state is a quiet filled capsule instead.
                Text("Delete").font(.sg(16, weight: .bold))
                    .foregroundStyle(selection.isEmpty ? Theme.muted : Theme.bg)
                    .padding(.horizontal, 22).frame(height: 44)
                    .background(selection.isEmpty ? Theme.track : Theme.signal, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(selection.isEmpty)
        }
        .padding(.leading, 22).padding(.trailing, 8).padding(.vertical, 8)
        .glassEffect(.regular, in: Capsule())
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Only shown while marking, and only when there is actually something in
    /// the log the mode cannot touch.
    private var showsImportedFootnote: Bool {
        store.filteredRuns(filter).contains { $0.isImported }
    }

    private var importedFootnote: some View {
        Text("Runs from Apple Health belong to the app that recorded them — delete those there.")
            .font(.sg(13)).foregroundStyle(Theme.muted).lineSpacing(3)
            .padding(.top, 16)
    }

    private func healthNotice(_ text: String) -> some View {
        NoticeCard(systemImage: "heart.slash", text: text) { store.healthNotice = nil }
            .padding(.top, 18)
    }

    // MARK: - Actions

    private var selectedRuns: [Run] {
        store.allRuns.filter { selection.contains($0.id) }
    }

    private func toggle(_ run: Run) {
        guard !run.isImported else { return }
        if selection.contains(run.id) { selection.remove(run.id) } else { selection.insert(run.id) }
    }

    private func explain(_ run: Run) {
        notDeletable = run
    }

    private func ask(for runs: [Run]) {
        guard !runs.isEmpty else { return }
        pendingDelete = PendingDelete(runs: runs)
    }

    private func confirm(_ pending: PendingDelete) {
        store.delete(pending.runs)
        pendingDelete = nil
        withAnimation(.snappy(duration: 0.25)) {
            openRow = nil
            selection = []
            if isSelecting { isSelecting = false }
        }
    }

    private func monthLabel(_ group: (month: Date, runs: [Run])) -> String {
        let name = group.month.formatted(.dateTime.month(.wide))
        let km = group.runs.reduce(0) { $0 + $1.distanceKm }
        return "\(name) · \(Format.km(km, decimals: 1)) km"
    }

    /// A delete the runner has asked for and not yet confirmed.
    private struct PendingDelete: Identifiable {
        var runs: [Run]
        var id: [UUID] { runs.map(\.id) }
    }
}

struct LogRow: View {
    /// The strings, worked out by the store and cached there — this view does
    /// no formatting and no classification of its own.
    var text: LogRowText
    var isFastestPaceOfMonth: Bool

    var body: some View {
        HStack(spacing: 14) {
            Text(text.day)
                .font(.sg(12)).foregroundStyle(Theme.muted).lineSpacing(3)
                .frame(width: 56, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("\(text.distance) km").font(.stat(18))
                    if text.isTrail { TrailTag() }
                }
                detail
            }
            Spacer()
            Text(text.pace)
                .font(.stat(18))
                .foregroundStyle(isFastestPaceOfMonth ? Theme.signal : Theme.ink)
        }
        .frame(minHeight: 60)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Theme.hairline.frame(height: 1) }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var detail: some View {
        if let prTag = text.prTag {
            Text("\(text.detail)\(Text(prTag).foregroundStyle(Theme.signal).fontWeight(.semibold))")
                .font(.stat(13, weight: .regular)).foregroundStyle(Theme.bright)
        } else {
            Text(text.detail)
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
