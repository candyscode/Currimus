import SwiftUI

/// The one place that fixes where a live run screen's content sits. Run,
/// Pacer and Trail all build on `RunScaffold`, so the hero (time / pace) is at
/// the same height on every screen and moves in parallel from a single knob.
enum RunLayout {
    /// Top inset of the content. Negative pulls the hero up under the caption
    /// (which lives on the clock line), shrinking the gap the design asks for.
    /// One knob for Run, Trail and Pacer — their heroes move in parallel.
    static let topInset: CGFloat = -14
    static let horizontal: CGFloat = 20
    static let bottom: CGFloat = 16
    /// Minimum gap the scaffold keeps between the hero group and the footer;
    /// the rest of the height pools here, giving the footer breathing room.
    static let heroToFooter: CGFloat = 12
}

/// A live run screen: a top-anchored hero group and a bottom-anchored footer
/// (zone bar / pacer gauge) with the free space pooled between them.
struct RunScaffold<Hero: View, Footer: View>: View {
    @Environment(\.recordingIssue) private var issue
    @ViewBuilder var hero: Hero
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
            Spacer(minLength: RunLayout.heroToFooter)
            // Every live screen goes through here, so a degraded recording is
            // visible on Run, Pacer and Trail alike.
            if let issue {
                RecordingIssueNote(issue: issue).padding(.bottom, 5)
            }
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(EdgeInsets(top: RunLayout.topInset, leading: RunLayout.horizontal,
                            bottom: RunLayout.bottom, trailing: RunLayout.horizontal))
    }
}

/// The proportional zone-pointer bar + ZONE readout — shared by Run and Trail.
struct ZoneFooter: View {
    var zone: Int
    /// Where the live HR sits inside the current zone, 0…1.
    var position: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZonePointerBar(zone: zone, position: position)
            HStack {
                Text("ZONE").kicker(8, color: Theme.bright, tracking: 0.1)
                Spacer()
                Text(zone > 0 ? "\(zone)" : "–")
                    .font(.stat(7.5))
                    // Signal is reserved for zone 5 — the number turning red
                    // means max effort, nothing else.
                    .foregroundStyle(zone == 5 ? Theme.signal : Theme.ink)
            }
            .padding(.top, 4.5)   // design 9 px
        }
    }
}

/// Proportional zone bar: the live zone widens to 3.4×, a white pointer marks
/// where the BPM sits inside it — position, not numbers. (Design: "Watch Zone
/// Pointer Exploration"; px values halved to watch points.)
struct ZonePointerBar: View {
    var zone: Int          // 1…5; 0 = no HR yet
    var position: Double   // 0…1 inside the active zone
    var height: CGFloat = 6
    var gap: CGFloat = 3

    private let activeFlex: CGFloat = 3.4
    private let heat: [Double] = [0.25, 0.4, 0.55, 0.75]   // Z1–Z4 when Z5 is live
    private let pointerW: CGFloat = 2
    private let pointerH: CGFloat = 11

    var body: some View {
        GeometryReader { proxy in
            let widths = widths(in: proxy.size.width)
            let activeIdx = max(min(zone - 1, 4), 0)
            let leftEdge = (0..<activeIdx).reduce(CGFloat.zero) { $0 + widths[$1] + gap }
            let clamped = min(max(position, 0.04), 0.96)
            let pointerX = leftEdge + clamped * widths[activeIdx]

            HStack(spacing: gap) {
                ForEach(0..<5, id: \.self) { i in
                    segment(i).frame(width: widths[i], height: height)
                }
            }
            // Overlay, not ZStack: the taller pointer must not stretch the
            // 6 pt track. Centered vertically, it overshoots 2.5 pt each side.
            .overlay(alignment: .leading) {
                if zone > 0 {
                    RoundedRectangle(cornerRadius: pointerW / 2)
                        .fill(Theme.ink)
                        // CSS `0 0 8px` ≈ 2 pt of SwiftUI shadow radius.
                        .shadow(color: zone == 5 ? .black.opacity(0.5) : Theme.ink.opacity(0.45), radius: 2)
                        .frame(width: pointerW, height: pointerH)
                        .offset(x: pointerX - pointerW / 2)
                        .animation(.easeInOut(duration: 1), value: position)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: zone)
        }
        .frame(height: height)
    }

    /// Segment widths: active zone flex 3.4, the rest flex 1 (equal when no
    /// HR). Snapped to the 0.5 pt pixel grid so all four gaps render the same
    /// width; the active segment absorbs the rounding remainder.
    private func widths(in total: CGFloat) -> [CGFloat] {
        let avail = max(total - gap * 4, 0)
        let flexes: [CGFloat] = (1...5).map { $0 == zone ? activeFlex : 1 }
        let sum = flexes.reduce(0, +)
        var snapped = flexes.map { ((avail * $0 / sum) * 2).rounded() / 2 }
        snapped[max(min(zone - 1, 4), 0)] += avail - snapped.reduce(0, +)
        return snapped
    }

    @ViewBuilder
    private func segment(_ i: Int) -> some View {
        let z = i + 1
        let shape = RoundedRectangle(cornerRadius: height / 2)
        if zone == 5 {
            if z == 5 {
                // CSS `0 0 14px` ≈ 3.5 pt — big enough to burn, small enough
                // to keep the gap to zone 4 legible.
                shape.fill(Theme.signal).shadow(color: Theme.signal.opacity(0.5), radius: 3.5)
            } else {
                shape.fill(Theme.signal.opacity(heat[i]))
            }
        } else if z == zone {
            shape.fill(Theme.signal.opacity(0.30))
                // The design's border sits inside the segment (border-box).
                .overlay(shape.strokeBorder(Theme.signal.opacity(0.45), lineWidth: 0.5))
        } else {
            shape.fill(Theme.track)
        }
    }
}
