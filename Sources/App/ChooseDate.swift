import SwiftUI
import UIKit

// "Choose Date" (Tesla app): Day / Month / Year / Custom, a day-month-year wheel and one blue button.
// Dates before the first recorded day and after today are grey and the wheel rolls back off them.

/// A custom range, kept inside the page's saved period text: "Custom|2026-11-01|2026-11-26".
struct CustomSpan: Equatable {
    var start: Date
    var end: Date   // the last day, included

    static let maxDays = 31

    var days: Int {
        let cal = Calendar.current
        return (cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: end)).day ?? 0) + 1
    }

    private static let keys: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// "1 Nov 2026", whatever the phone's region.
    static let shown: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    var stored: String { "Custom|\(Self.keys.string(from: start))|\(Self.keys.string(from: end))" }

    init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    init?(stored: String) {
        let p = stored.split(separator: "|").map(String.init)
        guard p.count == 3, p[0] == "Custom", let s = Self.keys.date(from: p[1]), let e = Self.keys.date(from: p[2]), s <= e else { return nil }
        let last = Calendar.current.date(byAdding: .day, value: Self.maxDays - 1, to: s) ?? e
        self.init(start: s, end: min(e, last))
    }

    var label: String {
        let full = Self.shown.string(from: end)
        let sameYear = Calendar.current.isDate(start, equalTo: end, toGranularity: .year)
        let first = Self.shown.string(from: start)
        return (sameYear ? String(first.dropLast(5)) : first) + " – " + full
    }
}

extension ImpactPeriod {
    /// The period a page has saved.
    init?(stored: String) {
        if stored.hasPrefix("Custom|") {
            guard CustomSpan(stored: stored) != nil else { return nil }
            self = .custom
        } else {
            self.init(rawValue: stored)
        }
    }
}

enum DateTab: String, CaseIterable, Identifiable {
    case day = "Day", month = "Month", year = "Year", custom = "Custom"
    var id: String { rawValue }
    /// Box widths, in proportion (Tesla app).
    var weight: CGFloat {
        switch self {
        case .day: return 78
        case .month: return 104
        case .year: return 89
        case .custom: return 111
        }
    }
}

struct ChooseDateSheet: View {
    @Binding var periodRaw: String
    @Binding var offset: Int
    let firstDay: Date?
    let close: () -> Void

    @State private var tab: DateTab = .day
    @State private var picked = Date()
    @State private var from = Date()
    @State private var to = Date()
    @State private var editingEnd = false
    @State private var ready = false

    private let cal = Calendar.current
    private static let blue = Color(red: 61 / 255, green: 92 / 255, blue: 245 / 255)
    private static let back = Color(red: 27 / 255, green: 27 / 255, blue: 29 / 255)

