import SwiftUI

/// A small caption pinned to the top-left, on the system clock's baseline —
/// the sanctioned watchOS slot beside the time (the same slot the Workout app
/// uses for its activity glyph). Deterministic across all watch sizes.
struct TopBarCaption: View {
    var text: String
    var color: Color = Theme.bright
    /// Leading trail triangle mark.
    var mark: Bool = false
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 4) {
            if mark {
                TriangleMark()
                    .fill(Theme.signal)
                    .frame(width: size * 0.6, height: size * 0.52)
            }
            Text(text)
                .font(.sg(size, weight: .medium))
                .kerning(size * 0.08)
                .foregroundStyle(color)
        }
        // The system toolbar leads at 16.5 pt (Ultra) but *centers* items
        // narrower than its minimum slot — a wide leading-aligned frame keeps
        // short captions ("RUN") pinned left like long ones. The 3.5 pt nudge
        // then lands every caption on the content column's 20 pt edge.
        .frame(minWidth: 64, alignment: .leading)
        .padding(.leading, 3.5)
    }
}

extension View {
    /// Places a caption beside the system clock (top-left).
    func topBarCaption<Caption: View>(@ViewBuilder _ caption: () -> Caption) -> some View {
        toolbar { ToolbarItem(placement: .topBarLeading) { caption() } }
    }
}
