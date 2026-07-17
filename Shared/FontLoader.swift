import CoreText
import Foundation

/// Registers the bundled Space Grotesk faces for this process. Call once at
/// startup (app and widget extension each run in their own process).
enum FontLoader {
    static let faces = [
        "SpaceGrotesk-Regular", "SpaceGrotesk-Medium",
        "SpaceGrotesk-SemiBold", "SpaceGrotesk-Bold", "SpaceGrotesk-Light",
    ]

    static func registerAll() {
        for face in faces {
            guard let url = Bundle.main.url(forResource: face, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