    private var today: Date { cal.startOfDay(for: Date()) }
    private var lowest: Date {
        min(today, cal.startOfDay(for: firstDay ?? cal.date(byAdding: .year, value: -5, to: today) ?? today))
    }
    private func clamp(_ d: Date, _ lo: Date, _ hi: Date) -> Date { min(max(cal.startOfDay(for: d), lo), hi) }
    /// The last end date a range starting on `from` may have.
    private var lastEnd: Date { min(today, cal.date(byAdding: .day, value: CustomSpan.maxDays - 1, to: from) ?? today) }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabs.padding(.horizontal, 19).padding(.top, 22)
            if tab == .custom {
                HStack(spacing: 12) {
                    dateBox("Start Date", from, on: !editingEnd) { editingEnd = false }
                    dateBox("End Date", to, on: editingEnd) { editingEnd = true }
                }
                .padding(.horizontal, 19)
                .padding(.top, 22)
            }
            Spacer(minLength: 0)
            wheel
            Spacer(minLength: 0)
            if tab == .custom {
                let n = CustomSpan(start: from, end: to).days
                Text("\(n) \(n == 1 ? "day" : "days") selected · Maximum \(CustomSpan.maxDays) days")
                    .font(.app(size: 11.5, weight: .medium)).foregroundStyle(Color(white: 0.6))
                    .frame(height: 16)
            }
            accept.padding(.horizontal, 19).padding(.top, 14)
        }
        .padding(.bottom, 38)
        .frame(height: 562)   // the same height on every tab
        .foregroundStyle(.white)
        .background(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12, style: .continuous).fill(Self.back))
        .contentShape(Rectangle())
        .environment(\.colorScheme, .dark)
        .onAppear(perform: start)
    }

    private func start() {
        guard !ready else { return }
        ready = true
        let period = ImpactPeriod(stored: periodRaw) ?? .day
        let range = PeriodRange.make(period, offset: offset, firstDay: firstDay, stored: periodRaw)
        picked = clamp(range.start, lowest, today)
        switch period {
        case .month: tab = .month
        case .year: tab = .year
        case .custom: tab = .custom
        default: tab = .day
        }
        if let s = CustomSpan(stored: periodRaw) {
            from = clamp(s.start, lowest, today)
            to = clamp(s.end, from, lastEnd)
        } else {
            startRange()
        }
    }

    /// A first suggestion for Custom: the month of the date shown on the other tabs.
    private func startRange() {
        let month = cal.dateInterval(of: .month, for: picked)
        from = clamp(month?.start ?? picked, lowest, today)
        to = clamp(month.map { $0.end.addingTimeInterval(-1) } ?? picked, from, lastEnd)
    }

    private var header: some View {
        ZStack {
            Text("Choose Date").font(.app(size: 14, weight: .semibold))
            HStack {
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(white: 0.73))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.leading, 6)
        }
        .frame(height: 64)
        .overlay(alignment: .bottom) { Rectangle().fill(Color(white: 0.2)).frame(height: 1) }
    }

    private var tabs: some View {
        GeometryReader { g in
            let total = DateTab.allCases.reduce(0) { $0 + $1.weight }
            HStack(spacing: 12) {
                ForEach(DateTab.allCases) { t in
                    let on = t == tab
                    Button {
                        guard t != tab else { return }
                        if t == .custom && CustomSpan(stored: periodRaw) == nil { startRange(); editingEnd = false }
                        tab = t
                    } label: {
                        Text(t.rawValue).font(.app(size: 13, weight: .medium))
                            .foregroundStyle(on ? Color.white : Color(white: 0.6))
                            .frame(width: max(0, (g.size.width - 36) * t.weight / total), height: 50)
                            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(on ? Self.blue : Color(white: 0.23), lineWidth: on ? 1.7 : 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 50)
    }

    private func dateBox(_ title: String, _ date: Date, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.app(size: 10.5)).foregroundStyle(Color(white: 0.6))
                    Text(CustomSpan.shown.string(from: date)).font(.app(size: 13.5, weight: .medium))
                        .foregroundStyle(on ? Color.white : Color(white: 0.47))
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 4)
                Image(systemName: "calendar").font(.system(size: 18)).foregroundStyle(on ? Color.white : Color(white: 0.47))
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: 51)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(on ? Color.clear : Color(white: 0.135)))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(on ? Self.blue : Color.clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var wheel: some View {
        Group {
            switch tab {
            case .day: DateWheel(columns: [.day, .month, .year], date: $picked, range: lowest...today)
            case .month: DateWheel(columns: [.month, .year], date: $picked, range: lowest...today)
            case .year: DateWheel(columns: [.year], date: $picked, range: lowest...today)
            case .custom:
                if editingEnd {
                    DateWheel(columns: [.day, .month, .year], date: $to, range: from...max(from, lastEnd))
                } else {
                    DateWheel(columns: [.day, .month, .year], date: Binding(get: { from }, set: { new in
                        from = new
                        to = clamp(to, from, lastEnd)   // the end moves to keep 1 to 31 days
                    }), range: lowest...today)
                }
            }
        }
        .id("\(tab.rawValue)\(editingEnd)")
        .frame(height: 216)
        .clipped()
    }

    private var accept: some View {
        Button(action: apply) {
            Text(tab == .custom ? "Accept Custom Date Range" : tab == .day ? "Accept Date" : "Accept \(tab.rawValue)")
                .font(.app(size: 13.5, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Self.blue))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func apply() {
        func back(_ c: Calendar.Component, _ d: Date) -> Int {
            guard let now = cal.dateInterval(of: c, for: Date())?.start,
                  let then = cal.dateInterval(of: c, for: d)?.start else { return 0 }
            return min(0, cal.dateComponents([c], from: now, to: then).value(for: c) ?? 0)
        }
        let new: (String, Int)
        switch tab {
        case .day: new = (ImpactPeriod.day.rawValue, back(.day, picked))
        case .month: new = (ImpactPeriod.month.rawValue, back(.month, picked))
        case .year: new = (ImpactPeriod.year.rawValue, back(.year, picked))
        case .custom:
            // One day on its own is shown as that Day.
            if cal.isDate(from, inSameDayAs: to) { new = (ImpactPeriod.day.rawValue, back(.day, from)) }
            else { new = (CustomSpan(start: from, end: to).stored, 0) }
        }
        periodRaw = new.0
        offset = new.1
        close()
    }
}

/// A label with room on its left, so a column can start a set gap in from its edge.
final class InsetLabel: UILabel {
    var inset: CGFloat = 0 { didSet { setNeedsDisplay() } }
    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: UIEdgeInsets(top: 0, left: inset, bottom: 0, right: 0)))
    }
}

