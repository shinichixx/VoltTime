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
}

struct EnergyPart: Identifiable {
    let name: String
    let color: Color
    let kwh: Double
    var glyph: FlowGlyph.Kind = .grid
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
    /// The middle of what the graph shows (reported by the graph as you swipe).
    @State private var focus = Date()

    init(store: EnergyStore, start: EnergyComponent = .all) {
        _store = ObservedObject(wrappedValue: store)
        _compRaw = State(initialValue: start.rawValue)
    }

    private let cal = Calendar.current
    private var period: ImpactPeriod { ImpactPeriod(rawValue: periodRaw) ?? .day }
    private var comp: EnergyComponent { EnergyComponent(rawValue: compRaw) ?? .all }

    /// The day / week / month / year under the middle of the graph.
    private var focusInterval: DateInterval {
        guard let c = period.component else {
            let start = store.firstDay ?? cal.startOfDay(for: Date())
            return DateInterval(start: start, end: cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date())
        }
        return cal.dateInterval(of: c, for: focus) ?? DateInterval(start: cal.startOfDay(for: focus), duration: 86400)
    }

    private var focusLabel: String {
        let i = focusInterval
        switch period {
        case .day:
            if cal.isDateInToday(i.start) { return "Today" }
            if cal.isDateInYesterday(i.start) { return "Yesterday" }
            return i.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        case .week:
            if cal.isDate(i.start, equalTo: Date(), toGranularity: .weekOfYear) { return "This week" }
            let last = i.end.addingTimeInterval(-1)
            return "\(i.start.formatted(.dateTime.day().month(.abbreviated))) – \(last.formatted(.dateTime.day().month(.abbreviated)))"
        case .month: return i.start.formatted(.dateTime.month(.wide).year())
        case .year: return i.start.formatted(.dateTime.year())
        case .lifetime: return "Since " + i.start.formatted(.dateTime.month(.abbreviated).year())
        }
    }

    private var total: EnergyFlow {
        let i = focusInterval
        if period == .day { return store.flow(i.start) ?? EnergyFlow() }
        return store.flowTotal(from: i.start, to: i.end)
    }

    var body: some View {
        let t = total
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(t)
                        .padding(.horizontal, 20)
                    EnergyChartView(store: store, period: period, comp: comp, focus: $focus)
                        .frame(height: comp == .all ? 250 : 270)
                        .padding(.top, 18)
                        .padding(.leading, 6)
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5).padding(.top, 14)
                    Group {
                        if comp == .all {
                            allLegend.padding(.top, 14)
                            allTiles(t).padding(.top, 12)
                            ChartKey(day: period == .day).padding(.top, 16)
                        } else {
                            if comp == .grid {
                                Text(netLine(t)).font(.app(size: 14, weight: .semibold)).padding(.top, 16)
                            }
                            Text("Energy Flow").font(.app(size: 14, weight: .semibold)).padding(.top, 22)
                            flowTables(t)
                        }
                        if let msg = store.message {
                            Text(msg).font(.app(size: 11)).foregroundStyle(TeslaDark.importing).padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, 20)
                    Color.clear.frame(height: 96)   // clear of the floating bar
                }
            }
            .scrollIndicators(.hidden)
            EnergyTabBar(selected: Binding(get: { comp }, set: { compRaw = $0.rawValue }))
                .padding(.bottom, 6)
        }
        .teslaPage(comp.pageTitle)
        .task(id: "\(periodRaw)|\(Int(focusInterval.start.timeIntervalSince1970))") {
            // Saved days show at once; this only tops up today / missing days (at most once a minute).
            await store.refresh()
        }
    }

    // MARK: Header

    private func header(_ t: EnergyFlow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(focusLabel).font(.app(size: 17, weight: .semibold))
                if store.loading { ProgressView().tint(.white).scaleEffect(0.6) }
                Spacer()
                PeriodMenu(periodRaw: $periodRaw, offset: .constant(0), boxed: true)
            }
            .padding(.top, 4)
            switch comp {
            case .all:
                EmptyView()
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
    }

    private func figure(_ title: String, arrow: String?, _ v: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if let arrow { Image(systemName: arrow).font(.system(size: 11, weight: .medium)) }
                Text(title).font(.app(size: 13))
            }
            .foregroundStyle(TeslaDark.rowLabel)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Num.kwh(v)).font(.app(size: 24, weight: .semibold))
                Text("kWh").font(.app(size: 13)).foregroundStyle(TeslaDark.rowLabel)
            }
        }
    }

    private func netLine(_ t: EnergyFlow) -> String {
        let net = t.imp - t.exp
        return "Net Grid Usage: \(Num.kwh(abs(net))) kWh \(net >= 0 ? "Imported" : "Exported")"
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
                EnergyPart(name: "Solar", color: EnergyColor.solar, kwh: t.exp, glyph: .solar)])
        case .all:
            EmptyView()
        }
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
                        Text(sum > 0 ? "\(Int((p.kwh / sum * 100).rounded()))%" : "0%")
                            .font(.app(size: 14, weight: .semibold))
                            .frame(width: 48, alignment: .leading)
                        Text(p.name).font(.app(size: 13.5)).foregroundStyle(TeslaDark.rowLabel)
                        Spacer()
                        Text(Num.kwh(p.kwh) + " kWh").font(.app(size: 13.5))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 44)
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

    private func kwh(_ v: Double) -> String { Num.kwh(v) + " kWh" }

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

