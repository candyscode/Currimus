import SwiftUI

/// The promise, before any data exists.
///
/// It is also the only screen a fresh install has, so it has to carry the one
/// thing the user can actually do here. Recording happens on the watch — but
/// the race, the heart-rate zones and the pacer defaults are the iPhone's, and
/// they are worth setting *before* the first run rather than after it.
struct FirstLaunchView: View {
    @EnvironmentObject private var store: RunStore
    @Environment(\.pushRoute) private var push
    @State private var healthAsk: HealthAsk = .idle

    /// The Health import is the one action here that can visibly fail — the
    /// prompt can be declined, and there may simply be nothing to import.
    /// Health never reveals which, so the wording covers both.
    private enum HealthAsk { case idle, working, foundNothing }

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
                VStack(alignment: .leading, spacing: 13) {
                    promise("No ads. No account. No feed.")
                    promise("No tracking, no data sales, no spam.")
                    promise("The numbers that matter, nothing else.")
                    promise("Built by runners, for runners.")
                }
                .padding(.top, 32)

                Spacer()

                VStack(spacing: 14) {
                    // The primary action names something this screen can
                    // actually do. It used to read "Start on your Apple Watch"
                    // — an instruction dressed as a button, on a screen with
                    // no way through to Settings at all.
                    Button { push(.settings) } label: {
                        Text("Set up race, zones and pacer")
                            .font(.sg(17, weight: .bold)).foregroundStyle(Theme.bg)
                            .frame(maxWidth: .infinity, minHeight: 58)
                            .background(Theme.signal, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    // Asked here rather than at launch: someone who has been
                    // running for years already has a log, and this is the
                    // screen with room to say what the permission is for.
                    Button(action: importFromHealth) {
                        Text(healthAsk == .working
                             ? "Reading Apple Health…"
                             : "Already have runs? Bring them in")
                            .font(.sg(15, weight: .semibold)).foregroundStyle(Theme.bright)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Theme.chipFill, in: Capsule())
                            .overlay(Capsule().stroke(Theme.chipStroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(healthAsk == .working)

                    Text(caption)
                        .font(.sg(13)).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center).lineSpacing(2)
                }
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 40)
        }
        .foregroundStyle(Theme.ink)
    }

    private var caption: String {
        healthAsk == .foundNothing
            ? "No running workouts in Apple Health yet — or access was declined. Either way, your first run on the watch starts the log."
            : "Then start your first run on the Apple Watch — the log fills itself."
    }

    /// Raises the Health prompt and pulls in whatever other apps recorded. On
    /// success this screen disappears on its own: the log stops being empty.
    private func importFromHealth() {
        healthAsk = .working
        Task {
            await store.refreshImportedRuns(requestingAccess: true)
            healthAsk = store.allRuns.isEmpty ? .foundNothing : .idle
        }
    }

    private func promise(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("—").foregroundStyle(Theme.signal)
            Text(text).foregroundStyle(Theme.bright)
        }
        .font(.sg(16))
    }
}