/// The iPhone wheel with the app's font: day and month roll round, unavailable values are grey and
/// the wheel returns to the nearest allowed date.
struct DateWheel: UIViewRepresentable {
    enum Column { case day, month, year }
    let columns: [Column]
    @Binding var date: Date
    let range: ClosedRange<Date>

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIPickerView {
        let p = UIPickerView()
        p.dataSource = context.coordinator
        p.delegate = context.coordinator
        p.overrideUserInterfaceStyle = .dark
        p.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.show(p, animated: false)
        return p
    }

    func updateUIView(_ p: UIPickerView, context: Context) {
        let changed = context.coordinator.parent.range != range
        context.coordinator.parent = self
        if changed { p.reloadAllComponents() }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIPickerView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 320, height: 216)
    }

    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
        var parent: DateWheel
        private let cal = Calendar(identifier: .gregorian)
        private static let loops = 200
        private static let months = ["January", "February", "March", "April", "May", "June", "July", "August",
                                     "September", "October", "November", "December"]
        /// What each column is on now.
        private var day = 1, month = 1, year = 2026
        private let years: [Int]

        init(_ parent: DateWheel) {
            self.parent = parent
            let c = Calendar(identifier: .gregorian)
            let lo = c.component(.year, from: parent.range.lowerBound), hi = c.component(.year, from: Date())
            years = Array((min(lo, hi) - 3)...(hi + 3))
            super.init()
        }

        func show(_ p: UIPickerView, animated: Bool) {
            let c = cal.dateComponents([.year, .month, .day], from: parent.date)
            day = c.day ?? 1; month = c.month ?? 1; year = c.year ?? year
            move(p, animated: animated)
        }

        private func move(_ p: UIPickerView, animated: Bool) {
            for (i, col) in parent.columns.enumerated() {
                let current = p.selectedRow(inComponent: i)
                let row: Int
                switch col {
                case .year: row = years.firstIndex(of: year) ?? 0
                case .month: row = nearest(current, value: month - 1, count: 12)
                case .day: row = nearest(current, value: day - 1, count: 31)
                }
                p.selectRow(row, inComponent: i, animated: animated)
            }
            p.reloadAllComponents()
        }

        /// The row showing `value` closest to where the column is (the middle of the loop at first).
        private func nearest(_ current: Int, value: Int, count: Int) -> Int {
            let base = current < count ? count * (Self.loops / 2) : current
            var delta = value - base % count
            if delta > count / 2 { delta -= count }
            if delta < -count / 2 { delta += count }
            return base + delta
        }

        private func make(_ y: Int, _ m: Int, _ d: Int) -> Date? {
            cal.date(from: DateComponents(year: y, month: m, day: d))
        }
        private func length(_ y: Int, _ m: Int) -> Int {
            make(y, m, 1).flatMap { cal.range(of: .day, in: .month, for: $0)?.count } ?? 31
        }

        /// Whether a value can be chosen with the other columns where they are.
        private func allowed(_ col: Column, _ v: Int) -> Bool {
            let lo = parent.range.lowerBound, hi = parent.range.upperBound
            if parent.columns.contains(.day) {
                let y = col == .year ? v : year, m = col == .month ? v : month
                let d = col == .day ? v : min(day, length(y, m))
                guard d <= length(y, m), let date = make(y, m, d) else { return false }
                return date >= lo && date <= hi
            }
            let unit: Calendar.Component = parent.columns.contains(.month) ? .month : .year
            guard let date = make(col == .year ? v : year, unit == .year ? 1 : (col == .month ? v : month), 1) else { return false }
            return cal.compare(date, to: lo, toGranularity: unit) != .orderedAscending
                && cal.compare(date, to: hi, toGranularity: unit) != .orderedDescending
        }

        func numberOfComponents(in pickerView: UIPickerView) -> Int { parent.columns.count }

        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            switch parent.columns[component] {
            case .day: return 31 * Self.loops
            case .month: return 12 * Self.loops
            case .year: return years.count
            }
        }

        private static let font = UIFont(name: AppFont.name(.regular), size: 21) ?? .systemFont(ofSize: 21)
        private static func textWidth(_ s: String) -> CGFloat {
            ceil((s as NSString).size(withAttributes: [.font: font]).width)
        }
        /// Space either side of the longest month (the same gap to the day and to the year).
        private static let gap: CGFloat = 34
        private static let monthWidth: CGFloat = months.map(textWidth).max() ?? 110

        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
            let slack: CGFloat = 8   // the selected row is drawn a little larger
            switch parent.columns[component] {
            case .day: return Self.textWidth("28") + slack
            case .month: return Self.gap + Self.monthWidth + slack + Self.gap
            case .year: return parent.columns.count == 1 ? 160 : Self.textWidth("2026") + slack
            }
        }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat { 36 }

        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            let label = (view as? InsetLabel) ?? InsetLabel()
            let col = parent.columns[component]
            let value: Int
            switch col {
            case .day: value = row % 31 + 1
            case .month: value = row % 12 + 1
            case .year: value = years[row]
            }
            label.text = col == .month ? Self.months[value - 1] : String(value)
            label.font = UIFont(name: AppFont.name(.regular), size: 21) ?? .systemFont(ofSize: 21)
            label.textColor = allowed(col, value) ? .white : UIColor(white: 1, alpha: 0.2)
            // Day: right edge; Month: left edge, a gap in from the day; Year: left edge (the month column's
            // spare room on its right is the same gap again).
            label.textAlignment = parent.columns.count == 1 ? .center : (col == .day ? .right : .left)
            label.inset = col == .month ? Self.gap : 0
            return label
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            switch parent.columns[component] {
            case .day: day = row % 31 + 1
            case .month: month = row % 12 + 1
            case .year: year = years[row]
            }
            let d = min(day, length(year, month))
            guard var date = make(year, month, parent.columns.contains(.day) ? d : 1) else { return }
            // Month and Year wheels may land on a month whose 1st is before the first record: that's fine.
            date = min(max(date, parent.range.lowerBound), parent.range.upperBound)
            let c = cal.dateComponents([.year, .month, .day], from: date)
            day = c.day ?? day; month = c.month ?? month; year = c.year ?? year
            move(pickerView, animated: true)
            parent.date = date
        }
    }
}
