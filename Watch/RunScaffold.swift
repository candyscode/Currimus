import SwiftUI

/// The one place that fixes where a live run screen's content sits. Run,
/// Pacer and Trail all build on `RunScaffold`, so the hero (time / pace) is at
/// the same height on every screen and moves in parallel from a single knob.
enum RunLayout {
    /// Top inset of the content. Negative pulls the hero up under the caption
    /// (which lives on the clock line), shrinking the gap the design asks for.
    static let topInset: CGFloat = -20
    static let horizontal: CGFloat = 20
    static let bottom: CGFloat = 16
    /// Minimum gap the scaffold keeps between the hero group and the footer;
    /// the rest of the height pools here, giving the footer breathing room.
    static let heroToFooter: CGFloat = 12
}

/// A live run screen: a top-anchored hero group and a bottom-anchored footer
/// (zone bar / pacer gauge) with the free space pooled between them.
struct RunScaffold<Hero: View, Footer: View>: View {
    @ViewBuilder var hero: Hero
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
            Spacer(minLength: RunLayout.heroToFooter)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(EdgeInsets(top: RunLayout.topInset, leading: RunLayout.horizontal,
                            bottom: RunLayout.bottom, trailing: RunLayout.horizontal))
    }
}

/// The five-segment zone bar + ZONE readout — shared by Run and Trail.
struct ZoneFooter: View {
    var zone: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZoneBar(zone: zone)
            HStack {
                Text("ZONE").kicker(8, color: Theme.bright, tracking: 0.1)
                Spacer()
                Text(zone > 0 ? "\(zone)" : "–")
                    .font(.stat(7.5))
                    .foregroundStyle(zone >= 3 ? Theme.signal : Theme.ink)
            }
            .padding(.top, 4.5)
        }
    }
}