// MARK: - The swipeable graph

/// Owns the scroll position, so swiping only redraws the graph; reports the middle of the view back up.
private struct EnergyChartView: View {
    @ObservedObject var store: EnergyStore
    let period: ImpactPeriod
    let comp: EnergyComponent
    @Binding var focus: Date

    @State private var scrollX = Date()           // leading edge of what's on screen
    @State private var points: [FlowPoint] = []
    @State private var builtFor = ""              // what `points` was built for
    @State private var selection: Date?

    private let cal = Calendar.current
    private var isDay: Bool { period == .day }
    private var byMonth: Bool { period == .year || period == .lifetime }
    private var unit: Calendar.Component { byMonth ? .month : .day }

    /// Everything you can swipe through: from the first recorded day to the end of the current period.
    private var domain: ClosedRange<Date> {
        let now = Date()
        let first = store.firstDay ?? cal.startOfDay(for: now)
        let comp = period.component ?? .month
        let lo = cal.dateInterval(of: period == .lifetime ? .month : comp, for: first)?.start ?? first
        let hi = cal.dateInterval(of: period == .lifetime ? .month : comp, for: now)?.end ?? now
        return lo...max(hi, lo.addingTimeInterval(86400))
    }

    /// How much is on screen at once.
    private var visibleLength: TimeInterval {
        switch period {
        case .day: return 86400
        case .week: return 7 * 86400
        case .month: return 31 * 86400
        case .year: return 365 * 86400
        case .lifetime: return domain.upperBound.timeIntervalSince(domain.lowerBound)
        }
    }

    /// Where a period opens: the current day / week / month / year.
    private var homeX: Date {
        guard let c = period.component else { return domain.lowerBound }
        return cal.dateInterval(of: c, for: Date())?.start ?? cal.startOfDay(for: Date())
    }

    private var buildKey: String {
        let centre = scrollX.addingTimeInterval(visibleLength / 2)
        let day = isDay ? Int(cal.startOfDay(for: centre).timeIntervalSince1970) : 0
        return "\(period.rawValue)|\(day)|\(store.loading)|\(store.firstDay?.timeIntervalSince1970 ?? 0)"
    }

    var body: some View {
        let visible = points.filter { $0.date >= scrollX.addingTimeInterval(-3600) && $0.date <= scrollX.addingTimeInterval(visibleLength + 3600) }
        let scale = yScale(visible)
        chart(scale)
            .onAppear {
                scrollX = homeX
                rebuild()
                report()
            }
            .onChange(of: period) { _, _ in
                selection = nil
                scrollX = homeX
                rebuild()
                report()
            }
            .onChange(of: scrollX) { _, _ in
                report()
                if buildKey != builtFor { rebuild() }
            }
            .onChange(of: store.loading) { _, _ in rebuild() }
            .onChange(of: comp) { _, _ in selection = nil }
    }

    private func report() {
        let centre = min(scrollX.addingTimeInterval(visibleLength / 2), Date())
        if period == .lifetime { focus = Date(); return }
        focus = centre
    }

