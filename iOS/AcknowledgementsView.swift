import SwiftUI

/// Attribution for the one thing in this app that somebody else made.
///
/// Space Grotesk is the whole typographic identity — every number on both
/// screens is set in it — and it ships under the SIL Open Font License, which
/// requires the copyright notice and the licence to travel with the software.
/// The licence file was already in the bundle; nothing surfaced it, so in
/// practice the condition was not being met.
struct AcknowledgementsView: View {
    /// The bundled OFL text, shown verbatim rather than summarised — a licence
    /// paraphrased is not the licence.
    private var licenseText: String? {
        guard let url = Bundle.main.url(forResource: "OFL", withExtension: "txt") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    var body: some View {
        PushedScreen(title: "Acknowledgements") {
            VStack(alignment: .leading, spacing: 0) {
                Text("SPACE GROTESK").kicker(13, color: Theme.bright, tracking: 0.12)
                Text("Every number in Currimus is set in Space Grotesk, by Florian Karsten.")
                    .font(.sg(16)).lineSpacing(3).padding(.top, 10)
                Text("Licensed under the SIL Open Font License 1.1.")
                    .font(.sg(13)).foregroundStyle(Theme.muted).padding(.top, 8)

                if let licenseText {
                    Text(licenseText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .padding(EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18)
                            .stroke(Theme.cardBorder, lineWidth: 1))
                        .padding(.top, 22)
                }

                Text("Nothing else. Currimus has no third-party code in it — no analytics, no networking, no SDKs.")
                    .font(.sg(13)).foregroundStyle(Theme.muted).lineSpacing(3).padding(.top, 24)
            }
        }
    }
}
