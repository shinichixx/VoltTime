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
            Text(range.label).font(.system(size: 15, weight: .medium))
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

    var body: some View {
        let period = ImpactPeriod(rawValue: periodRaw) ?? .month
        Menu {
            Picker("Period", selection: Binding(get: { period }, set: { periodRaw = $0.rawValue; offset = 0 })) {
                ForEach(ImpactPeriod.allCases) { Text($0.rawValue).tag($0) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(period.rawValue).font(.system(size: 15))
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(TeslaDark.rowLabel)
            }
            .foregroundStyle(.white)
        }
    }
}
