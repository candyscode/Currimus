import SwiftUI

/// The promise, before any data exists.
///
/// One thing to do, because on a fresh install there is only one thing worth
/// doing: bring the runs that already exist in Apple Health into Currimus.
/// Setting up race, zones and pacer used to compete for the same screen; it is
/// reachable from Settings the moment the log has anything in it, and asking a
/// runner to configure an empty app was the wrong first minute.
struct FirstLaunchView: View {
    @EnvironmentObject private var store: RunStore
    @Environment(\.pushRoute) private var push
    /// Set when the import came back with nothing. Health never says whether
    /// that is a refusal or an empty log, so the screen has to cover both — and
    /// it has to keep saying it after the sheet is gone.
    @State private var foundNothing = DebugFlags.showsEmptyImportNotice

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Theme.bg.ignoresSafeArea()
            RadialGradient(colors: [Theme.signal.opacity(0.14), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 280)
                .frame(width: 320, height: 320)
                .offset(x: 60, y: -60)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Text("CURRIMUS").font(.sg(16, weight: .bold)).kerning(1.3).padding(.top, 26)

                Spacer()

                Text("Simple.\nBeautiful.\n\(Text("Yours.").foregroundStyle(Theme.signal))")
                    .font(.sg(56, weight: .semibold)).kerning(-1.9).lineSpacing(2)
                // The pitch gives way to the problem. Left in place, it pushed
                // the headline into two truncated lines on a 6.3" screen — and
                // someone reading why their runs are missing is past being
                // sold to.
                if !foundNothing {
                    VStack(alignment: .leading, spacing: 13) {
                        promise("No ads. No account. No feed.")
                        promise("No tracking, no data sales, no spam.")
                        promise("The numbers that matter, nothing else.")
                        promise("Built by runners, for runners.")
                    }
                    .padding(.top, 32)
                }

                Spacer()

                VStack(spacing: 14) {
                    if foundNothing { nothingFoundNotice }

                    Button { store.startFirstImport() } label: {
                        Text(foundNothing ? "Try Apple Health again" : "Let's get started")
                            .font(.sg(17, weight: .bold)).foregroundStyle(Theme.bg)
                            .frame(maxWidth: .infinity, minHeight: 58)
                            .background(Theme.signal, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    // Only offered once the import has failed: with no runs and
                    // no way here, the app would be a dead end for someone who
                    // declined Health and still wants their race set up.
                    if foundNothing {
                        Button { push(.settings) } label: {
                            Text("Set up race, zones and pacer")
                                .font(.sg(14, weight: .semibold)).foregroundStyle(Theme.bright)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(caption)
                            .font(.sg(13)).foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center).lineSpacing(2)
                    }
                }
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 40)
        }
        .foregroundStyle(Theme.ink)
        .sheet(isPresented: Binding(get: { store.firstImport != nil },
                                    set: { if !$0 { finishImport() } })) {
            if let progress = store.firstImport {
                FirstImportSheet(progress: progress,
                                 onStop: { store.stopFirstImport() },
                                 onDone: finishImport)
            }
        }
    }

    /// What the button promises, before it is pressed.
    private var caption: String {
        switch store.watchState {
        case .noWatch:
            return "Currimus reads the runs you already have in Apple Health. Recording happens on the Apple Watch — there is none paired with this iPhone yet."
        case .appMissing:
            return "Currimus reads the runs you already have in Apple Health. To record, install Currimus on your Apple Watch — the Watch app, under Available Apps."
        case .ready, .unknown:
            return "Currimus reads the runs you already have in Apple Health. After that, your Apple Watch keeps the log filling itself."
        }
    }

    /// Said plainly, because the likely cause is a permission the runner can
    /// still change, and the consequence of leaving it is an app that cannot do
    /// its job.
    private var nothingFoundNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.signal)
                Text("No runs came out of Apple Health")
                    .font(.sg(15, weight: .bold)).foregroundStyle(Theme.ink)
            }
            Text("If you have runs on this iPhone, access was most likely declined — Health never says, it simply returns nothing. Without it Currimus has no log, no records and no progress. Allow it under Settings → Privacy & Security → Health → Currimus, then try again.")
                .font(.sg(13)).foregroundStyle(Theme.bright)
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        .background(Theme.glassCardFill, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.glassCardStroke, lineWidth: 1))
        .padding(.bottom, 4)
    }

    /// Closing the sheet is the way into the app: with runs in the log this
    /// screen is replaced by the tabs, and without them it stays and says so.
    private func finishImport() {
        foundNothing = store.allRuns.isEmpty
        store.clearFirstImport()
    }

    private func promise(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("—").foregroundStyle(Theme.signal)
            Text(text).foregroundStyle(Theme.bright)
        }
        .font(.sg(16))
    }
}

