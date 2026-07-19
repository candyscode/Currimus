import SwiftUI

// MARK: - Navigation routes (pushed screens hide the tab bar)

enum Route: Hashable {
    case race
    case raceSetup
    case runDetail(Run)
    case records
    case settings
    case pacerDefaults
    case hrZones
}

enum Tab: Hashable { case home, log, progress }

/// Imperative push for buttons that aren't NavigationLinks (settings, cards).
struct PushRouteKey: EnvironmentKey { static let defaultValue: (Route) -> Void = { _ in } }
extension EnvironmentValues {
    var pushRoute: (Route) -> Void {
        get { self[PushRouteKey.self] }
        set { self[PushRouteKey.self] = newValue }
    }
}

// MARK: - Glass floating tab bar (the Liquid Glass navigation)

struct GlassTabBar: View {
    @Binding var tab: Tab

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 0) {
                item(.home, "Home", HomeGlyph())
                item(.log, "Log", LogGlyph())
                item(.progress, "Progress", ProgressGlyph())
            }
            .padding(6)
        }
        .glassEffect(.regular, in: Capsule())
        .frame(height: 80)
        .padding(.horizontal, 22)
        .shadow(color: .black.opacity(0.55), radius: 22, y: 18)
    }

    @ViewBuilder
    private func item(_ value: Tab, _ label: String, _ glyph: some Shape) -> some View {
        let active = tab == value
        Button {
            withAnimation(.snappy(duration: 0.25)) { tab = value }
        } label: {
            VStack(spacing: 3) {
                glyph.stroke(active ? Theme.signal : Theme.bright,
                             style: .init(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    .frame(width: 24, height: 24)
                Text(label)
                    .font(.sg(11, weight: .semibold))
                    .foregroundStyle(active ? Theme.signal : Theme.bright)
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
            .background {
                if active {
                    Capsule().fill(Color.white.opacity(0.08))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tab-bar glyphs (stroked, matching the design SVGs)

struct HomeGlyph: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: .init(x: w * 0.15, y: h * 0.44)); p.addLine(to: .init(x: w * 0.5, y: h * 0.15))
        p.addLine(to: .init(x: w * 0.85, y: h * 0.44))
        p.move(to: .init(x: w * 0.23, y: h * 0.40)); p.addLine(to: .init(x: w * 0.23, y: h * 0.85))
        p.addLine(to: .init(x: w * 0.77, y: h * 0.85)); p.addLine(to: .init(x: w * 0.77, y: h * 0.40))
        return p
    }
}

struct LogGlyph: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        for (i, y) in [0.27, 0.5, 0.73].enumerated() {
            p.move(to: .init(x: w * 0.17, y: h * y))
            p.addLine(to: .init(x: w * (i == 2 ? 0.55 : 0.83), y: h * y))
        }
        return p
    }
}

struct ProgressGlyph: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: .init(x: w * 0.15, y: h * 0.73)); p.addLine(to: .init(x: w * 0.38, y: h * 0.48))
        p.addLine(to: .init(x: w * 0.54, y: h * 0.64)); p.addLine(to: .init(x: w * 0.85, y: h * 0.31))
        p.move(to: .init(x: w * 0.65, y: h * 0.31)); p.addLine(to: .init(x: w * 0.85, y: h * 0.31))
        p.addLine(to: .init(x: w * 0.85, y: h * 0.52))
        return p
    }
}

// MARK: - Screen scaffolds

/// A root tab screen: content scrolls under a glass status scrim; the tab bar
/// floats on top (added by RootView). Home passes a brand header.
struct TabScreen<Content: View, Header: View>: View {
    var topInset: CGFloat
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .top) {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                content
                    .padding(.horizontal, 26)
                    .padding(.top, topInset)
                    .padding(.bottom, 118)   // clear the floating tab bar
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            TopScrim { header }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// A pushed screen: glass back button + title, content scrolls under.
struct PushedScreen<Content: View>: View {
    var title: String
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .top) {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                content
                    .padding(.horizontal, 26)
                    .padding(.top, 64)
                    .padding(.bottom, 44)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            TopScrim {
                HStack(spacing: 14) {
                    GlassIconButton(systemImagePath: .back) { dismiss() }
                    Text(title).font(.sg(17, weight: .semibold))
                    Spacer()
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// The blur scrim behind the status bar / header, matching the design gradient.
struct TopScrim<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 6)
            .padding(.bottom, 12)
            .background(alignment: .top) {
                LinearGradient(colors: [Theme.bg.opacity(0.92), Theme.bg.opacity(0.5)],
                               startPoint: .top, endPoint: .bottom)
                    .background(.ultraThinMaterial)
                    .mask(LinearGradient(colors: [.black, .black, .clear],
                                         startPoint: .top, endPoint: .bottom))
                    .ignoresSafeArea(edges: .top)
            }
    }
}
