import SwiftUI

/// Resolves every colour a run screen needs for the current luminance state.
///
/// The hero keeps full contrast on purpose: the system has already dimmed the
/// whole panel, and dimming the largest number a second time costs the one
/// thing the reduced screen exists for — a readable glance at arm's length in
/// bright sun. Everything around it steps back instead.
struct RunPalette {
    var dimmed: Bool

    /// The one number that must stay readable.
    var hero: Color { Theme.ink }
    /// Supporting metrics — pace, distance, climb.
    var stat: Color { dimmed ? Color(hex: 0x5A5A5A) : Theme.ink }
    /// Kickers and captions.
    var label: Color { dimmed ? Color(hex: 0x454545) : Theme.bright }
    /// The single accent left on a reduced screen.
    var signal: Color { dimmed ? Theme.signal.opacity(0.55) : Theme.signal }
    /// Resting zone segments and gauge tracks.
    var track: Color { dimmed ? Color(hex: 0x1C1C1C) : Theme.track }

    /// Live fill of the active zone segment (design: 0.28 reduced, 0.30 live).
    var activeZoneFill: Double { dimmed ? 0.28 : 0.30 }

    /// The screen only reduces when the wrist is down *and* the setting is on.
    static func resolve(systemDimmed: Bool, enabled: Bool) -> RunPalette {
        RunPalette(dimmed: systemDimmed && enabled)
    }
}

/// Whether the reduced always-on screen is switched on in Settings.
///
/// Switching it off does not restore brightness or refresh rate — watchOS
/// dims the panel and holds 1 Hz either way. It only stops Currimus adding
/// its own reduction on top.
private struct AlwaysOnReducedKey: EnvironmentKey {
    static let defaultValue = true
}

private struct RunPaletteKey: EnvironmentKey {
    static let defaultValue = RunPalette(dimmed: false)
}

extension EnvironmentValues {
    var alwaysOnReduced: Bool {
        get { self[AlwaysOnReducedKey.self] }
        set { self[AlwaysOnReducedKey.self] = newValue }
    }

    /// Colours for the current luminance state, injected once per run screen so
    /// nested components (zone bar, stat rows, gauge) need no flag of their own.
    var runPalette: RunPalette {
        get { self[RunPaletteKey.self] }
        set { self[RunPaletteKey.self] = newValue }
    }
}

