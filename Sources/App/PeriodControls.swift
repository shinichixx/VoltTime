import SwiftUI

/// Start / end / label of the period being shown (Impact and Energy pages).
struct PeriodRange: Equatable {
    let start: Date
    let end: Date
    let label: String

    static func make(_ period: ImpactPeriod, offset: Int, firstDay: Date?, stored: String = "") -> PeriodRange {
        let cal = Calendar.current
        let now = Date()
        if period == .custom, let s = CustomSpan(stored: stored) {
            return PeriodRange(start: s.start, end: cal.date(byAdding: .day, value: 1, to: s.end) ?? s.end, label: s.label)
        }
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
        case .lifetime, .custom: label = ""
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
        let canBack = period.steps && (firstDay.map { range.start > $0 } ?? false)
        let canForward = period.steps && offset < 0
        HStack {
            Button { offset -= 1 } label: { Image(systemName: "chevron.left").padding(10) }
                .disabled(!canBack)
                .foregroundStyle(canBack ? TeslaDark.rowLabel : Color(white: 0.23))
                .opacity(period.steps ? 1 : 0)
            Spacer()
            Text(range.label).font(.app(size: 15, weight: .medium))
            Spacer()
            Button { offset += 1 } label: { Image(systemName: "chevron.right").padding(10) }
                .disabled(!canForward)
                .foregroundStyle(canForward ? TeslaDark.rowLabel : Color(white: 0.23))
                .opacity(period.steps ? 1 : 0)
        }
        .font(.system(size: 15, weight: .semibold))
        .buttonStyle(.plain)
    }
}

/// "Day ⌄" timescale picker (Tesla app): tapping it drops a dark panel under it titled Timescale, with
/// Day … Lifetime, a line, then Go to Today (only when you're not on the current period) and Choose Date…,
/// which opens the Choose Date sheet (ChooseDate.swift).
struct PeriodMenu: View {
    @Binding var periodRaw: String
    @Binding var offset: Int
    /// Energy page: a small rounded box with a grey border (in the top bar it's plain text).
    var boxed = false
    /// Earliest date Choose Date allows.
    var firstDay: Date? = nil

    @State private var frame: CGRect = .zero

    private var period: ImpactPeriod { ImpactPeriod(stored: periodRaw) ?? .month }

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
    /// Choose Date is first laid out below the screen, then slid up, so its UIKit wheel moves with the rest.
    @State private var sheetUp = false

    private let cal = Calendar.current
    private let width: CGFloat = 214
    private var period: ImpactPeriod { ImpactPeriod(stored: periodRaw) ?? .month }

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                Color.black.opacity(sheetUp ? 0.45 : 0.001)
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                panel
                    .offset(x: min(max(12, anchor.maxX - width), g.size.width - width - 12),
                            y: anchor.maxY + 6 - g.frame(in: .global).minY)
                    .opacity(sheetUp ? 0 : 1)
                    .allowsHitTesting(!choosing)
                if choosing {
                    VStack {
                        Spacer()
                        ChooseDateSheet(periodRaw: $periodRaw, offset: $offset, firstDay: firstDay, close: close)
                            .geometryGroup()
                            .offset(y: sheetUp ? 0 : 640)   // taller than the sheet and the bottom safe area
                            .onAppear {
                                // Next run loop: the wheel is in place (off screen) before the slide starts.
                                DispatchQueue.main.async {
                                    withAnimation(.easeOut(duration: 0.28)) { sheetUp = true }
                                }
                            }
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
            }
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Timescale").font(.app(size: 12, weight: .medium)).foregroundStyle(Color(white: 0.55))
                .padding(.top, 14).padding(.bottom, 4)
            ForEach(ImpactPeriod.allCases.filter { $0 != .custom }) { p in
                row(p.rawValue, check: p == period) {
                    if p != period { periodRaw = p.rawValue; offset = 0 }
                    close()
                }
            }
            Rectangle().fill(Color(white: 0.32)).frame(height: 1).padding(.vertical, 6)
            if (offset != 0 && period.steps) || period == .custom {
                // A custom range goes back to today as a Day.
                row("Go to Today", check: false) { if period == .custom { periodRaw = ImpactPeriod.day.rawValue }; offset = 0; close() }
            }
            if period != .lifetime {
                row("Choose Date…", check: false) {
                    choosing = true
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
}


/// Numbers in the app: thousands always with a comma ("1,065"), one decimal under 100 ("13.7").
enum Num {
    static let en = Locale(identifier: "en_US")
    static func whole(_ v: Double) -> String { Int(v.rounded()).formatted(.number.locale(en)) }
    /// One decimal (no decimals from 100 up, or when `whole`), with a comma for thousands: 1,284.
    static func kwh(_ v: Double, whole w: Bool = false) -> String { (w || abs(v) >= 100) ? whole(v) : one(v) }
    static func one(_ v: Double) -> String { v.formatted(.number.locale(en).precision(.fractionLength(1))) }
}


/// Where My Car and My Home are mid-swipe, and how far each is scrolled. The two photos are drawn
/// behind the pager (so a page edge never cuts them) and fade by these numbers.
@MainActor
final class PagerFX: ObservableObject {
    @Published var carX: CGFloat = 0
    @Published var carScroll: CGFloat = 0
    @Published var homeX: CGFloat? = nil
    @Published var homeScroll: CGFloat = 0
    /// Screen y of the top of the house backdrop (for the photo's tap areas).
    @Published var homePhotoTop: CGFloat? = nil
    /// iOS 18+: the pager's own scroll offset sets carX / homeX (build 102). The pages' screen positions
    /// go stale when the pager jumps behind the Menu, which left the house showing on the car page.
    var pagerDriven = false

    /// 1 while the page is in place, 0 once it's half way off.
    static func swipe(_ x: CGFloat?, _ w: CGFloat) -> Double {
        guard let x else { return 0 }
        return max(0, 1 - 2 * min(1, abs(x) / max(w, 1)))
    }
    static func scrolled(_ y: CGFloat) -> Double { max(0.08, 1 - Double(max(y, 0)) / 150) }
}

/// Where the pager is scrolled to, and how wide one page is.
struct PagerGeo: Equatable { var x: CGFloat; var w: CGFloat }

extension View {
    /// iOS 18+: the car sits at -offset, the house one page to the right of it.
    @ViewBuilder func pagerFX(_ fx: PagerFX) -> some View {
        if #available(iOS 18.0, *) {
            onScrollGeometryChange(for: PagerGeo.self) { g in
                PagerGeo(x: g.contentOffset.x + g.contentInsets.leading, w: g.containerSize.width)
            } action: { _, p in
                fx.pagerDriven = true
                fx.carX = -p.x
                fx.homeX = p.w - p.x
            }
        } else {
            self
        }
    }
}


extension View {
    /// A row ("Today" + the Timescale box) that stays put under the top bar while this scroll view moves
    /// beneath it; the content fades out just under the row instead of ending in a hard line.
    /// `fade: false` while the Day reading box rises into that strip, so the box stays solid.
    func pinnedTop<H: View>(fade: Bool = true, @ViewBuilder _ row: () -> H) -> some View {
        VStack(spacing: 0) {
            row()
            self.mask(
                VStack(spacing: 0) {
                    LinearGradient(colors: [fade ? .clear : .black, .black], startPoint: .top, endPoint: .bottom).frame(height: 12)
                    Color.black
                }
            )
        }
    }
}
