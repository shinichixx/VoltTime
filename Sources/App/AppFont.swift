import SwiftUI

/// The app's typeface: Albert Sans (SIL Open Font License, bundled in Sources/Fonts),
/// the closest free match to the Tesla app's Universal Sans. SF Symbols keep the system font.
extension Font {
    static func app(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(AppFont.name(weight), fixedSize: size)
    }
}

enum AppFont {
    static func name(_ w: Font.Weight) -> String {
        switch w {
        case .ultraLight, .thin, .light: return "AlbertSansRoman-Light"
        case .medium: return "AlbertSansRoman-Medium"
        case .semibold: return "AlbertSansRoman-SemiBold"
        case .bold, .heavy, .black: return "AlbertSansRoman-Bold"
        default: return "AlbertSansRoman-Regular"
        }
    }
}
