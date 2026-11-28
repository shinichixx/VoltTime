import SwiftUI

// Dark, like the Tesla app (and the old Home Assistant Tesla dashboard).
enum Theme {
    static let rouge = Color(red: 0.93, green: 0.27, blue: 0.27)
    static let blue = Color(red: 0.243, green: 0.416, blue: 0.882)
    static let orange = Color(red: 1.0, green: 0.62, blue: 0.04)
    static let purple = Color(red: 0.243, green: 0.416, blue: 0.882)
    static let green = Color(red: 0.247, green: 0.725, blue: 0.314)
    static let background = Color(red: 22 / 255, green: 23 / 255, blue: 24 / 255)
    static let field = Color(white: 0.20)
    static let card = Color(white: 0.145)
}

/// Coloured capsule badge.
struct Badge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.app(size: 10.5, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

extension Double {
    /// "73" for whole numbers, "0.4981" otherwise.
    var plain: String {
        if self == rounded() && abs(self) < 1e9 { return String(Int(self)) }
        var s = String(format: "%.4f", self)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}

func parseNumber(_ s: String) -> Double? {
    Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
}
