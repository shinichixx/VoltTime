import SwiftUI

// Tesla-app style building blocks: pure black page, small captions, rows with a thin icon column,
// slim grey segmented switches, big light numbers. Used by Settings, Charge details and Simulation.

enum TSurface {
    static let page = Color.black
    static let field = Color(white: 0.10)      // #1a1a1c
    static let selected = Color(white: 0.23)   // #3a3a3c
    static let line = Color(white: 0.17)       // #2c2c2e
    static let icon = Color(white: 0.78)       // #c7c7cc
    static let green = Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255)  // #30d158
}

/// Small grey caption above a group of rows.
struct TCaption: View {
    let text: String
    var trailing: String = ""

    var body: some View {
        HStack {
            Text(text.uppercased()).kerning(0.8)
            Spacer()
            if !trailing.isEmpty { Text(trailing) }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(TeslaDark.rowLabel)
        .padding(.horizontal, 20)
        .padding(.top, 26)
        .padding(.bottom, 6)
    }
}

/// One list row: fixed icon column, title (+ subtitle), trailing view, optional content underneath.
/// Thin line above the text (starts at the text, not under the icon); `last` adds the closing line.
struct TRow<Trailing: View, Below: View>: View {
    let title: String
    let icon: String?
    let subtitle: String?
    let dot: Color?
    let badge: AnyView?
    let last: Bool
    let trailing: Trailing
    let below: Below

    init(_ title: String, icon: String? = nil, subtitle: String? = nil, dot: Color? = nil, badge: AnyView? = nil,
         last: Bool = false, @ViewBuilder trailing: () -> Trailing, @ViewBuilder below: () -> Below) {
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
        self.dot = dot
        self.badge = badge
        self.last = last
        self.trailing = trailing()
        self.below = below()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(TSurface.icon)
                }
            }
            .frame(width: 24)

            VStack(spacing: 0) {
                Rectangle().fill(TSurface.line).frame(height: 0.5)
                VStack(alignment: .leading, spacing: 11) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 7) {
                                Text(title).font(.system(size: 15)).foregroundStyle(.white).lineLimit(1)
                                if let badge { badge }
                            }
                            if let subtitle {
                                HStack(spacing: 5) {
                                    if let dot { Circle().fill(dot).frame(width: 6, height: 6) }
                                    Text(subtitle).font(.system(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        trailing.fixedSize()
                    }
                    below
                }
                .padding(.vertical, 12)
                if last { Rectangle().fill(TSurface.line).frame(height: 0.5) }
            }
        }
        .padding(.horizontal, 20)
        .contentShape(Rectangle())
    }
}

extension TRow where Below == EmptyView {
    init(_ title: String, icon: String? = nil, subtitle: String? = nil, dot: Color? = nil, badge: AnyView? = nil,
         last: Bool = false, @ViewBuilder trailing: () -> Trailing) {
        self.init(title, icon: icon, subtitle: subtitle, dot: dot, badge: badge, last: last, trailing: trailing, below: { EmptyView() })
    }
}

/// Row that opens another page.
struct TNavRow: View {
    let title: String
    let icon: String
    var subtitle: String? = nil
    var dot: Color? = nil
    var last = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TRow(title, icon: icon, subtitle: subtitle, dot: dot, last: last) {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(TeslaDark.dim)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Three big light numbers side by side, separated by hairlines.
struct TStat {
    let value: String
    var unit: String = ""
    let caption: String
    var color: Color = .white
}

struct TStats: View {
    let items: [TStat]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                if i > 0 { Rectangle().fill(TSurface.line).frame(width: 0.5, height: 36) }
                VStack(spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(items[i].value).font(.system(size: 25, weight: .light)).foregroundStyle(items[i].color)
                        if !items[i].unit.isEmpty {
                            Text(items[i].unit).font(.system(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    Text(items[i].caption).font(.system(size: 12)).foregroundStyle(TeslaDark.rowLabel).lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20)
    }
}

/// Slim grey segmented switch, selected segment lighter.
struct TSegment: View {
    let items: [String]
    var subs: [String]? = nil
    let selected: Int?
    var disabled = false
    let pick: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                let on = i == selected
                Button { pick(i) } label: {
                    VStack(spacing: 1) {
                        Text(items[i]).font(.system(size: 13, weight: .medium))
                        if let subs, subs.indices.contains(i) {
                            Text(subs[i]).font(.system(size: 10.5))
                                .foregroundStyle(on ? TeslaDark.labelGrey : TeslaDark.dim)
                        }
                    }
                    .foregroundStyle(on ? Color.white : TeslaDark.rowLabel)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, subs == nil ? 6 : 7)
                    .background(RoundedRectangle(cornerRadius: 7).fill(on ? TSurface.selected : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9).fill(TSurface.field))
        .disabled(disabled)
        .opacity(disabled ? 0.6 : 1)
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}

/// Compact − / + pill.
struct TStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        HStack(spacing: 0) {
            button("minus", -step).disabled(value <= range.lowerBound)
            Rectangle().fill(TSurface.selected).frame(width: 0.5, height: 18)
            button("plus", step).disabled(value >= range.upperBound)
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(TSurface.field))
    }

    private func button(_ symbol: String, _ d: Int) -> some View {
        Button { value = min(max(value + d, range.lowerBound), range.upperBound) } label: {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 38, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Number field in a grey pill, unit after it.
struct TNumberField: View {
    @Binding var text: String
    let unit: String
    var focus: FocusState<String?>.Binding
    let key: String

    var body: some View {
        HStack(spacing: 5) {
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .frame(width: 58)
                .focused(focus, equals: key)
            Text(unit).font(.system(size: 12)).foregroundStyle(TeslaDark.rowLabel)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(TSurface.field))
    }
}

struct TValueField: View {
    @Binding var value: Double
    let unit: String
    var focus: FocusState<String?>.Binding
    let key: String

    var body: some View {
        HStack(spacing: 5) {
            TextField("0", value: $value, format: .number.grouping(.never).precision(.fractionLength(0...4)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .frame(width: 64)
                .focused(focus, equals: key)
            Text(unit).font(.system(size: 12)).foregroundStyle(TeslaDark.rowLabel)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(TSurface.field))
    }
}

/// Value with a small grey unit, for trailing positions.
struct TValue: View {
    let value: String
    var unit: String = ""
    var color: Color = .white
    var size: CGFloat = 15

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value).font(.system(size: size, weight: size > 17 ? .light : .regular)).foregroundStyle(color)
            if !unit.isEmpty { Text(unit).font(.system(size: 12)).foregroundStyle(TeslaDark.rowLabel) }
        }
        .lineLimit(1)
    }
}

/// Grey footnote under a group, aligned with the row text.
struct TFootnote: View {
    let text: String
    var color: Color = TeslaDark.dim

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 58)
            .padding(.trailing, 20)
            .padding(.top, 8)
    }
}

/// Tesla-style battery: green = now, stripes = what this charge adds, white marker = limit.
struct TBatteryBar: View {
    let now: Double
    let limit: Double
    /// When set, dragging along the bar sets the limit (like Tesla's charge-limit slider).
    var range: ClosedRange<Double> = 1...100
    var onDrag: ((Double) -> Void)? = nil

    private struct Stripes: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            var x = -r.height
            while x < r.width {
                p.move(to: CGPoint(x: x, y: r.height))
                p.addLine(to: CGPoint(x: x + r.height, y: 0))
                x += 6
            }
            return p
        }
    }

