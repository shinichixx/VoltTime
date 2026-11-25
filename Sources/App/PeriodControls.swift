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

/// "Day ⌄" timescale picker (Tesla app): tapping it drops a dark panel under it titled Timescale, with
/// Day … Lifetime, a line, then Go to Today (only when you're not on the current period) and Choose Date…,
/// which opens a calendar and goes to the day / week / month / year that date falls in.
struct PeriodMenu: View {
    @Binding var periodRaw: String
    @Binding var offset: Int
    /// Energy page: a small rounded box with a grey border (in the top bar it's plain text).
    var boxed = false
    /// Earliest date Choose Date allows.
    var firstDay: Date? = nil

    @State private var frame: CGRect = .zero

    private var period: ImpactPeriod { ImpactPeriod(rawValue: periodRaw) ?? .month }

    var body: some View {
        Button {
            // Shown by the app's root (over every page) so it appears and goes in place, once.
            TimescalePresenter.shared.request = .init(anchor: frame, period: $periodRaw, offset: $offset, firstDay: firstDay)
        } label: {
            HStack(spacing: 5) {
                Text(period.rawValue).font(.app(size: boxed ? 13.5 : 15, weight: boxed ? .medium : .regular))
                Image(systemName: "chevron.down").font(.system(size: boxed ? 10 : 11, weight: .semibold)).foregroundStyle(TeslaDark.rowLabel)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, boxed ? 10 : 0)
            .padding(.vertical, boxed ? 5 : 0)
            .background {
                if boxed {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color(white: 0.11))
                    RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color(white: 0.3), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(GeometryReader { g in
            Color.clear
                .onAppear { frame = g.frame(in: .global) }
                .onChange(of: g.frame(in: .global)) { _, f in frame = f }
        })
    }
}

/// The one Timescale panel, drawn over the whole app by the root view.
@MainActor
final class TimescalePresenter: ObservableObject {
    static let shared = TimescalePresenter()
    struct Request {
        let anchor: CGRect
        let period: Binding<String>
        let offset: Binding<Int>
        let firstDay: Date?
    }
    @Published var request: Request?
}

struct TimescaleOverlay: View {
    @ObservedObject private var presenter = TimescalePresenter.shared

    var body: some View {
        if let r = presenter.request {
            TimescalePanel(periodRaw: r.period, offset: r.offset, anchor: r.anchor, firstDay: r.firstDay) {
                presenter.request = nil
            }
        }
    }
}

private struct TimescalePanel: View {
    @Binding var periodRaw: String
    @Binding var offset: Int
    let anchor: CGRect
    let firstDay: Date?
    let close: () -> Void

    @State private var choosing = false
    @State private var picked = Date()

    private let cal = Calendar.current
    private let width: CGFloat = 214
    private var period: ImpactPeriod { ImpactPeriod(rawValue: periodRaw) ?? .month }

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                Color.black.opacity(choosing ? 0.45 : 0.001)
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                if choosing {
                    VStack { Spacer(); calendar }
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    panel
                        .offset(x: min(max(12, anchor.maxX - width), g.size.width - width - 12),
                                y: anchor.maxY + 6 - g.frame(in: .global).minY)
                }
            }
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Timescale").font(.app(size: 12, weight: .medium)).foregroundStyle(Color(white: 0.55))
                .padding(.top, 14).padding(.bottom, 4)
            ForEach(ImpactPeriod.allCases) { p in
                row(p.rawValue, check: p == period) {
                    if p != period { periodRaw = p.rawValue; offset = 0 }
                    close()
                }
            }
            Rectangle().fill(Color(white: 0.32)).frame(height: 1).padding(.vertical, 6)
            if offset != 0 && period != .lifetime {
                row("Go to Today", check: false) { offset = 0; close() }
            }
            if period != .lifetime {
                row("Choose Date…", check: false) {
                    picked = PeriodRange.make(period, offset: offset, firstDay: firstDay).start
                    withAnimation(.easeOut(duration: 0.2)) { choosing = true }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .frame(width: width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(red: 52 / 255, green: 53 / 255, blue: 57 / 255)))
        .shadow(color: .black.opacity(0.5), radius: 14, y: 4)
    }

    private func row(_ title: String, check: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.app(size: 14.5, weight: .medium)).foregroundStyle(.white)
                Spacer()
                if check { Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white) }
            }
            .frame(height: 37)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var lowest: Date { firstDay.map { cal.startOfDay(for: $0) } ?? cal.date(byAdding: .year, value: -5, to: Date()) ?? Date() }

    private var calendar: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { close() }.foregroundStyle(TeslaDark.rowLabel)
                Spacer()
                Text("Choose Date").font(.app(size: 15, weight: .semibold))
                Spacer()
                Button("Go") { go() }.font(.app(size: 15, weight: .semibold)).foregroundStyle(.white)
            }
            .font(.app(size: 15))
            .padding(.horizontal, 20)
            .padding(.top, 18)
            DatePicker("", selection: $picked, in: lowest...Date(), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(Color(white: 0.85))
                .padding(.horizontal, 12)
            Text(hint).font(.app(size: 11.5)).foregroundStyle(TeslaDark.rowLabel)
                .padding(.bottom, 34)
        }
        .foregroundStyle(.white)
        .background(UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14, style: .continuous)
            .fill(Color(red: 36 / 255, green: 37 / 255, blue: 40 / 255)))
        .environment(\.colorScheme, .dark)
        .transition(.move(edge: .bottom))
    }

    private var hint: String {
        switch period {
        case .day: return "Opens this day."
        case .week: return "Opens the week this day falls in."
        case .month: return "Opens the month this day falls in."
        default: return "Opens the year this day falls in."
        }
    }

    /// Offset of the period holding `picked`, counted back from the current one.
    private func go() {
        guard let c = period.component,
              let now = cal.dateInterval(of: c, for: Date())?.start,
              let then = cal.dateInterval(of: c, for: picked)?.start else { close(); return }
        offset = min(0, cal.dateComponents([c], from: now, to: then).value(for: c) ?? 0)
        close()
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
