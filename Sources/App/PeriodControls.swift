import SwiftUI

/// Start / end / label of the period being shown (Impact and Energy pages).
struct PeriodRange: Equatable {
    let start: Date
    let end: Date
    let label: String

    static func make(_ period: ImpactPeriod, offset: Int, firstDay: Date?) -> PeriodRange {
        let cal = Calendar.current
        let now = Date()
        guard let comp = period.component else {
            let start = firstDay ?? cal.startOfDay(for: now)
            return PeriodRange(start: start,
                               end: cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now,
                               label: "Since " + start.formatted(.dateTime.month(.abbreviated).year()))
        }
        let shifted = cal.date(byAdding: comp, value: offset, to: now) ?? now
        let interval = cal.dateInterval(of: comp, for: shifted) ?? DateInterval(start: cal.startOfDay(for: now), duration: 86400)
        let label: String
        switch period {
        case .day:
            if offset == 0 { label = "Today" }
            else if offset == -1 { label = "Yesterday" }
            else { label = interval.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) }
        case .week:
            let last = interval.end.addingTimeInterval(-1)
            label = offset == 0 ? "This week"
                : "\(interval.start.formatted(.dateTime.day().month(.abbreviated))) – \(last.formatted(.dateTime.day().month(.abbreviated)))"
        case .month: label = interval.start.formatted(.dateTime.month(.wide).year())
        case .year: label = interval.start.formatted(.dateTime.year())
        case .lifetime: label = ""
        }
        return PeriodRange(start: interval.start, end: interval.end, label: label)
    }
}

/// ‹ label › row under the navigation bar.
struct PeriodBar: View {
    let range: PeriodRange
    let period: ImpactPeriod
    let firstDay: Date?
    @Binding var offset: Int

    var body: some View {
        let canBack = period != .lifetime && (firstDay.map { range.start > $0 } ?? false)
        let canForward = period != .lifetime && offset < 0
        HStack {
            Button { offset -= 1 } label: { Image(systemName: "chevron.left").padding(10) }
                .disabled(!canBack)
                .foregroundStyle(canBack ? TeslaDark.rowLabel : Color(white: 0.23))
                .opacity(period == .lifetime ? 0 : 1)
            Spacer()
            Text(range.label).font(.app(size: 15, weight: .medium))
            Spacer()
            Button { offset += 1 } label: { Image(systemName: "chevron.right").padding(10) }
                .disabled(!canForward)
                .foregroundStyle(canForward ? TeslaDark.rowLabel : Color(white: 0.23))
                .opacity(period == .lifetime ? 0 : 1)
        }
        .font(.system(size: 15, weight: .semibold))
        .buttonStyle(.plain)
    }
}

/// "Month ⌄" timescale menu for the top-right of the navigation bar (Tesla app style).
struct PeriodMenu: View {
    @Binding var periodRaw: String
    @Binding var offset: Int
    /// Energy page (Tesla app): a small rounded box with a grey border, not a capsule in the top bar.
    var boxed = false

    var body: some View {
        let period = ImpactPeriod(rawValue: periodRaw) ?? .month
        Menu {
            Picker("Period", selection: Binding(get: { period }, set: { periodRaw = $0.rawValue; offset = 0 })) {
                ForEach(ImpactPeriod.allCases) { Text($0.rawValue).tag($0) }
            }
        } label: {
            HStack(spacing: 5) {
                Text(period.rawValue).font(.app(size: boxed ? 13.5 : 15, weight: boxed ? .medium : .regular))
                Image(systemName: "chevron.down").font(.system(size: boxed ? 10 : 11, weight: .semibold)).foregroundStyle(TeslaDark.rowLabel)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, boxed ? 10 : 0)
            .padding(.vertical, boxed ? 6 : 0)
            .background {
                if boxed {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color(white: 0.11))
                    RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color(white: 0.3), lineWidth: 1)
                }
            }
        }
    }
}


/// Numbers in the app: thousands always with a comma ("1,065"), one decimal under 100 ("13.7").
enum Num {
    static let en = Locale(identifier: "en_US")
    static func whole(_ v: Double) -> String { Int(v.rounded()).formatted(.number.locale(en)) }
    static func kwh(_ v: Double) -> String { v >= 100 ? whole(v) : String(format: "%.1f", v) }
}


/// Where My Car and My Home are mid-swipe, and how far each is scrolled. The two photos are drawn
/// behind the pager (so a page edge never cuts them) and fade by these numbers.
@MainActor
final class PagerFX: ObservableObject {
    @Published var carX: CGFloat = 0
    @Published var carScroll: CGFloat = 0
    @Published var homeX: CGFloat? = nil
    @Published var homeScroll: CGFloat = 0

    /// 1 while the page is in place, 0 once it's half way off.
    static func swipe(_ x: CGFloat?, _ w: CGFloat) -> Double {
        guard let x else { return 0 }
        return max(0, 1 - 2 * min(1, abs(x) / max(w, 1)))
    }
    static func scrolled(_ y: CGFloat) -> Double { max(0.08, 1 - Double(max(y, 0)) / 150) }
}