    /// Day: 15-minute points for the days around what's on screen (built again as you swipe on).
    /// Week and Month: a bar per day; Year and Lifetime: a bar per month, across the whole history.
    private func rebuild() {
        builtFor = buildKey
        var out: [FlowPoint] = []
        if isDay {
            let centre = cal.startOfDay(for: scrollX.addingTimeInterval(visibleLength / 2))
            for off in -3...3 {
                guard let day = cal.date(byAdding: .day, value: off, to: centre), day < domain.upperBound,
                      day >= domain.lowerBound, let raw = store.curve(day) else { continue }
                let c = raw.minutes < 15 ? raw.coarsened(to: 15) : raw
                let step = TimeInterval(c.minutes * 60)
                var last = c.count
                if cal.isDateInToday(day) { last = min(c.count, max(0, Int(Date().timeIntervalSince(day) / step))) }
                let k = 60.0 / Double(c.minutes)
                for i in 0..<last {
                    out.append(FlowPoint(date: day.addingTimeInterval(Double(i) * step + step / 2), flow: c.flow(i), k: k))
                }
            }
        } else {
            var d = domain.lowerBound
            let end = min(domain.upperBound, cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date())
            while d < end {
                let next = cal.date(byAdding: unit, value: 1, to: d) ?? end
                out.append(FlowPoint(date: d, flow: store.flowTotal(from: d, to: min(next, end)), k: 1))
                d = next
            }
        }
        points = out
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
            return [("Imported", EnergyColor.grid, f.imp * k), ("Exported", EnergyColor.solar, -f.exp * k)]
        }
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

