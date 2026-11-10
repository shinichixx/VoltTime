import SwiftUI

// Same palette and building blocks as Fleetly.
enum Theme {
    static let teal = Color(red: 0.0, green: 0.588, blue: 0.655)
    static let rouge = Color(red: 0.80, green: 0.09, blue: 0.15)
    static let blue = Color(red: 0.13, green: 0.40, blue: 0.80)
    static let orange = Color(red: 1.0, green: 0.596, blue: 0.0)
    static let purple = Color(red: 0.404, green: 0.227, blue: 0.718)
    static let green = Color(red: 0.180, green: 0.490, blue: 0.196)
    static let background = Color(red: 0.945, green: 0.953, blue: 0.961)
    static let tabInactive = Color(white: 0.45)
    static let field = Color(red: 0.965, green: 0.969, blue: 0.976)
}

struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
    }
}

/// Coloured top bar with a white chip on the left (Fleetly's header).
struct AppHeader<Trailing: View>: View {
    let color: Color
    let icon: String
    let title: String
    let subtitle: String
    let trailing: Trailing

    init(color: Color = Theme.teal, icon: String, title: String, subtitle: String, @ViewBuilder trailing: () -> Trailing) {
        self.color = color
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(Color.white).frame(width: 30, height: 30)
                    .overlay(Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(color))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white)
                    Text(subtitle).font(.system(size: 10.5)).foregroundStyle(Color.white.opacity(0.85))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .padding(.trailing, 4)
            .background(Color.white.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            Spacer()
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(color.ignoresSafeArea(edges: .top))
    }
}

struct HeaderButton: View {
    let systemName: String
    var spinning = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Circle().fill(Color.white.opacity(0.22)).frame(width: 36, height: 36)
                .overlay {
                    if spinning {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: systemName).foregroundStyle(.white).font(.system(size: 15, weight: .semibold))
                    }
                }
        }
    }
}

/// Coloured icon tile + title, used at the top of cards.
struct CardTitle: View {
    let icon: String
    let title: String
    let color: Color
    var trailing: String = ""
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 9).fill(color).frame(width: 30, height: 30)
                .overlay(Image(systemName: icon).foregroundStyle(.white).font(.system(size: 14, weight: .semibold)))
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(color)
            Spacer()
            if !trailing.isEmpty {
                Text(trailing).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}

/// Small figure with a caption, three of these sit side by side.
struct Figure: View {
    let label: String
    let value: String
    var color: Color = .primary
    var body: some View {
        VStack(spacing: 3) {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 15, weight: .bold)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(Theme.field)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Label on the left, numeric text field with unit on the right.
struct NumberRow: View {
    let label: String
    @Binding var text: String
    let unit: String
    var focus: FocusState<String?>.Binding
    let key: String

    var body: some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 90)
                .focused(focus, equals: key)
            Text(unit).font(.system(size: 12)).foregroundStyle(Theme.teal).frame(width: 52, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

/// Label on the left, numeric field bound to a Double (commits when editing ends).
struct ValueRow: View {
    let label: String
    @Binding var value: Double
    let unit: String
    var focus: FocusState<String?>.Binding
    let key: String

    var body: some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            TextField("0", value: $value, format: .number.grouping(.never).precision(.fractionLength(0...4)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 90)
                .focused(focus, equals: key)
            Text(unit).font(.system(size: 12)).foregroundStyle(Theme.teal).frame(width: 52, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

/// Coloured capsule badge.
struct Badge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
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
