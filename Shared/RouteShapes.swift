import SwiftUI

/// The route and grid geometry, shared by the iPhone run detail and the Apple
/// TV. It is pure `Shape` math — bounding-box normalisation of a GPS track, a
/// pleasant default loop when there is none, and grid-paper lines — so it lives
/// once here and both platforms draw an identical path. Only what genuinely
/// varies between them (line spacing, stroke width) is a parameter of the
/// wrapping view, not of the geometry.

/// A GPS track normalised into the rect, or a default loop when the run has no
/// usable track. The single source of truth for how a route is drawn anywhere.
struct RouteShape: Shape {
    var route: [Coordinate]?

    func path(in rect: CGRect) -> Path {
        var p = Path()
        if let route, route.count > 2 {
            let lats = route.map(\.lat), lons = route.map(\.lon)
            let minLat = lats.min()!, maxLat = lats.max()!, minLon = lons.min()!, maxLon = lons.max()!
            let spanLat = max(maxLat - minLat, 1e-5), spanLon = max(maxLon - minLon, 1e-5)
            let mapped = route.map { c in
                CGPoint(x: (c.lon - minLon) / spanLon * rect.width,
                        y: (1 - (c.lat - minLat) / spanLat) * rect.height)
            }
            p.move(to: mapped[0]); mapped.dropFirst().forEach { p.addLine(to: $0) }
        } else {
            let w = rect.width, h = rect.height
            p.move(to: .init(x: 0.06 * w, y: 0.78 * h))
            p.addCurve(to: .init(x: 0.30 * w, y: 0.34 * h),
                       control1: .init(x: 0.16 * w, y: 0.62 * h), control2: .init(x: 0.16 * w, y: 0.38 * h))
            p.addCurve(to: .init(x: 0.58 * w, y: 0.56 * h),
                       control1: .init(x: 0.44 * w, y: 0.30 * h), control2: .init(x: 0.46 * w, y: 0.58 * h))
            p.addCurve(to: .init(x: 0.84 * w, y: 0.22 * h),
                       control1: .init(x: 0.70 * w, y: 0.54 * h), control2: .init(x: 0.72 * w, y: 0.24 * h))
            p.addCurve(to: .init(x: 0.95 * w, y: 0.40 * h),
                       control1: .init(x: 0.90 * w, y: 0.21 * h), control2: .init(x: 0.95 * w, y: 0.30 * h))
        }
        return p
    }
}

/// Grid-paper lines at a given spacing — the backdrop the route is drawn over.
/// `step` is the one thing that differs between a phone card and a TV card.
struct GridShape: Shape {
    var step: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x = rect.minX
        while x <= rect.maxX { p.move(to: .init(x: x, y: rect.minY)); p.addLine(to: .init(x: x, y: rect.maxY)); x += step }
        var y = rect.minY
        while y <= rect.maxY { p.move(to: .init(x: rect.minX, y: y)); p.addLine(to: .init(x: rect.maxX, y: y)); y += step }
        return p
    }
}