/// The first import, while it runs.
///
/// Modal and with a bar, because this is minutes of work on a long log and the
/// alternative — a button that greys out and says nothing — is what this screen
/// replaced. The three steps behind it (permission, workout list, traces) are
/// one thing to the runner, so they are one bar.
struct FirstImportSheet: View {
    var progress: RunStore.FirstImport
    var onStop: () -> Void
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    /// Drives the indeterminate sweep while Health is being asked — there is no
    /// count to show until the workout list comes back.
    @State private var sweeping = false

    private var foundNothing: Bool { progress.isFinished && progress.imported == 0 }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.sg(24, weight: .semibold)).kerning(-0.4)

                Text(body_)
                    .font(.sg(14)).foregroundStyle(Theme.bright).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)

                if progress.stage != .reading, progress.total > 0 {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(progress.done)").font(.stat(56)).kerning(-2.2)
                        Text("of \(progress.total)").font(.sg(16)).foregroundStyle(Theme.bright)
                    }
                    .padding(.top, 22)
                } else if progress.isFinished, progress.imported > 0 {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(progress.imported)").font(.stat(56)).kerning(-2.2)
                        Text(progress.imported == 1 ? "run" : "runs")
                            .font(.sg(16)).foregroundStyle(Theme.bright)
                    }
                    .padding(.top, 22)
                }

                // No bar when nothing was found: a full orange line reads as
                // success, which is the opposite of what this state means.
                if !foundNothing { bar.padding(.top, 16) }

                Spacer()

                Button {
                    if progress.isFinished { onDone() } else { onStop() }
                    dismiss()
                } label: {
                    Text(buttonTitle)
                        .font(.sg(17, weight: .bold))
                        .foregroundStyle(progress.isFinished ? Theme.bg : Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(progress.isFinished ? AnyShapeStyle(Theme.signal)
                                                        : AnyShapeStyle(Theme.chipFill),
                                    in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(EdgeInsets(top: 44, leading: 26, bottom: 24, trailing: 26))
        }
        .presentationDetents([.height(420)])
        .interactiveDismissDisabled(!progress.isFinished)
    }

    /// One bar in two modes: a sweep while there is nothing to count, the real
    /// fraction as soon as there is.
    private var bar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.trackIdle)
                if progress.stage == .reading {
                    Capsule().fill(Theme.signal)
                        .frame(width: proxy.size.width * 0.32)
                        .offset(x: sweeping ? proxy.size.width * 0.68 : 0)
                        .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                                   value: sweeping)
                        .onAppear { sweeping = true }
                } else {
                    Capsule().fill(Theme.signal)
                        .frame(width: max(proxy.size.width * progress.fraction,
                                          progress.fraction > 0 ? 4 : 0))
                        .animation(.snappy(duration: 0.3), value: progress.fraction)
                }
            }
        }
        .frame(height: 8)
    }

    private var title: String {
        if foundNothing { return String(localized: "Nothing to bring in") }
        if progress.isFinished { return String(localized: "Your runs are in") }
        return progress.stage == .reading
            ? String(localized: "Reading Apple Health")
            : String(localized: "Bringing your runs in")
    }

    private var body_: String {
        if foundNothing {
            return String(localized: "Apple Health returned no running workouts. Either there are none yet, or access was declined — Health does not say which. Currimus needs that access to be of any use, so it is worth checking.")
        }
        if progress.isFinished {
            return String(localized: "\(Format.plural(progress.imported, "run", "runs")) read out of Apple Health, with their heart-rate traces and GPS tracks.")
        }
        return progress.stage == .reading
            ? String(localized: "Allow access when Health asks, and Currimus reads every running workout on this iPhone. Nothing leaves the device.")
            : String(localized: "Reading the heart-rate trace and GPS track of each run, so zones, records and splits are measured rather than guessed. You can stop — what is done stays done.")
    }

    private var buttonTitle: String {
        if foundNothing { return String(localized: "Continue") }
        return progress.isFinished ? String(localized: "Show me my runs") : String(localized: "Stop")
    }
}
