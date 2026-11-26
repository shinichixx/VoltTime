import SwiftUI
import Charts

/// Tesla-app style Energy page: "Today" and the boxed timescale picker at the top, one component at a time
/// (floating bar at the bottom), a graph you swipe through continuously (Day runs on across midnight; Week,
/// Month and Year settle on a whole period), the kW / kWh scale fitted to what's on screen, and Energy Flow
/// tables below.
enum EnergyComponent: String, CaseIterable, Identifiable, Hashable {
    case all, home, solar, vehicle, grid
    var id: String { rawValue }

    /// Order on the floating bar.
    static let barOrder: [EnergyComponent] = [.all, .home, .vehicle, .solar, .grid]

    /// Page title (Tesla app: the component's name).
    var pageTitle: String {
        switch self {
        case .all: return "Energy"
        case .home: return "Home"
        case .solar: return "Solar"
        case .vehicle: return "Vehicle"
        case .grid: return "Grid"
        }
    }

    /// The graph's colour, used for the dot under the selected icon.
    var color: Color {
        switch self {
        case .all: return .white
        case .home: return EnergyColor.home
        case .solar: return EnergyColor.solar
        case .vehicle: return EnergyColor.vehicle
        case .grid: return EnergyColor.grid
        }
    }

    var glyph: FlowGlyph.Kind {
        switch self {
        case .all: return .all
        case .home: return .home
        case .solar: return .solar
        case .vehicle: return .car
        case .grid: return .grid
        }
    }
}

enum EnergyColor {
    static let solar = Color(red: 1, green: 0.8, blue: 0.2)
    static let home = Color(red: 0.36, green: 0.61, blue: 1)
    static let vehicle = Color(red: 0.9, green: 0.22, blue: 0.23)
    static let grid = Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)
    static let gridOut = Color(white: 0.42)
    /// Row border and the eye filter's lines (Tesla app).
    static let focus = Color(red: 58 / 255, green: 86 / 255, blue: 226 / 255)
    static let muted = Color(white: 0.45)
}

/// How the graph is filtered: a tapped table row (its layer keeps colour and fill, the rest go grey lines)
/// and the eye (every line blue, no fill).
struct EnergyLook: Equatable {
    var focus: String? = nil
    var outline = false
    func style(_ key: String, _ c: Color) -> (line: Color, fill: Bool) {
        if let f = focus { return f == key ? (c, true) : (outline ? EnergyColor.focus : EnergyColor.muted, false) }
        return outline ? (EnergyColor.focus, false) : (c, true)
    }
}

struct EnergyPart: Identifiable {
    let name: String
    let color: Color
    let kwh: Double
    var glyph: FlowGlyph.Kind = .grid
    /// Which graph layer this row is (defaults to the name).
    var key: String? = nil
    var layer: String { key ?? name }
    var id: String { name }
}

/// One time step on a graph: the energy flow in that step, and the factor that turns it into what the graph
/// shows (×4 for a 15-minute step gives kW; 1 for a day or month bar gives kWh).
struct FlowPoint: Identifiable {
    let date: Date
    let flow: EnergyFlow
    let k: Double
    var id: Double { date.timeIntervalSince1970 }
}

// MARK: - Page

struct EnergyView: View {
    @ObservedObject var store: EnergyStore
    @AppStorage("energy.period") private var periodRaw = ImpactPeriod.day.rawValue
    @State private var compRaw: String
    /// 0 = the current day / week / month / year, -1 = the one before, …
    @State private var offset = 0
    /// Which way the last swipe went (the graph slides in from that side).
    @State private var forward = false
    /// Tap and hold on the graph: the time (or bar) being read.
    @State private var selection: Date?
    /// Table-row filter and the eye (reset each time Energy opens).
    @State private var look = EnergyLook()
    @State private var folded = false

    init(store: EnergyStore, start: EnergyComponent = .all) {
        _store = ObservedObject(wrappedValue: store)
        _compRaw = State(initialValue: start.rawValue)
    }

    private let cal = Calendar.current
    private var period: ImpactPeriod { ImpactPeriod(stored: periodRaw) ?? .day }
    private var comp: EnergyComponent { EnergyComponent(rawValue: compRaw) ?? .all }

    private var range: PeriodRange { PeriodRange.make(period, offset: offset, firstDay: store.firstDay, stored: periodRaw) }
    private var cover: Coverage { store.coverage(range) }
    /// Nothing recorded at all: show "–", not 0 (which would look like a real reading).
    private var noData: Bool { cover.have == 0 && !store.loading }
    private var canBack: Bool { period.steps && (store.firstDay.map { range.start > $0 } ?? false) }
    private var canForward: Bool { period.steps && offset < 0 }

    /// One swipe, one period: the old graph slides out and the next one slides in.
    private func step(_ by: Int) {
        guard by < 0 ? canBack : canForward else { return }
        forward = by > 0
        selection = nil
        DispatchQueue.main.async {   // the leaving graph picks up the new direction first
            withAnimation(.easeInOut(duration: 0.28)) { offset += by }
        }
    }

    private var total: EnergyFlow {
        let r = range
        if period == .day { return store.flow(r.start) ?? EnergyFlow() }
        return store.flowTotal(from: r.start, to: r.end)
    }