    var body: some View {
        GeometryReader { g in
            let inner = max(1, g.size.width - 6)
            let n = min(1, max(0, now / 100))
            let l = min(1, max(0, limit / 100))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7).strokeBorder(Color(white: 0.30), lineWidth: 1.5)
                HStack(spacing: 0) {
                    Rectangle().fill(TSurface.green).frame(width: inner * n)
                    ZStack {
                        TSurface.green.opacity(0.12)
                        Stripes().stroke(TSurface.green.opacity(0.5), lineWidth: 1.6)
                    }
                    .frame(width: inner * max(0, l - n))
                    .clipped()
                    Spacer(minLength: 0)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(3)
                Capsule().fill(.white)
                    .frame(width: 2.5, height: g.size.height + 8)
                    .offset(x: 3 + inner * l - 1.25)
            }
            .overlay(alignment: .trailing) {
                RoundedRectangle(cornerRadius: 1.5).fill(Color(white: 0.30))
                    .frame(width: 3.5, height: 11)
                    .offset(x: 5)
            }
            .contentShape(Rectangle().inset(by: -10))
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { v in
                    guard let onDrag else { return }
                    let pct = ((v.location.x - 3) / inner * 100).rounded()
                    onDrag(min(max(pct, range.lowerBound), range.upperBound))
                },
                including: onDrag == nil ? .none : .all
            )
        }
        .frame(height: 30)
        .padding(.trailing, 6)
        .animation(onDrag == nil ? .easeOut(duration: 0.3) : nil, value: limit)
    }
}

/// Swipe a row left to show a red Delete button (works inside a ScrollView).
struct SwipeToDelete: ViewModifier {
    let enabled: Bool
    let onDelete: () -> Void
    @State private var x: CGFloat = 0
    @State private var open = false
    private let width: CGFloat = 86

    func body(content: Content) -> some View {
        ZStack(alignment: .trailing) {
            if x < 0 {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { x = 0; open = false }
                    onDelete()
                } label: {
                    Text("Delete").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: max(width, -x))
                        .frame(maxHeight: .infinity)
                        .background(Theme.rouge)
                }
                .buttonStyle(.plain)
            }
            content
                .background(TSurface.page)
                .offset(x: x)
        }
        .clipped()
        .simultaneousGesture(
            DragGesture(minimumDistance: 18)
                .onChanged { g in
                    guard enabled, abs(g.translation.width) > abs(g.translation.height) * 1.5 else { return }
                    x = min(0, max(-width * 1.4, g.translation.width + (open ? -width : 0)))
                }
                .onEnded { g in
                    guard enabled else { return }
                    let target = g.translation.width + (open ? -width : 0)
                    withAnimation(.spring(duration: 0.25)) {
                        open = target < -width / 2
                        x = open ? -width : 0
                    }
                }
        )
    }
}

/// "1:13 PM" → ("1:13", "PM"); 24-hour clocks give no suffix.
func splitClock(_ s: String) -> (time: String, suffix: String) {
    let parts = s.split(whereSeparator: { $0.isWhitespace })
    if parts.count >= 2, let last = parts.last, last.allSatisfy({ $0.isLetter || $0 == "." }) {
        return (parts.dropLast().joined(separator: " "), String(last))
    }
    return (s, "")
}
