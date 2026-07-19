import SwiftUI

/// The promise, before any data exists.
struct FirstLaunchView: View {
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

                (Text("Simple.\nBeautiful.\n") + Text("Yours.").foregroundStyle(Theme.signal))
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
                    Text("Start on your Apple Watch")
                        .font(.sg(17, weight: .bold)).foregroundStyle(Theme.bg)
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(Theme.signal, in: Capsule())
                    Text("Race, zones and pacer defaults live in Settings.")
                        .font(.sg(13)).foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 40)
        }
        .foregroundStyle(Theme.ink)
    }

    private func promise(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("—").foregroundStyle(Theme.signal)
            Text(text).foregroundStyle(Theme.bright)
        }
        .font(.sg(16))
    }
}