    var body: some View {
        let t = total
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                // Pinned: the title row, the totals and the graph down to the line under it; only what's below scrolls.
                titleRow.padding(.horizontal, 20)
                header(t)
                    .padding(.horizontal, 20)
                    ZStack {
                        EnergyChartView(store: store, period: period, comp: comp, range: range, swipe: step, selection: $selection,
                                        look: look, canHold: true)
                            .id("\(periodRaw)|\(offset)")
                            .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading),
                                                    removal: .move(edge: forward ? .leading : .trailing)))
                    }
                    .frame(height: 270)
                    .clipShape(OpenTopClip())   // the slide stays inside the graph; the reading box may rise above it
                    .padding(.top, 18)
                if let note = cover.note(day: period == .day, loading: store.loading), cover.have > 0 {
                    Text(note).font(.app(size: 11.5)).foregroundStyle(TeslaDark.rowLabel)
                        .padding(.horizontal, 20).padding(.top, 8)
                }
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5).padding(.top, 14)
                    .opacity(selection == nil ? 1 : 0.25)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Group {
                            Group {
                                if comp == .grid || comp == .all {
                                    Text(netLine(t)).font(.app(size: 14, weight: .semibold)).padding(.top, 16)
                                }
                                HStack(spacing: 18) {
                                    Text("Energy Flow").font(.app(size: 14, weight: .semibold))
                                    Spacer()
                                    Button { look.outline.toggle(); if !look.outline { look.focus = nil } } label: {
                                        Image(systemName: look.outline ? "eye.slash" : "eye").font(.system(size: 15, weight: .medium))
                                            .frame(width: 26, height: 26)
                                    }
                                    Button { withAnimation(.easeInOut(duration: 0.3)) { folded.toggle() } } label: {
                                        Image(systemName: "chevron.up").font(.system(size: 14, weight: .medium))
                                            .rotationEffect(.degrees(folded ? 180 : 0))
                                            .frame(width: 26, height: 26)
                                    }
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.white)
                                .padding(.top, 22)
                                VStack(alignment: .leading, spacing: 0) {
                                    if !folded {
                                        flowTables(t)
                                            .transition(.move(edge: .top).combined(with: .opacity))
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .clipped()
                            }
                            if let msg = store.message {
                                Text(msg).font(.app(size: 11)).foregroundStyle(TeslaDark.importing).padding(.top, 8)
                            }
                        }
                        .padding(.horizontal, 20)
                        .opacity(selection == nil ? 1 : 0.25)   // dims while reading the graph (Tesla app)
                        .animation(.easeOut(duration: 0.15), value: selection == nil)
                        Color.clear.frame(height: 96)   // clear of the floating bar
                    }
                }
                .scrollIndicators(.hidden)
                .mask(VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 12)
                    Color.black
                })
            }
            // Tesla app: content fades to black from just above the floating bar, solid from two-thirds down it.
            VStack(spacing: 0) {
                LinearGradient(stops: [.init(color: TeslaDark.bg.opacity(0), location: 0),
                                       .init(color: TeslaDark.bg.opacity(0.55), location: 0.5),
                                       .init(color: TeslaDark.bg, location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 44)
                Color.clear.frame(height: 21)
                    .background(TeslaDark.bg.ignoresSafeArea(edges: .bottom))
            }
            .allowsHitTesting(false)
            EnergyTabBar(selected: Binding(get: { comp }, set: { compRaw = $0.rawValue; selection = nil }))
                .padding(.bottom, 6)
        }
        .teslaPage(comp.pageTitle)
        .onChange(of: compRaw) { _, _ in look.focus = nil }
        .onChange(of: periodRaw) { _, _ in look.focus = nil }
        .onChange(of: offset) { _, _ in look.focus = nil }
        .task(id: "\(periodRaw)|\(offset)") {
            // Saved days show at once; this only tops up today / missing days (at most once a minute).
            await store.refresh()
        }
    }

    // MARK: Header

    /// "Today" and the Day box: pinned under the top bar, the page scrolls beneath.
    private var titleRow: some View {
        HStack(alignment: .center) {
            Text(headerLabel).font(.app(size: 17, weight: .semibold))
            if store.loading && selection == nil { ProgressView().tint(.white).scaleEffect(0.6) }
            Spacer()
            PeriodMenu(periodRaw: $periodRaw, offset: $offset, boxed: true, firstDay: store.firstDay)
                .opacity(selection == nil ? 1 : 0)
                .allowsHitTesting(selection == nil)
        }
        .padding(.top, 6)
    }

    private func header(_ t: EnergyFlow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
            switch comp {
            case .all:
                HStack(alignment: .top, spacing: 0) {
                    figure("Total Used", arrow: nil, t.house + t.car)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Self-Powered").font(.app(size: 13)).foregroundStyle(TeslaDark.rowLabel)
                        Text(selfPowered(t)).font(.app(size: 24, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 14)
            case .grid:
                HStack(alignment: .top, spacing: 0) {
                    figure("Imported", arrow: "arrow.up", t.imp)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    figure("Exported", arrow: "arrow.down", t.exp)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 14)
            case .home:
                figure("Total Used", arrow: nil, t.house).padding(.top, 14)
            case .solar:
                figure("Total Generated", arrow: nil, t.solar).padding(.top, 14)
            case .vehicle:
                figure("Charged", arrow: "arrow.down", t.car).padding(.top, 14)
            }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(selection == nil ? 1 : 0)   // the reading takes this space while you hold the graph
            .overlay(alignment: .topLeading) {
                // Week / Month / Year: the held bar's reading sits here instead of a box (Tesla app).
                if let sel = selection, period != .day {
                    let gs = EnergyReading.groups(comp, selectedFlow(sel), 1, unit: "kWh", gridBoth: true, whole: whole)
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(gs.indices, id: \.self) { i in
                            EnergyReadingView(group: gs[i], unit: "kWh", large: true)
                                .frame(maxWidth: gs.count > 1 ? .infinity : nil, alignment: .leading)
                        }
                    }
                    .padding(.top, 14)
                }
            }
        }
    }

    /// The held bar's day or month (as the chart sums it: up to today).
    private func selectedFlow(_ sel: Date) -> EnergyFlow {
        let byMonth = period == .year || period == .lifetime
        let start = byMonth ? (cal.dateInterval(of: .month, for: sel)?.start ?? sel) : cal.startOfDay(for: sel)
        let next = cal.date(byAdding: byMonth ? .month : .day, value: 1, to: start) ?? start
        let end = min(next, cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? next)
        return store.flowTotal(from: max(start, range.start), to: end)
    }

    /// "Today", or while reading the graph "Today · 2:35 PM" (Day) / the bar's day or month.
    private var headerLabel: String {
        guard let sel = selection else { return range.label }
        switch period {
        case .day:
            return range.label + " · " + sel.addingTimeInterval(-450).formatted(date: .omitted, time: .shortened)
        case .week, .month, .custom:
            return sel.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        default:
            return sel.formatted(.dateTime.month(.wide).year())
        }
    }

    private func figure(_ title: String, arrow: String?, _ v: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if let arrow { Image(systemName: arrow).font(.system(size: 11, weight: .medium)) }
                Text(title).font(.app(size: 13))
            }
            .foregroundStyle(TeslaDark.rowLabel)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(noData ? "–" : Num.kwh(v, whole: whole)).font(.app(size: 24, weight: .semibold))
                Text("kWh").font(.app(size: 13)).foregroundStyle(TeslaDark.rowLabel)
            }
        }
    }

    private func netLine(_ t: EnergyFlow) -> String {
        if noData { return "Net Grid Usage: –" }
        let net = t.imp - t.exp
        return "Net Grid Usage: \(Num.kwh(abs(net), whole: whole)) kWh \(net >= 0 ? "Imported" : "Exported")"
    }

    // MARK: Energy Flow tables

    @ViewBuilder private func flowTables(_ t: EnergyFlow) -> some View {
        switch comp {
        case .home:
            table("Used From", arrow: nil, [
                EnergyPart(name: "Solar", color: EnergyColor.solar, kwh: t.homeSolar, glyph: .solar),
                EnergyPart(name: "Grid", color: EnergyColor.grid, kwh: t.homeGrid, glyph: .grid)])
        case .vehicle:
            table("Charged From", arrow: nil, [
                EnergyPart(name: "Solar", color: EnergyColor.solar, kwh: t.carSolar, glyph: .solar),
                EnergyPart(name: "Grid", color: EnergyColor.grid, kwh: t.carGrid, glyph: .grid)])
        case .solar:
            table("Used By", arrow: nil, [
                EnergyPart(name: "Home", color: EnergyColor.home, kwh: t.homeSolar, glyph: .home),
                EnergyPart(name: "Vehicle", color: EnergyColor.vehicle, kwh: t.carSolar, glyph: .car),
                EnergyPart(name: "Grid", color: EnergyColor.grid, kwh: t.exp, glyph: .grid)])
        case .grid:
            table("Used By", arrow: "arrow.up", [
                EnergyPart(name: "Home", color: EnergyColor.home, kwh: t.homeGrid, glyph: .home),
                EnergyPart(name: "Vehicle", color: EnergyColor.vehicle, kwh: t.carGrid, glyph: .car)])
            table("Exported From", arrow: "arrow.down", [
                EnergyPart(name: "Solar", color: EnergyColor.solar, kwh: t.exp, glyph: .solar, key: "Exported")])
        case .all:
            table("Supplied By", arrow: nil, [
                EnergyPart(name: "Solar", color: EnergyColor.solar, kwh: t.solar, glyph: .solar, key: "solar"),
                EnergyPart(name: "Grid", color: EnergyColor.grid, kwh: t.imp, glyph: .grid, key: "imp")])
            table("Used By", arrow: nil, [
                EnergyPart(name: "Home", color: EnergyColor.home, kwh: t.house, glyph: .home, key: "home"),
                EnergyPart(name: "Vehicle", color: EnergyColor.vehicle, kwh: t.car, glyph: .car, key: "car"),
                EnergyPart(name: "Grid", color: EnergyColor.grid, kwh: t.exp, glyph: .grid, key: "export")])
        }
    }

    /// Share of home + car covered without the grid.
    private func selfPowered(_ f: EnergyFlow) -> String {
        let used = f.house + f.car
        guard used > 0 else { return "—" }
        return "\(Int((max(0, min(1, 1 - f.imp / used)) * 100).rounded()))%"
    }

    /// Bordered table: icon, percentage, name, kWh (Tesla app).
    private func table(_ caption: String, arrow: String?, _ parts: [EnergyPart]) -> some View {
        let sum = parts.reduce(0) { $0 + $1.kwh }
        let border = Color(white: 0.24)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                if let arrow { Image(systemName: arrow).font(.system(size: 11, weight: .medium)) }
                Text(caption).font(.app(size: 13))
            }
            .foregroundStyle(TeslaDark.rowLabel)
            VStack(spacing: 0) {
                ForEach(Array(parts.enumerated()), id: \.offset) { i, p in
                    if i > 0 { Rectangle().fill(border).frame(height: 1) }
                    HStack(spacing: 0) {
                        FlowGlyph(kind: p.glyph, color: p.color, height: 15, maxWidth: 18)
                            .frame(width: 34, alignment: .center)
                        Text(noData ? "–" : sum > 0 ? "\(Int((p.kwh / sum * 100).rounded()))%" : "0%")
                            .font(.app(size: 14, weight: .semibold))
                            .frame(width: 48, alignment: .leading)
                        Text(p.name).font(.app(size: 13.5)).foregroundStyle(TeslaDark.rowLabel)
                        Spacer()
                        Text(noData ? "–" : Num.kwh(p.kwh, whole: whole) + " kWh").font(.app(size: 13.5))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                    .overlay {
                        if look.focus == p.layer {
                            RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(EnergyColor.focus, lineWidth: 2)
                        }
                    }
                    // Tap: only this layer keeps its colour on the graph; tap again to cancel.
                    .onTapGesture { look.focus = look.focus == p.layer ? nil : p.layer }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(border, lineWidth: 1))
        }
        .padding(.top, 14)
    }

    // MARK: All: legend and tiles

    private static let allNames = ["Solar", "Home", "Model 3", "Grid"]
    private static let allColors = [EnergyColor.solar, EnergyColor.home, EnergyColor.vehicle, EnergyColor.grid]

    private var allLegend: some View {
        HStack(spacing: 14) {
            ForEach([1, 2, 0, 3], id: \.self) { i in
                HStack(spacing: 5) {
                    Circle().fill(Self.allColors[i]).frame(width: 8, height: 8)
                    Text(Self.allNames[i]).font(.app(size: 12)).foregroundStyle(TeslaDark.labelGrey)
                }
            }
        }
    }

    private func allTiles(_ f: EnergyFlow) -> some View {
        let used = f.solar + f.imp - f.exp
        let selfPowered = used > 0 ? "\(Int((max(0, min(1, 1 - f.imp / used)) * 100).rounded()))%" : "—"
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            tile("sun.max.fill", EnergyColor.solar, "Solar", kwh(f.solar), "generated")
            tile("house.fill", EnergyColor.home, "Home", kwh(f.house), "consumption without car")
            tile("car.side.fill", EnergyColor.vehicle, "Model 3", kwh(f.car), "charged at home")
            tile("leaf.fill", TeslaDark.exporting, "Self-powered", selfPowered, "of home + car")
            tile("arrow.down.circle.fill", EnergyColor.grid, "Grid import", kwh(f.imp), "from TNB")
            tile("arrow.up.circle.fill", EnergyColor.grid, "Grid export", kwh(f.exp), "to TNB")
        }
    }

    private func kwh(_ v: Double) -> String { Num.kwh(v, whole: whole) + " kWh" }
    /// Year and Lifetime show whole kWh.
    private var whole: Bool { period == .year || period == .lifetime }

    private func tile(_ icon: String, _ color: Color, _ title: String, _ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(color)
                    .frame(width: 22, height: 14)
                Text(title).font(.app(size: 12, weight: .medium)).foregroundStyle(TeslaDark.labelGrey)
            }
            Text(value).font(.app(size: 19, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(caption).font(.app(size: 10.5)).foregroundStyle(TeslaDark.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(TeslaDark.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - The graph (one period at a time)

/// Draws only the period on screen. A sideways swipe asks the page for the next / previous period (it slides in);
/// tap and hold, then move, to read the values at a point.
private struct EnergyChartView: View {
    @ObservedObject var store: EnergyStore
    let period: ImpactPeriod
    let comp: EnergyComponent
    let range: PeriodRange
    let swipe: (Int) -> Void
    @Binding var selection: Date?
    var look = EnergyLook()
    /// Day view: holding only works with the page at the top (the box would hide under the pinned row).
    var canHold = true

    private let cal = Calendar.current
    private var isDay: Bool { period == .day }
    private var byMonth: Bool { period == .year || period == .lifetime }
    private var unit: Calendar.Component { byMonth ? .month : .day }

    /// Day: 15-minute steps (kW). Week and Month: a bar per day; Year and Lifetime: a bar per month (kWh).
    private var points: [FlowPoint] {
        if isDay {
            guard let raw = store.curve(range.start) else { return [] }
            let c = raw.minutes < 15 ? raw.coarsened(to: 15) : raw
            let step = TimeInterval(c.minutes * 60)
            var last = c.count
            if cal.isDateInToday(range.start) { last = min(c.count, max(0, Int(Date().timeIntervalSince(range.start) / step))) }
            let k = 60.0 / Double(c.minutes)
            return (0..<last).map { FlowPoint(date: range.start.addingTimeInterval(Double($0) * step + step / 2), flow: c.flow($0), k: k) }
        }
        var out: [FlowPoint] = []
        var d = range.start
        let end = min(range.end, cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date())
        if store.coverage(range).have == 0 { return [] }
        while d < end {
            let next = cal.date(byAdding: unit, value: 1, to: d) ?? end
            out.append(FlowPoint(date: d, flow: store.flowTotal(from: d, to: min(next, end)), k: 1))
            d = byMonth ? (cal.dateInterval(of: .month, for: next)?.start ?? next) : next
        }
        return out
    }

    /// Bars: through the end of the last bucket, so this month / today isn't cut off.
    private func xEnd(_ pts: [FlowPoint]) -> Date {
        guard !isDay, let last = pts.last?.date, let e = cal.date(byAdding: unit, value: 1, to: last) else { return range.end }
        return period == .lifetime ? e : max(range.end, e)
    }

    var body: some View {
        let pts = points
        let scale = yScale(pts)
        chart(pts, scale)
    }

    // MARK: What each view stacks

    /// (name, colour, value) per point; negative values go below zero.
    private func parts(_ p: FlowPoint) -> [(String, Color, Double)] {
        let f = p.flow, k = p.k
        switch comp {
        case .all, .home:
            return [("Solar", EnergyColor.solar, f.homeSolar * k), ("Grid", EnergyColor.grid, f.homeGrid * k)]
        case .solar:
            return [("Home", EnergyColor.home, f.homeSolar * k), ("Vehicle", EnergyColor.vehicle, f.carSolar * k),
                    ("Grid", EnergyColor.grid, f.exp * k)]
        case .vehicle:
            return [("Solar", EnergyColor.solar, f.carSolar * k), ("Grid", EnergyColor.grid, f.carGrid * k)]
        case .grid:
            // Import split by who used it (Tesla app): home in blue, the car in red on top; export below zero.
            return [("Home", EnergyColor.home, f.homeGrid * k), ("Vehicle", EnergyColor.vehicle, f.carGrid * k),
                    ("Exported", EnergyColor.solar, -f.exp * k)]
        }
    }

    /// Stretches where a layer has power, each with one step either side (so the edge eases down to the layer
    /// beneath); a layer with no power draws no edge line at all.
    struct Run: Identifiable { let id: Int; let points: [(Date, Double)] }
    static func runs(_ pts: [FlowPoint], has: (FlowPoint) -> Bool, edge: (FlowPoint) -> Double) -> [Run] {
        var out: [Run] = []
        var i = 0
        while i < pts.count {
            guard has(pts[i]) else { i += 1; continue }
            var j = i
            while j + 1 < pts.count && has(pts[j + 1]) { j += 1 }
            let lo = max(0, i - 1), hi = min(pts.count - 1, j + 1)
            out.append(Run(id: out.count, points: (lo...hi).map { (pts[$0].date, edge(pts[$0])) }))
            i = j + 1
        }
        return out
    }

    /// Grid's export is the one part drawn below zero.
    private func negative(_ i: Int) -> Bool { comp == .grid && i == 2 }

    /// Where part `i` sits at this point: stacked on the parts before it (above zero), or hanging below zero.
    private func bounds(_ p: FlowPoint, _ i: Int) -> (lo: Double, hi: Double) {
        let vs = parts(p).map(\.2)
        if negative(i) { return (min(vs[i], 0), 0) }
        let below = vs.prefix(i).enumerated().filter { !negative($0.offset) }.map { max($0.element, 0) }.reduce(0, +)
        return (below, below + max(vs[i], 0))
    }

    /// Strong (62%) at the far edge of the graph, 10% at the 0 line; the gradient spans the plot area.
    private func fade(_ c: Color, below: Bool, _ scale: EnergyScale, strong: Double = 0.62, weak: Double = 0.10) -> LinearGradient {
        let span = scale.domain.upperBound - scale.domain.lowerBound
        let zero = span > 0 ? scale.domain.upperBound / span : 1   // 0 = top of the plot, 1 = bottom
        let stops = [Gradient.Stop(color: c.opacity(strong), location: 0), Gradient.Stop(color: c.opacity(weak), location: 1)]
        return below
            ? LinearGradient(stops: stops, startPoint: .bottom, endPoint: UnitPoint(x: 0.5, y: zero))
            : LinearGradient(stops: stops, startPoint: .top, endPoint: UnitPoint(x: 0.5, y: zero))
    }

    private func yScale(_ pts: [FlowPoint]) -> EnergyScale {
        if comp == .all {
            return EnergyScale(lo: -(pts.map { $0.flow.exp * $0.k }.max() ?? 0),
                               hi: pts.map { max($0.flow.house + $0.flow.car, $0.flow.solar + $0.flow.imp) * $0.k }.max() ?? 0)
        }
        var hi = 0.0, lo = 0.0
        for p in pts {
            let vs = parts(p).map(\.2)
            hi = max(hi, vs.filter { $0 > 0 }.reduce(0, +))
            lo = min(lo, vs.filter { $0 < 0 }.reduce(0, +))
        }
        return EnergyScale(lo: lo, hi: hi)
    }

    // MARK: Chart

    private func chart(_ pts: [FlowPoint], _ scale: EnergyScale) -> some View {
        let template = parts(FlowPoint(date: Date(), flow: EnergyFlow(), k: 1))
        return Chart {
            // Longer periods: the held bar's line sits behind the bars (Tesla app).
            if !isDay, let sel = selection, let hit = hitPoint(sel, pts) {
                RuleMark(x: .value("Selected", hit.date, unit: unit))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
            if comp == .all {
                allMarks(pts, scale)
            } else if isDay {
                // Tesla app: each colour fades from strong at its line to 10% at the 0 line, with a solid edge on top.
                ForEach(Array(template.enumerated()), id: \.offset) { i, t in
                    ForEach(pts) { p in
                        let b = bounds(p, i)
                        AreaMark(x: .value("Time", p.date), yStart: .value("Lo", b.lo), yEnd: .value("Hi", b.hi), series: .value("Area", t.0))
                            .foregroundStyle(fade(look.style(t.0, t.1).fill ? t.1 : .clear, below: negative(i), scale))
                            .interpolationMethod(.monotone)
                    }
                }
                // Edge lines from the top layer down, so a lower layer's line wins where they meet
                // (a 0 kW layer never paints over the one beneath it).
                ForEach(Array(template.enumerated()).reversed(), id: \.offset) { i, t in
                    ForEach(Self.runs(pts, has: { (!look.outline || t.0 == look.focus) && abs(parts($0)[i].2) > 0.001 },
                                      edge: { let b = bounds($0, i); return negative(i) ? b.lo : b.hi })) { run in
                        ForEach(run.points, id: \.0) { q in
                            LineMark(x: .value("Time", q.0), y: .value("Edge", q.1), series: .value("Line", "\(t.0)\(run.id)"))
                                .foregroundStyle(look.style(t.0, t.1).line)
                                .lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                                .interpolationMethod(.monotone)
                        }
                    }
                }
            } else {
                barMarks(barSegments(pts, scale))
            }
            if isDay && look.outline {
                // Eye: one blue line along the top of what's used (and one along the bottom of export).
                ForEach(totalLines(pts)) { line in
                    ForEach(line.points, id: \.0) { q in
                        LineMark(x: .value("Time", q.0), y: .value("Edge", q.1), series: .value("T", line.key))
                            .foregroundStyle(EnergyColor.focus)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                            .interpolationMethod(.monotone)
                    }
                }
            }
            if let sel = selection, let hit = hitPoint(sel, pts) {
                if isDay {
                    RuleMark(x: .value("Selected", hit.date))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .annotation(position: .top, alignment: .center, spacing: 6,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            readingBox(hit)
                        }
                }
                if isDay {
                    ForEach(dots(hit), id: \.0) { d in
                        PointMark(x: .value("Time", hit.date), y: .value("V", d.1))
                            .symbol {
                                Circle().fill(d.2).frame(width: 9, height: 9)
                                    .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                            }
                    }
                }
            }
        }
        .chartForegroundStyleScale(domain: template.map(\.0), range: template.map(\.1))
        .chartLegend(.hidden)
        .chartXScale(domain: range.start...xEnd(pts))
        .chartXAxis { xAxis(pts) }
        .chartYScale(domain: scale.domain)
        .chartYAxis(.hidden)   // the scale is drawn inside the graph instead (Tesla app), so the graph runs edge to edge
        .chartBackground { proxy in
            GeometryReader { g in
                Canvas { ctx, size in drawScale(proxy, g, scale, &ctx, size, lines: true) }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { g in
                ZStack {
                    Canvas { ctx, size in drawScale(proxy, g, scale, &ctx, size, lines: false) }
                        .allowsHitTesting(false)
                    Rectangle().fill(Color.clear).contentShape(Rectangle())
                        .simultaneousGesture(gestures(proxy, g))
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if comp == .grid || comp == .all {
                VStack {
                    Text("Import")
                    Spacer()
                    // Only when the graph goes below zero.
                    if scale.domain.lowerBound < 0 { Text("Export") }
                }
                .font(.app(size: 10)).foregroundStyle(TeslaDark.dim)
                .chartLabelGlow()
                .padding(.vertical, 4).padding(.leading, 6)
                .padding(.bottom, 22)
                .allowsHitTesting(false)
            }
        }
        .overlay {
            if pts.isEmpty && !store.loading {
                Text(isDay ? "No data for this date" : "No data for this period").font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
            }
        }
    }

    /// The kW / kWh scale inside the graph, at the right edge (Tesla app): each number sits at the end of its
    /// line (the line stops just short of it); the top one just under the top line, the bottom one just above
    /// the bottom line. Lines behind the graph, numbers over it.
    private func drawScale(_ proxy: ChartProxy, _ g: GeometryProxy, _ scale: EnergyScale,
                           _ ctx: inout GraphicsContext, _ size: CGSize, lines: Bool) {
        guard let anchor = proxy.plotFrame else { return }
        let plot = g[anchor]
        let unitName = isDay ? "kW" : "kWh"
        // Day: 6 AM, 12 PM, 6 PM centred under their dotted lines.
        if isDay && !lines {
            for h in [6, 12, 18] {
                let d = range.start.addingTimeInterval(Double(h) * 3600)
                guard let px = proxy.position(forX: d) else { continue }
                let t = ctx.resolve(Text(Self.hourLabel(d)).font(.app(size: 11)).foregroundColor(TeslaDark.rowLabel))
                ctx.draw(t, at: CGPoint(x: plot.minX + px, y: plot.maxY + 6), anchor: .top)
            }
        }
        // Bars: day / month labels centred under their own bars.
        if !isDay && !lines {
            for (d, label) in barLabels() {
                guard let px = proxy.position(forX: d) else { continue }
                let t = ctx.resolve(Text(label).font(.app(size: 11)).foregroundColor(TeslaDark.rowLabel))
                ctx.draw(t, at: CGPoint(x: plot.minX + px, y: plot.maxY + 6), anchor: .top)
            }
        }
        // Every line runs to the edge; its number sits just under it at the right. The bottom line has none.
        var v = scale.domain.lowerBound
        while v <= scale.domain.upperBound + 0.0001 {
            defer { v += scale.step }
            guard let py = proxy.position(forY: v) else { continue }
            let y = plot.minY + py
            let isTop = abs(v - scale.domain.upperBound) < 0.0001
            let isBottom = abs(v - scale.domain.lowerBound) < 0.0001
            if lines {
                var p = Path()
                p.move(to: CGPoint(x: plot.minX, y: y))
                p.addLine(to: CGPoint(x: plot.maxX, y: y))
                if abs(v) < 0.0001 && scale.domain.lowerBound < 0 {
                    // The 0 line between import and export: dotted, in the gap between the bars (Tesla app).
                    ctx.stroke(p, with: .color(Color.white.opacity(0.25)), style: StrokeStyle(lineWidth: 0.7, dash: [5, 4]))
                } else {
                    ctx.stroke(p, with: .color(Color.white.opacity(0.09)), lineWidth: 0.7)
                }
            } else if !isBottom {
                let text = ctx.resolve(Text(scale.label(v, top: isTop, unit: unitName))
                    .font(.app(size: 10.5)).foregroundColor(TeslaDark.rowLabel))
                ctx.drawGlowing(text, at: CGPoint(x: plot.maxX - 4, y: y + 2), anchor: .topTrailing)
            }
        }
    }

    /// Where each bar's label goes (the middle of its day or month) and what it says.
    private func barLabels() -> [(Date, String)] {
        var out: [(Date, String)] = []
        var d = range.start
        var i = 0
        let end = range.end
        while d < end {
            guard let next = cal.date(byAdding: unit, value: 1, to: d) else { break }
            let mid = d.addingTimeInterval(next.timeIntervalSince(d) / 2)
            switch period {
            case .week:
                out.append((mid, d.formatted(.dateTime.weekday(.narrow))))
            case .month:
                let day = cal.component(.day, from: d)
                if [1, 8, 15, 22, 29].contains(day) { out.append((mid, "\(day)")) }
            case .year:
                out.append((mid, d.formatted(.dateTime.month(.narrow))))
            case .lifetime:
                let months = cal.dateComponents([.month], from: range.start, to: end).month ?? 0
                let every = months > 24 ? 6 : (months > 12 ? 3 : 1)
                if i % every == 0 { out.append((mid, d.formatted(months > 12 ? .dateTime.month(.abbreviated).year(.twoDigits) : .dateTime.month(.narrow)))) }
            case .custom:
                // Up to a week: every day; longer: every 7th day from the start.
                let n = cal.dateComponents([.day], from: range.start, to: end).day ?? 0
                if n <= 7 || i % 7 == 0 { out.append((mid, "\(cal.component(.day, from: d))")) }
            case .day:
                break
            }
            d = next
            i += 1
        }
        return out
    }

    /// Tap and hold (then move) reads values; otherwise a sideways swipe turns the page.
    private func gestures(_ proxy: ChartProxy, _ g: GeometryProxy) -> some Gesture {
        let hold = LongPressGesture(minimumDuration: 0.25, maximumDistance: 12)
            .sequenced(before: DragGesture(minimumDistance: 0))
        let flick = DragGesture(minimumDistance: 18)
        return hold.exclusively(before: flick)
            .onChanged { v in
                if canHold, case .first(let s) = v, case .second(true, let d?) = s {
                    let x = d.location.x - (proxy.plotFrame.map { g[$0].minX } ?? 0)
                    if let raw = proxy.value(atX: x, as: Date.self), let hit = hitPoint(raw, points) {
                        if selection != hit.date { selection = hit.date }
                    }
                }
            }
            .onEnded { v in
                switch v {
                case .first:
                    selection = nil
                case .second(let d):
                    let w = d.translation.width, h = d.translation.height
                    guard abs(w) > 50, abs(w) > abs(h) * 1.4 else { return }
                    swipe(w < 0 ? 1 : -1)   // finger to the left: the next (later) period
                }
            }
    }

    @AxisContentBuilder private func xAxis(_ pts: [FlowPoint]) -> some AxisContent {
        if isDay {
            AxisMarks(values: [6, 12, 18].map { range.start.addingTimeInterval(Double($0) * 3600) }) { v in
                let d = v.as(Date.self) ?? Date()
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    .foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel {   // keeps the room; the visible label is drawn centred under its line (drawScale)
                    Text(Self.hourLabel(d)).font(.app(size: 11)).foregroundStyle(Color.clear)
                }
            }
        } else {
            AxisMarks(values: .stride(by: unit, count: axisCount(pts.count))) { _ in
                AxisValueLabel {   // keeps the room; the visible labels are drawn under their own bars (drawScale)
                    Text("0").font(.app(size: 11)).foregroundStyle(Color.clear)
                }
            }
        }
    }

    /// "12 AM", "6 AM", "12 PM", "6 PM" whatever the phone's region.
    static func hourLabel(_ d: Date) -> String {
        let h = Calendar.current.component(.hour, from: d)
        let h12 = h % 12 == 0 ? 12 : h % 12
        return "\(h12) \(h < 12 ? "AM" : "PM")"
    }

    private func axisCount(_ n: Int) -> Int {
        switch period {
        case .month, .custom: return n > 7 ? 7 : 1
        case .lifetime: return n > 12 ? 3 : 1
        default: return 1
        }
    }

    private var axisFormat: Date.FormatStyle {
        switch period {
        case .week: return .dateTime.weekday(.narrow)
        case .month: return .dateTime.day()
        default: return .dateTime.month(.narrow)
        }
    }

    /// All: Model 3 sits on Home (red top = everything used), grid sits on Solar (grey top = everything supplied),
    /// export below zero.
    /// All: Home (blue) with Model 3 (red) stacked on it = everything used; solar as a yellow line with a light
    /// fill; export below zero in grey. Each fades toward the 0 line, edges only where there's power.
    @ChartContentBuilder private func allMarks(_ points: [FlowPoint], _ scale: EnergyScale) -> some ChartContent {
        if isDay {
            ForEach(points) { p in
                AreaMark(x: .value("Time", p.date), yStart: .value("Lo", 0.0), yEnd: .value("Hi", p.flow.house * p.k), series: .value("A", "home"))
                    .foregroundStyle(fade(look.style("home", EnergyColor.home).fill ? EnergyColor.home : .clear, below: false, scale)).interpolationMethod(.monotone)
            }
            ForEach(points) { p in
                AreaMark(x: .value("Time", p.date), yStart: .value("Lo", p.flow.house * p.k), yEnd: .value("Hi", (p.flow.house + p.flow.car) * p.k), series: .value("A", "car"))
                    .foregroundStyle(fade(look.style("car", EnergyColor.vehicle).fill ? EnergyColor.vehicle : .clear, below: false, scale)).interpolationMethod(.monotone)
            }
            ForEach(points) { p in
                AreaMark(x: .value("Time", p.date), yStart: .value("Lo", 0.0), yEnd: .value("Hi", p.flow.solar * p.k), series: .value("A", "solar"))
                    .foregroundStyle(fade(look.style("solar", EnergyColor.solar).fill ? EnergyColor.solar : .clear, below: false, scale, strong: 0.45, weak: 0.08)).interpolationMethod(.monotone)
            }
            ForEach(points) { p in
                AreaMark(x: .value("Time", p.date), yStart: .value("Lo", 0.0), yEnd: .value("Hi", -p.flow.exp * p.k), series: .value("A", "export"))
                    .foregroundStyle(fade(look.style("export", EnergyColor.grid).fill ? EnergyColor.grid : .clear, below: true, scale)).interpolationMethod(.monotone)
            }
            ForEach(allLines(points)) { line in
                ForEach(line.points, id: \.0) { q in
                    LineMark(x: .value("Time", q.0), y: .value("Edge", q.1), series: .value("L", line.key))
                        .foregroundStyle(line.color)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
            }
        } else {
            barMarks(barSegments(points, scale))
        }
    }

    /// One coloured piece of a bar, placed by hand (so it can also be drawn as an outline).
    struct BarSeg: Identifiable {
        let id: String
        let x0: Date, x1: Date
        let lo: Double, hi: Double
        let color: Color
        let fill: Bool
        let alpha: Double
    }

    /// Bars for Week / Month / Year: each view's parts stacked; All puts used (home + car) beside supplied
    /// (solar + grid), export below zero.
    private func barSegments(_ pts: [FlowPoint], _ scale: EnergyScale) -> [BarSeg] {
        var out: [BarSeg] = []
        for p in pts {
            let next = cal.date(byAdding: unit, value: 1, to: p.date) ?? p.date.addingTimeInterval(86400)
            let len = next.timeIntervalSince(p.date)
            func at(_ r: Double) -> Date { p.date.addingTimeInterval(len * r) }
            let a = dim(p)
            func add(_ key: String, _ c: Color, _ b: (lo: Double, hi: Double), _ from: Double, _ to: Double, _ shade: Double = 1) {
                if look.outline && look.focus != key { return }   // eye: the total outline stands in for the rest
                guard let g = gapped(b, scale) else { return }
                let st = look.style(key, c)
                out.append(BarSeg(id: "\(p.id)\(key)", x0: at(from), x1: at(to), lo: g.lo, hi: g.hi,
                                  color: st.fill ? c.opacity(shade) : st.line, fill: st.fill, alpha: a))
            }
            if comp == .all {
                let f = p.flow
                add("home", EnergyColor.home, (0, f.house), 0.14, 0.49, 0.9)
                add("car", EnergyColor.vehicle, (f.house, f.house + f.car), 0.14, 0.49, 0.9)
                add("solar", EnergyColor.solar, (0, f.solar), 0.51, 0.86, 0.9)
                add("imp", EnergyColor.grid, (f.solar, f.solar + f.imp), 0.51, 0.86, 0.9)
                add("export", EnergyColor.grid, (-f.exp, 0), 0.51, 0.86, 0.5)
            } else if comp == .home || comp == .vehicle {
                // Grid at the bottom, solar on top.
                let ps = parts(p), s = max(ps[0].2, 0), g = max(ps[1].2, 0)
                add(ps[1].0, ps[1].1, (0, g), 0.2, 0.8)
                add(ps[0].0, ps[0].1, (g, g + s), 0.2, 0.8)
            } else {
                for (i, part) in parts(p).enumerated() { add(part.0, part.1, bounds(p, i), 0.2, 0.8) }
            }
            if look.outline {
                // Eye: one outline per bar for what's used, and one for export below 0.
                let (u0, u1) = comp == .all ? (0.14, 0.49) : (0.2, 0.8)
                let (e0, e1) = comp == .all ? (0.51, 0.86) : (0.2, 0.8)
                if let g = gapped((0, usedTop(p)), scale) {
                    out.append(BarSeg(id: "\(p.id)top", x0: at(u0), x1: at(u1), lo: g.lo, hi: g.hi, color: EnergyColor.focus, fill: false, alpha: a))
                }
                if let g = gapped((belowZero(p), 0), scale) {
                    out.append(BarSeg(id: "\(p.id)bottom", x0: at(e0), x1: at(e1), lo: g.lo, hi: g.hi, color: EnergyColor.focus, fill: false, alpha: a))
                }
            }
        }
        return out
    }

    /// Filled bars, or a 1 pt outline when the layer is filtered out.
    @ChartContentBuilder private func barMarks(_ segs: [BarSeg]) -> some ChartContent {
        ForEach(segs.filter(\.fill)) { s in
            RectangleMark(xStart: .value("A", s.x0), xEnd: .value("B", s.x1), yStart: .value("Lo", s.lo), yEnd: .value("Hi", s.hi))
                .cornerRadius(1.5)
                .foregroundStyle(s.color)
                .opacity(s.alpha)
        }
        ForEach(segs.filter { !$0.fill }) { s in
            RuleMark(xStart: .value("A", s.x0), xEnd: .value("B", s.x1), y: .value("Hi", s.hi))
                .foregroundStyle(s.color).lineStyle(StrokeStyle(lineWidth: 1)).opacity(s.alpha)
            RuleMark(xStart: .value("A", s.x0), xEnd: .value("B", s.x1), y: .value("Lo", s.lo))
                .foregroundStyle(s.color).lineStyle(StrokeStyle(lineWidth: 1)).opacity(s.alpha)
            RuleMark(x: .value("A", s.x0), yStart: .value("Lo", s.lo), yEnd: .value("Hi", s.hi))
                .foregroundStyle(s.color).lineStyle(StrokeStyle(lineWidth: 1)).opacity(s.alpha)
            RuleMark(x: .value("B", s.x1), yStart: .value("Lo", s.lo), yEnd: .value("Hi", s.hi))
                .foregroundStyle(s.color).lineStyle(StrokeStyle(lineWidth: 1)).opacity(s.alpha)
        }
    }

    /// Eye: what's used at each moment (All: home + car; other views: their parts stacked above 0), and export below 0.
    private func usedTop(_ p: FlowPoint) -> Double {
        if comp == .all { return (p.flow.house + p.flow.car) * p.k }
        return parts(p).map(\.2).filter { $0 > 0 }.reduce(0, +)
    }
    private func belowZero(_ p: FlowPoint) -> Double {
        if comp == .all { return -p.flow.exp * p.k }
        return parts(p).map(\.2).filter { $0 < 0 }.reduce(0, +)
    }

    private func totalLines(_ pts: [FlowPoint]) -> [EdgeLine] {
        Self.runs(pts, has: { usedTop($0) > 0.001 }, edge: { usedTop($0) }).map {
            EdgeLine(key: "top\($0.id)", color: EnergyColor.focus, points: $0.points)
        } + Self.runs(pts, has: { belowZero($0) < -0.001 }, edge: { belowZero($0) }).map {
            EdgeLine(key: "bottom\($0.id)", color: EnergyColor.focus, points: $0.points)
        }
    }

    struct EdgeLine: Identifiable { let key: String; let color: Color; let points: [(Date, Double)]; var id: String { key } }

    /// All view edge lines (drawn top layer first): car, solar, export, then home on top.
    private func allLines(_ pts: [FlowPoint]) -> [EdgeLine] {
        var out: [EdgeLine] = []
        func add(_ name: String, _ c: Color, has: @escaping (FlowPoint) -> Bool, edge: @escaping (FlowPoint) -> Double) {
            if look.outline && look.focus != name { return }   // eye: only the total lines (and a tapped row's own line)
            for r in Self.runs(pts, has: has, edge: edge) { out.append(EdgeLine(key: "\(name)\(r.id)", color: c, points: r.points)) }
        }
        add("car", look.style("car", EnergyColor.vehicle).line, has: { $0.flow.car > 0.001 }, edge: { ($0.flow.house + $0.flow.car) * $0.k })
        add("solar", look.style("solar", EnergyColor.solar).line, has: { $0.flow.solar > 0.001 }, edge: { $0.flow.solar * $0.k })
        add("export", look.style("export", EnergyColor.grid).line, has: { $0.flow.exp > 0.001 }, edge: { -$0.flow.exp * $0.k })
        add("home", look.style("home", EnergyColor.home).line, has: { $0.flow.house > 0.001 }, edge: { $0.flow.house * $0.k })
        return out
    }

    // MARK: Reading the graph (tap and hold)

    /// A bar segment pulled in (Tesla app): a thin gap under each colour stacked on another, and a gap either side
    /// of the 0 line. A tiny segment still shows as a sliver.
    private func gapped(_ b: (lo: Double, hi: Double), _ scale: EnergyScale) -> (lo: Double, hi: Double)? {
        guard b.hi - b.lo > 0.0001 else { return nil }
        let pt = (scale.domain.upperBound - scale.domain.lowerBound) / 248   // one point in kWh
        var lo = b.lo, hi = b.hi
        if hi <= 0 { hi -= 2 * pt }                       // below zero: 2 pt gap under the 0 line
        else { lo += (lo <= 0.0001 ? 2 : 0.75) * pt }     // above zero: 2 pt over 0, or a thin gap on a colour beneath
        if hi - lo < pt { if b.hi <= 0 { lo = hi - pt } else { hi = lo + pt } }
        return (lo, hi)
    }

    /// While a bar is read, the others dim.
    private func dim(_ p: FlowPoint) -> Double {
        guard let sel = selection else { return 1 }
        return cal.isDate(p.date, equalTo: sel, toGranularity: unit) ? 1 : 0.35
    }

    private func hitPoint(_ d: Date, _ pts: [FlowPoint]) -> FlowPoint? {
        if isDay { return pts.min { abs($0.date.timeIntervalSince(d)) < abs($1.date.timeIntervalSince(d)) } }
        return pts.first { cal.isDate($0.date, equalTo: d, toGranularity: unit) }
    }

    /// A dot on each line that has power at that moment, in its colour.
    private func dots(_ p: FlowPoint) -> [(String, Double, Color)] {
        if comp == .all {
            let f = p.flow, k = p.k
            var out: [(String, Double, Color)] = []
            if f.solar > 0.001 { out.append(("solar", f.solar * k, EnergyColor.solar)) }
            if f.house > 0.001 { out.append(("home", f.house * k, EnergyColor.home)) }
            if f.car > 0 { out.append(("used", (f.house + f.car) * k, EnergyColor.vehicle)) }
            if f.exp > 0 { out.append(("export", -f.exp * k, EnergyColor.grid)) }
            return out
        }
        let template = parts(p)
        return template.indices.compactMap { i in
            let v = template[i].2
            guard abs(v) > 0.001 else { return nil }
            let b = bounds(p, i)
            return (template[i].0, negative(i) ? b.lo : b.hi, template[i].1)
        }
    }

    /// Day view's box (Tesla app): a summary line, then each source / destination as icon over value, then the unit.
    private func readingBox(_ p: FlowPoint) -> some View {
        let u = isDay ? "kW" : "kWh"
        let gs = EnergyReading.groups(comp, p.flow, p.k, unit: u, gridBoth: false)
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(gs.indices, id: \.self) { EnergyReadingView(group: gs[$0], unit: u) }
        }
        .fixedSize(horizontal: true, vertical: true)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(white: 0.21)))
    }
}

/// What a reading shows: per group an arrow + summary line and the icons with their values.
enum EnergyReading {
    struct Item {
        let kind: FlowGlyph.Kind; let color: Color; let value: Double; var whole = false
        var text: String { EnergyReading.n(value, whole: whole) }
    }
    struct Group { let arrow: String?; let summary: String; let items: [Item] }

    /// One decimal, or none for Year / Lifetime; commas for thousands; a real minus sign.
    static func n(_ v: Double, whole: Bool = false) -> String {
        let s = whole ? Num.whole(v) : Num.one(v)
        return (s == "-0.0" || s == "-0") ? String(s.dropFirst()) : s.replacingOccurrences(of: "-", with: "−")
    }
    static func isZero(_ s: String) -> Bool { s == "0.0" || s == "0" }

    /// gridBoth: Grid shows Imported and Exported side by side (longer periods); otherwise whichever is bigger.
    static func groups(_ comp: EnergyComponent, _ f: EnergyFlow, _ k: Double, unit u: String, gridBoth: Bool,
                       whole: Bool = false) -> [Group] {
        func n(_ v: Double) -> String { EnergyReading.n(v, whole: whole) }
        func Item(kind: FlowGlyph.Kind, color: Color, value: Double) -> EnergyReading.Item {
            EnergyReading.Item(kind: kind, color: color, value: value, whole: whole)
        }
        let imp = Group(arrow: "arrow.up", summary: "\(n(f.imp * k)) \(u) Imported",
                        items: [Item(kind: .home, color: EnergyColor.home, value: f.homeGrid * k),
                                Item(kind: .car, color: EnergyColor.vehicle, value: f.carGrid * k)])
        let exp = Group(arrow: "arrow.down", summary: "\(n(f.exp * k)) \(u) Exported",
                        items: [Item(kind: .solar, color: EnergyColor.solar, value: f.exp * k)])
        switch comp {
        case .grid:
            if gridBoth { return [imp, exp] }
            return [f.exp > f.imp ? exp : imp]
        case .home:
            return [Group(arrow: nil, summary: "\(n(f.house * k)) \(u) Used",
                          items: [Item(kind: .solar, color: EnergyColor.solar, value: f.homeSolar * k),
                                  Item(kind: .grid, color: EnergyColor.grid, value: f.homeGrid * k)])]
        case .vehicle:
            return [Group(arrow: nil, summary: "\(n(f.car * k)) \(u) Charging",
                          items: [Item(kind: .solar, color: EnergyColor.solar, value: f.carSolar * k),
                                  Item(kind: .grid, color: EnergyColor.grid, value: f.carGrid * k)])]
        case .solar:
            return [Group(arrow: nil, summary: "\(n(f.solar * k)) \(u) Generated",
                          items: [Item(kind: .home, color: EnergyColor.home, value: f.homeSolar * k),
                                  Item(kind: .car, color: EnergyColor.vehicle, value: f.carSolar * k),
                                  Item(kind: .grid, color: EnergyColor.grid, value: f.exp * k)])]
        case .all:
            return [Group(arrow: nil, summary: "\(n((f.house + f.car) * k)) \(u) Used",
                          items: [Item(kind: .solar, color: EnergyColor.solar, value: f.solar * k),
                                  Item(kind: .home, color: EnergyColor.home, value: f.house * k),
                                  Item(kind: .car, color: EnergyColor.vehicle, value: f.car * k),
                                  Item(kind: .grid, color: EnergyColor.grid, value: (f.imp - f.exp) * k)])]
        }
    }
}

/// Summary line over icons with values; a 0.0 value is grey, the rest white (Tesla app).
struct EnergyReadingView: View {
    let group: EnergyReading.Group
    let unit: String
    var large = false

    var body: some View {
        VStack(alignment: .leading, spacing: large ? 6 : 7) {
            HStack(spacing: 4) {
                if let a = group.arrow { Image(systemName: a).font(.system(size: 10, weight: .medium)) }
                Text(group.summary).font(.app(size: large ? 11.5 : 12))
            }
            .foregroundStyle(TeslaDark.rowLabel)
            HStack(alignment: .bottom, spacing: 14) {
                ForEach(Array(group.items.enumerated()), id: \.offset) { _, it in
                    let v = it.text
                    VStack(spacing: 4) {
                        FlowGlyph(kind: it.kind, color: it.color, height: large ? 15 : 14, maxWidth: 18)
                            .frame(height: 15)
                        // Header: the figures match the summary line's size (Tesla app).
                        Text(v).font(.app(size: large ? 11.5 : 12.5, weight: .semibold).monospacedDigit())
                            .foregroundStyle(EnergyReading.isZero(v) ? TeslaDark.rowLabel : Color.white)
                            .fixedSize()
                    }
                    .frame(minWidth: 28)
                }
                Text(unit).font(.app(size: large ? 11.5 : 12)).foregroundStyle(TeslaDark.rowLabel).fixedSize()
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)   // never "Cha…" or "k…"
    }
}

/// Chart figures that sit over bars and areas: a soft glow in the page background colour round the grey text.
extension GraphicsContext {
    func drawGlowing(_ text: GraphicsContext.ResolvedText, at point: CGPoint, anchor: UnitPoint) {
        var tight = self
        tight.addFilter(.shadow(color: TeslaDark.bg, radius: 1.5))
        var soft = self
        soft.addFilter(.shadow(color: TeslaDark.bg, radius: 3))
        // Each pass builds the glow up; one shadow alone is too faint over a grey bar.
        for _ in 0..<2 { soft.draw(text, at: point, anchor: anchor) }
        for _ in 0..<3 { tight.draw(text, at: point, anchor: anchor) }
        draw(text, at: point, anchor: anchor)
    }
}

extension View {
    func chartLabelGlow() -> some View {
        shadow(color: TeslaDark.bg, radius: 1.5).shadow(color: TeslaDark.bg, radius: 1.5).shadow(color: TeslaDark.bg, radius: 3)
    }
}

/// Clips left, right and bottom only: the reading box can rise above the graph into the header.
struct OpenTopClip: Shape {
    func path(in r: CGRect) -> Path { Path(CGRect(x: r.minX, y: r.minY - 200, width: r.width, height: r.height + 200)) }
}

/// Y range fitted to what's on screen: neat steps, 4–5 gridlines; negatives (export) below zero.
struct EnergyScale {
    let domain: ClosedRange<Double>
    let step: Double

    init(lo: Double, hi: Double) {
        let low = min(lo, 0), high = max(hi, 0)
        let span = max(high - low, 0.5)
        let steps: [Double] = [0.5, 1, 2, 2.5, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000, 2000, 2500, 5000, 10000]
        let st = steps.first { span / $0 <= 4.5 } ?? 10000
        let top = max(st, (high / st).rounded(.up) * st)
        let bottom = low < -0.001 ? (low / st).rounded(.down) * st : 0
        domain = bottom...top
        step = st
    }

    /// Tesla app: the unit only on the top line ("8 kW"), negatives shown without the minus ("4" below zero).
    func label(_ v: Double, top: Bool, unit: String) -> String {
        let big = unit == "kWh" && max(abs(domain.lowerBound), abs(domain.upperBound)) > 1000
        let x = abs(big ? v / 1000 : v)
        let n = abs(x - x.rounded()) < 0.001 ? Num.whole(x) : String(format: "%.1f", x)
        return top ? "\(n) \(big ? "MWh" : unit)" : n
    }
}

// MARK: - Floating component bar (Tesla app)

struct EnergyTabBar: View {
    @Binding var selected: EnergyComponent
    private static let width: CGFloat = 255
    private static let height: CGFloat = 46

    var body: some View {
        ZStack(alignment: .topLeading) {
            Capsule()
                .fill(Color(red: 66 / 255, green: 66 / 255, blue: 69 / 255))
                .shadow(color: .black.opacity(0.45), radius: 10, y: 3)
            ForEach(Array(EnergyComponent.barOrder.enumerated()), id: \.offset) { i, c in
                let x = Self.width * (0.127 + CGFloat(i) * 0.1865)
                let on = c == selected
                Button { selected = c } label: {
                    FlowGlyph(kind: c.glyph, color: on ? Color(white: 0.96) : Color(white: 0.59), height: 13.5, maxWidth: 16.5)
                        .frame(width: 46, height: Self.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .position(x: x, y: Self.height / 2)
                .accessibilityLabel(c.pageTitle)
                if on {
                    Circle().fill(c.color).frame(width: 4, height: 4)
                        .position(x: x, y: Self.height - 8)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(width: Self.width, height: Self.height)
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}

/// Small key under the All chart: mini drawings in the chart's own colours.
private struct ChartKey: View {
    let day: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                item(day ? "Red line" : "Left bar", day ? "Everything used" : "Used: Home + Model 3") {
                    day ? AnyView(area(top: EnergyColor.vehicle, upper: EnergyColor.vehicle, lower: EnergyColor.home))
                        : AnyView(stack(EnergyColor.home, EnergyColor.vehicle))
                }
                item(day ? "Grey line" : "Right bar", day ? "Everything supplied" : "Supplied: Solar + Grid") {
                    day ? AnyView(area(top: EnergyColor.grid, upper: EnergyColor.grid, lower: EnergyColor.solar))
                        : AnyView(stack(EnergyColor.solar, EnergyColor.grid))
                }
                item("Below 0", "Solar sent to TNB") { AnyView(below) }
            }
            if day {
                Text("Model 3 sits on top of Home; Grid sits on top of Solar.")
                    .font(.app(size: 10)).foregroundStyle(Color(white: 0.4))
            }
        }
    }

    private func item(_ t: String, _ sub: String, _ icon: () -> AnyView) -> some View {
        HStack(alignment: .center, spacing: 8) {
            icon().frame(width: 16, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(t).font(.app(size: 11, weight: .semibold)).foregroundStyle(TeslaDark.labelGrey)
                Text(sub).font(.app(size: 9.5)).foregroundStyle(TeslaDark.rowLabel).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stack(_ bottom: Color, _ top: Color) -> some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5).fill(top).frame(width: 8, height: 10)
            RoundedRectangle(cornerRadius: 1.5).fill(bottom).frame(width: 8, height: 14)
        }
        .frame(width: 16, height: 26, alignment: .bottom)
    }

    private func area(top: Color, upper: Color, lower: Color) -> some View {
        Canvas { ctx, sz in
            func wave(_ y: CGFloat, _ a: CGFloat, _ ph: CGFloat) -> Path {
                var p = Path(); p.move(to: CGPoint(x: 0, y: sz.height))
                for i in stride(from: 0, through: sz.width, by: 1) { p.addLine(to: CGPoint(x: i, y: y + a * sin(i / 3 + ph))) }
                p.addLine(to: CGPoint(x: sz.width, y: sz.height)); p.closeSubpath(); return p
            }
            ctx.fill(wave(sz.height * 0.35, 2, 0), with: .color(upper.opacity(0.4)))
            ctx.fill(wave(sz.height * 0.65, 1.5, 1), with: .color(lower.opacity(0.45)))
            var line = Path()
            for i in stride(from: 0, through: sz.width, by: 1) {
                let pt = CGPoint(x: i, y: sz.height * 0.35 + 2 * sin(i / 3))
                if i == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
            }
            ctx.stroke(line, with: .color(top), lineWidth: 1.5)
        }
    }

    private var below: some View {
        VStack(spacing: 1) {
            Rectangle().fill(Color(white: 0.35)).frame(width: 16, height: 1)
            RoundedRectangle(cornerRadius: 1.5).fill(EnergyColor.gridOut).frame(width: 8, height: 12)
        }
        .frame(width: 16, height: 26, alignment: .center)
    }
}