    private func chart(_ scale: EnergyScale) -> some View {
        let template = parts(FlowPoint(date: Date(), flow: EnergyFlow(), k: 1))
        let names = template.map(\.0)
        let colors = template.map(\.1)
        return Chart {
            if comp == .all {
                allMarks
            } else {
                ForEach(points) { p in
                    ForEach(parts(p), id: \.0) { part in
                        if isDay {
                            AreaMark(x: .value("Time", p.date), y: .value("kW", part.2), stacking: .standard)
                                .foregroundStyle(by: .value("Part", part.0))
                                .interpolationMethod(.monotone)
                                .opacity(0.85)
                        } else {
                            BarMark(x: .value("Date", p.date, unit: unit), y: .value("kWh", part.2), width: .ratio(0.6))
                                .foregroundStyle(by: .value("Part", part.0))
                        }
                    }
                }
            }
            if let sel = selection {
                RuleMark(x: .value("Selected", sel))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, alignment: .center, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        scrub(sel)
                    }
            }
        }
        .chartForegroundStyleScale(domain: names, range: colors)
        .chartLegend(.hidden)
        .chartXScale(domain: domain)
        .chartScrollableAxes(period == .lifetime ? [] : .horizontal)
        .chartXVisibleDomain(length: visibleLength)
        .chartScrollPosition(x: $scrollX)
        .modifier(SnapToPeriod(period: period))
        .chartXSelection(value: $selection)
        .chartXAxis { xAxis }
        .chartYScale(domain: scale.domain)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .stride(by: scale.step)) { v in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                AxisValueLabel {
                    if let d = v.as(Double.self) {
                        Text(scale.label(d, top: abs(d - scale.domain.upperBound) < 0.001, unit: isDay ? "kW" : "kWh"))
                    }
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if comp == .grid {
                VStack {
                    Text("Import")
                    Spacer()
                    Text("Export")
                }
                .font(.app(size: 10)).foregroundStyle(TeslaDark.dim)
                .padding(.vertical, 4).padding(.leading, 6)
                .padding(.bottom, 22)
                .allowsHitTesting(false)
            }
        }
        .overlay {
            if points.isEmpty && !store.loading {
                Text("No data yet").font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
            }
        }
    }

    @AxisContentBuilder private var xAxis: some AxisContent {
        if isDay {
            AxisMarks(values: .stride(by: .hour, count: 6)) { v in
                let d = v.as(Date.self) ?? Date()
                let midnight = cal.component(.hour, from: d) == 0
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    .foregroundStyle(Color.white.opacity(midnight ? 0.25 : 0.1))
                AxisValueLabel {
                    Text(Self.hourLabel(d))
                        .font(.app(size: 11, weight: midnight ? .semibold : .regular))
                        .foregroundStyle(midnight ? Color.white : TeslaDark.rowLabel)
                }
            }
        } else {
            AxisMarks(values: .stride(by: unit, count: axisCount)) { _ in
                AxisValueLabel(format: axisFormat, centered: true)
            }
        }
    }

    /// "12 AM", "6 AM", "12 PM", "6 PM" whatever the phone's region.
    static func hourLabel(_ d: Date) -> String {
        let h = Calendar.current.component(.hour, from: d)
        let h12 = h % 12 == 0 ? 12 : h % 12
        return "\(h12) \(h < 12 ? "AM" : "PM")"
    }

    private var axisCount: Int {
        switch period {
        case .month: return 7
        case .lifetime: return points.count > 12 ? 3 : 1
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
    @ChartContentBuilder private var allMarks: some ChartContent {
        if isDay {
            ForEach(points) { p in
                AreaMark(x: .value("Time", p.date), yStart: .value("Lo", 0.0), yEnd: .value("Hi", p.flow.solar * p.k), series: .value("F", "solar"))
                    .foregroundStyle(EnergyColor.solar.opacity(0.22)).interpolationMethod(.monotone)
            }
            ForEach(points) { p in
                AreaMark(x: .value("Time", p.date), yStart: .value("Lo", p.flow.solar * p.k), yEnd: .value("Hi", (p.flow.solar + p.flow.imp) * p.k), series: .value("F", "import"))
                    .foregroundStyle(EnergyColor.grid.opacity(0.25)).interpolationMethod(.monotone)
            }
            ForEach(points) { p in
                AreaMark(x: .value("Time", p.date), yStart: .value("Lo", 0.0), yEnd: .value("Hi", -p.flow.exp * p.k), series: .value("F", "export"))
                    .foregroundStyle(EnergyColor.grid.opacity(0.3)).interpolationMethod(.monotone)
            }
            ForEach(points) { p in
                AreaMark(x: .value("Time", p.date), yStart: .value("Lo", 0.0), yEnd: .value("Hi", p.flow.house * p.k), series: .value("F", "home"))
                    .foregroundStyle(EnergyColor.home.opacity(0.25)).interpolationMethod(.monotone)
            }
            ForEach(points) { p in
                AreaMark(x: .value("Time", p.date), yStart: .value("Lo", p.flow.house * p.k), yEnd: .value("Hi", (p.flow.house + p.flow.car) * p.k), series: .value("F", "car"))
                    .foregroundStyle(EnergyColor.vehicle.opacity(0.28)).interpolationMethod(.monotone)
            }
            ForEach(points) { p in
                LineMark(x: .value("Time", p.date), y: .value("V", (p.flow.solar + p.flow.imp) * p.k), series: .value("L", "supply"))
                    .foregroundStyle(EnergyColor.grid).lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round)).interpolationMethod(.monotone)
            }
            ForEach(points) { p in
                LineMark(x: .value("Time", p.date), y: .value("V", -p.flow.exp * p.k), series: .value("L", "export"))
                    .foregroundStyle(EnergyColor.grid).lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round)).interpolationMethod(.monotone)
            }
            ForEach(points) { p in
                LineMark(x: .value("Time", p.date), y: .value("V", p.flow.solar * p.k), series: .value("L", "solar"))
                    .foregroundStyle(EnergyColor.solar).lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round)).interpolationMethod(.monotone)
            }
            ForEach(points) { p in
                LineMark(x: .value("Time", p.date), y: .value("V", (p.flow.house + p.flow.car) * p.k), series: .value("L", "used"))
                    .foregroundStyle(EnergyColor.vehicle).lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round)).interpolationMethod(.monotone)
            }
            ForEach(points) { p in
                LineMark(x: .value("Time", p.date), y: .value("V", p.flow.house * p.k), series: .value("L", "home"))
                    .foregroundStyle(EnergyColor.home).lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round)).interpolationMethod(.monotone)
            }
        } else {
            ForEach(points) { p in
                BarMark(x: .value("Date", p.date, unit: unit), yStart: .value("Lo", 0.0), yEnd: .value("Hi", p.flow.house))
                    .foregroundStyle(EnergyColor.home.opacity(0.9)).position(by: .value("Side", "used"))
                BarMark(x: .value("Date", p.date, unit: unit), yStart: .value("Lo", p.flow.house), yEnd: .value("Hi", p.flow.house + p.flow.car))
                    .foregroundStyle(EnergyColor.vehicle.opacity(0.9)).position(by: .value("Side", "used"))
                BarMark(x: .value("Date", p.date, unit: unit), yStart: .value("Lo", 0.0), yEnd: .value("Hi", p.flow.solar))
                    .foregroundStyle(EnergyColor.solar.opacity(0.9)).position(by: .value("Side", "supplied"))
                BarMark(x: .value("Date", p.date, unit: unit), yStart: .value("Lo", p.flow.solar), yEnd: .value("Hi", p.flow.solar + p.flow.imp))
                    .foregroundStyle(EnergyColor.grid.opacity(0.9)).position(by: .value("Side", "supplied"))
                BarMark(x: .value("Date", p.date, unit: unit), yStart: .value("Lo", 0.0), yEnd: .value("Hi", -p.flow.exp))
                    .foregroundStyle(EnergyColor.grid.opacity(0.5)).position(by: .value("Side", "supplied"))
            }
        }
    }

    // MARK: Scrub box (tap and hold)

    private func scrub(_ sel: Date) -> some View {
        let hit: FlowPoint? = isDay
            ? points.min { abs($0.date.timeIntervalSince(sel)) < abs($1.date.timeIntervalSince(sel)) }
            : points.first { cal.isDate($0.date, equalTo: sel, toGranularity: unit) }
        let title: String
        if let h = hit {
            if isDay {
                let a = h.date.addingTimeInterval(-450)
                title = a.formatted(date: .omitted, time: .shortened)
            } else {
                title = h.date.formatted(byMonth ? .dateTime.month(.wide).year() : .dateTime.weekday(.abbreviated).day().month(.abbreviated))
            }
        } else { title = "" }
        let fmt = isDay ? "%.1f kW" : "%.1f kWh"
        let rows: [(String, Color, Double)]
        if let h = hit {
            if comp == .all {
                let f = h.flow, k = h.k
                rows = [("Solar", EnergyColor.solar, f.solar * k), ("Home", EnergyColor.home, f.house * k),
                        ("Model 3", EnergyColor.vehicle, f.car * k), ("Grid", EnergyColor.grid, (f.imp - f.exp) * k)]
            } else {
                rows = parts(h).map { ($0.0, $0.1, abs($0.2)) }
            }
        } else { rows = [] }
        return VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.app(size: 11, weight: .semibold))
            ForEach(rows, id: \.0) { r in
                HStack(spacing: 5) {
                    Circle().fill(r.1).frame(width: 6, height: 6)
                    Text(r.0).font(.app(size: 11)).foregroundStyle(TeslaDark.labelGrey)
                    Spacer(minLength: 10)
                    Text(String(format: fmt, r.2)).font(.app(size: 11, weight: .medium).monospacedDigit())
                }
            }
        }
        .lineLimit(1)
        .fixedSize()
        .padding(8)
        .background(Color(white: 0.17))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Week, Month and Year settle on a whole period when you let go; Day runs on freely.
private struct SnapToPeriod: ViewModifier {
    let period: ImpactPeriod
    @ViewBuilder func body(content: Content) -> some View {
        let first = Calendar.current.firstWeekday
        switch period {
        case .week:
            content.chartScrollTargetBehavior(.valueAligned(matching: DateComponents(hour: 0),
                                                            majorAlignment: .matching(DateComponents(weekday: first))))
        case .month:
            content.chartScrollTargetBehavior(.valueAligned(matching: DateComponents(hour: 0),
                                                            majorAlignment: .matching(DateComponents(day: 1))))
        case .year:
            content.chartScrollTargetBehavior(.valueAligned(matching: DateComponents(day: 1),
                                                            majorAlignment: .matching(DateComponents(month: 1, day: 1))))
        default:
            content
        }
    }
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
        let n = abs(x - x.rounded()) < 0.001 ? String(Int(x.rounded())) : String(format: "%.1f", x)
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
