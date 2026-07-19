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

enum AppTab: Hashable { case home, log, progress }

// MARK: - Exact design tab-bar glyphs → template images for the native bar

/// The design's stroked SVG icons (24-unit viewbox), rendered to template
/// images so the native Liquid Glass tab bar tints them per selection state.
@MainActor struct TabIconSet {
    let home: Image
    let log: Image
    let progress: Image

    init() {
        home = Self.render(HomeGlyph())
        log = Self.render(LogGlyph())
        progress = Self.render(ProgressGlyph())
    }

    private static func render(_ shape: some Shape) -> Image {
        let renderer = ImageRenderer(content:
            shape.stroke(Color.black, style: .init(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 27, height: 27)
        )
        renderer.scale = 3
        let ui = renderer.uiImage ?? UIImage()
        return Image(uiImage: ui.withRenderingMode(.alwaysTemplate))
    }
}

private func pt(_ x: Double, _ y: Double, _ r: CGRect) -> CGPoint {
    CGPoint(x: r.minX + x / 24 * r.width, y: r.minY + y / 24 * r.height)
}

struct HomeGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: pt(3.5, 10.5, r)); p.addLine(to: pt(12, 3.5, r)); p.addLine(to: pt(20.5, 10.5, r))
        p.move(to: pt(5.5, 9.5, r)); p.addLine(to: pt(5.5, 20.5, r))
        p.addLine(to: pt(18.5, 20.5, r)); p.addLine(to: pt(18.5, 9.5, r))
        return p
    }
}

struct LogGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: pt(4, 6.5, r)); p.addLine(to: pt(20, 6.5, r))
        p.move(to: pt(4, 12, r)); p.addLine(to: pt(20, 12, r))
        p.move(to: pt(4, 17.5, r)); p.addLine(to: pt(13, 17.5, r))
        return p
    }
}

struct ProgressGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: pt(3.5, 17.5, r)); p.addLine(to: pt(9, 11.5, r))
        p.addLine(to: pt(13, 15.5, r)); p.addLine(to: pt(20.5, 7.5, r))
        p.move(to: pt(15.5, 7.5, r)); p.addLine(to: pt(20.5, 7.5, r)); p.addLine(to: pt(20.5, 12.5, r))
        return p
    }
}

/// Imperative push for buttons that aren't NavigationLinks (settings, cards).
struct PushRouteKey: EnvironmentKey { static let defaultValue: (Route) -> Void = { _ in } }
extension EnvironmentValues {
    var pushRoute: (Route) -> Void {
        get { self[PushRouteKey.self] }
        set { self[PushRouteKey.self] = newValue }
    }
}

// MARK: - Interactive swipe-back

/// Re-enables the edge swipe-to-go-back gesture on pushed screens whose
/// navigation bar is hidden (hiding the bar otherwise disables it).
struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController { Probe(coordinator: context.coordinator) }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var nav: UINavigationController?
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            (nav?.viewControllers.count ?? 0) > 1
        }
    }

    private final class Probe: UIViewController {
        let coordinator: Coordinator
        init(coordinator: Coordinator) { self.coordinator = coordinator; super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { fatalError() }
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            if let nav = navigationController {
                coordinator.nav = nav
                nav.interactivePopGestureRecognizer?.isEnabled = true
                nav.interactivePopGestureRecognizer?.delegate = coordinator
            }
        }
    }
}

extension View {
    func swipeBackEnabled() -> some View {
        background(SwipeBackEnabler().frame(width: 0, height: 0).accessibilityHidden(true))
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
                    .padding(.bottom, 24)   // the system tab bar adds its own inset
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
        .swipeBackEnabled()
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
