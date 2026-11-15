import SwiftUI
import Charts

/// Tesla-app style Energy page: timescale menu top right, one component at a time (bar at the bottom),
/// stacked areas for a day (tap and hold to scrub), stacked bars for longer periods, Energy Flow rows below.
enum EnergyComponent: String, CaseIterable, Identifiable {
    case all, home, solar, vehicle, grid
    var id: String { rawValue }

    var name: String {
        switch self {
        case .all: return "All"
        case .home: return "Home"
        case .solar: return "Solar"
        case .vehicle: return "Vehicle"
        case .grid: return "Grid"
        }
    }

    var icon: String {
        switch self {
        case .all: return "chart.xyaxis.line"
        case .home: return "house.fill"
        case .solar: return "sun.max.fill"
        case .vehicle: return "car.side.fill"
        case .grid: return "bolt.horizontal.fill"
        }
    }

    var title: String {
        switch self {
        case .all: return "Power"
        case .home: return "Home usage"
        case .solar: return "Solar generated"
        case .vehicle: return "Vehicle charged"
        case .grid: return "Grid net"
        }
    }

    var flowCaption: String {
        switch self {
        case .home, .vehicle: return "FROM"
        case .solar: return "USED BY"
        case .all, .grid: return ""
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
    var id: String { name }
}

private struct ChartPoint: Identifiable {
    let date: Date
    let part: String
    let value: Double
    var id: String { "\(part)-\(date.timeIntervalSince1970)" }
}

struct EnergyView: View {
    @ObservedObject var store: EnergyStore
    @AppStorage("energy.period") private var periodRaw = ImpactPeriod.day.rawValue
    @State private var compRaw = EnergyComponent.all.rawValue   // always opens on All
    @State private var offset = 0
    @State private var selection: Date?

    private let cal = Calendar.current
    private var period: ImpactPeriod { ImpactPeriod(rawValue: periodRaw) ?? .day }
    private var comp: EnergyComponent { EnergyComponent(rawValue: compRaw) ?? .home }
    private var range: PeriodRange { PeriodRange.make(period, offset: offset, firstDay: store.firstDay) }
    /// The day's curve (Day view only), straight from the shared store.
    private var curve: DayCurve? { period == .day ? store.curve(range.start) : nil }

    var body: some View {
        let r = range
        let total = periodTotal(r)
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PeriodBar(range: r, period: period, firstDay: store.firstDay, offset: $offset)
                        .padding(.horizontal, -4)
                        .padding(.top, 4)
                        .padding(.bottom, 10)   // same spacing as the Impact page
                    if comp == .all {
                        HStack(spacing: 8) {
                            Text(period == .day ? "Power" : "Energy per \(period == .year || period == .lifetime ? "month" : "day")")
                                .font(.system(size: 13)).foregroundStyle(TeslaDark.rowLabel)
                            if store.loading { ProgressView().tint(.white).scaleEffect(0.6) }
                        }
                        allChart(r)
                            .frame(height: 210)
                            .padding(.top, 6)
                        allLegend
                            .padding(.top, 8)
                        allTiles(total)
                            .padding(.top, 12)
                        Text("Model 3 sits on top of Home (red line = everything used). Grid sits on top of Solar (grey line = everything supplied). Below 0 = solar exported to TNB.")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Color(white: 0.36))
                            .padding(.top, 10)
                    } else {
                        Text(comp.title).font(.system(size: 13)).foregroundStyle(TeslaDark.rowLabel)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(totalText(total)).font(.system(size: 32, weight: .semibold))
                            if store.loading { ProgressView().tint(.white).scaleEffect(0.7) }
                        }
                        .padding(.bottom, 10)
                        chart(r)
                            .frame(height: 230)
                        flowRows(total)
                            .padding(.top, 14)
                    }
                    if let msg = store.message {
                        Text(msg).font(.system(size: 11)).foregroundStyle(TeslaDark.importing).padding(.top, 8)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            componentBar
        }
        .teslaPage("Energy")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { PeriodMenu(periodRaw: $periodRaw, offset: $offset) }
        }
        .onChange(of: periodRaw) { _, _ in selection = nil }
        .onChange(of: compRaw) { _, _ in selection = nil }
        .onChange(of: offset) { _, _ in selection = nil }
        .task(id: "\(periodRaw)|\(offset)") {
            // Saved days show at once; this only tops up today / missing days (at most once a minute).
            await store.refresh()
        }
    }

    // MARK: Totals and parts

    private func periodTotal(_ r: PeriodRange) -> EnergyFlow {
        if period == .day { return curve?.total ?? EnergyFlow() }
        return store.flowTotal(from: r.start, to: r.end)
    }

    private func parts(_ f: EnergyFlow) -> [EnergyPart] {
        switch comp {
        case .all, .home:
            return [EnergyPart(name: "Solar", color: EnergyColor.solar, kwh: f.homeSolar),
                    EnergyPart(name: "Grid", color: EnergyColor.grid, kwh: f.homeGrid)]
        case .solar:
            return [EnergyPart(name: "Home", color: EnergyColor.home, kwh: f.homeSolar),
                    EnergyPart(name: "Vehicle", color: EnergyColor.vehicle, kwh: f.carSolar),
                    EnergyPart(name: "Grid", color: EnergyColor.grid, kwh: f.exp)]
        case .vehicle:
            return [EnergyPart(name: "Solar", color: EnergyColor.solar, kwh: f.carSolar),
                    EnergyPart(name: "Grid", color: EnergyColor.grid, kwh: f.carGrid)]
        case .grid:
            return [EnergyPart(name: "Imported", color: EnergyColor.grid, kwh: f.imp),
                    EnergyPart(name: "Exported", color: EnergyColor.gridOut, kwh: f.exp)]
        }
    }

    private func totalText(_ f: EnergyFlow) -> String {
        switch comp {
        case .all, .home: return kwh(f.house)
        case .solar: return kwh(f.solar)
        case .vehicle: return kwh(f.car)
        case .grid:
            let net = f.imp - f.exp
            return (net >= 0 ? "+" : "−") + kwh(abs(net))
        }
    }

    private func kwh(_ v: Double) -> String {
        v >= 100 ? String(format: "%.0f kWh", v) : String(format: "%.1f kWh", v)
    }

    // MARK: Chart

    @ViewBuilder private func chart(_ r: PeriodRange) -> some View {
        let template = parts(EnergyFlow())
        let names = template.map(\.name)
        let colors = template.map(\.color)
        if period == .day {
            dayChart(r, names: names, colors: colors)
        } else {
            barChart(r, names: names, colors: colors)
        }
    }

    private func dayPoints(_ r: PeriodRange) -> (points: [ChartPoint], step: TimeInterval) {
        guard let c = curve else { return ([], 900) }
        let step = TimeInterval(c.minutes * 60)
        let perHour = 60.0 / Double(c.minutes)
        var lastSlot = c.count
        if cal.isDateInToday(r.start) {
            lastSlot = min(c.count, max(0, Int(Date().timeIntervalSince(r.start) / step)))
        }
        var out: [ChartPoint] = []
        out.reserveCapacity(lastSlot * 3)
        for i in 0..<lastSlot {
            let t = r.start.addingTimeInterval(Double(i) * step + step / 2)
            let f = c.flow(i)
            if comp == .grid {
                out.append(ChartPoint(date: t, part: "Imported", value: (f.imp - f.exp) * perHour))
            } else {
                for p in parts(f) { out.append(ChartPoint(date: t, part: p.name, value: p.kwh * perHour)) }
            }
        }
        return (out, step)
    }

    private func dayChart(_ r: PeriodRange, names: [String], colors: [Color]) -> some View {
        let (points, step) = dayPoints(r)
        return Chart {
            ForEach(points) { p in
                AreaMark(x: .value("Time", p.date), y: .value("kW", p.value), stacking: .standard)
                    .foregroundStyle(by: .value("Part", p.part))
                    .interpolationMethod(.monotone)
                    .opacity(comp == .grid ? 0.7 : 0.9)
            }
            if let sel = selection {
                RuleMark(x: .value("Selected", sel))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: side(sel, r), alignment: .top, spacing: 8,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        dayScrub(sel, r, step: step)
                    }
            }
        }
        .chartForegroundStyleScale(domain: names, range: colors)
        .chartLegend(.hidden)
        .chartXScale(domain: r.start...r.end)
        .chartXSelection(value: $selection)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                AxisValueLabel(format: .dateTime.hour(.twoDigits(amPM: .omitted)))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { v in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                AxisValueLabel { if let d = v.as(Double.self) { Text("\(Int(d)) kW") } }
            }
        }
        .overlay {
            if curve == nil && !store.loading {
                Text("No data for this day").font(.system(size: 12)).foregroundStyle(TeslaDark.rowLabel)
            }
        }
    }

    private func dayScrub(_ sel: Date, _ r: PeriodRange, step: TimeInterval) -> some View {
        let perHour = 3600 / step
        let i = max(0, min((curve?.count ?? 1) - 1, Int(sel.timeIntervalSince(r.start) / step)))
        let f = curve.map { $0.flow(i) } ?? EnergyFlow()
        let time = r.start.addingTimeInterval(Double(i) * step)
        let rows: [EnergyPart] = comp == .grid
            ? [EnergyPart(name: f.imp >= f.exp ? "Importing" : "Exporting", color: EnergyColor.grid, kwh: abs(f.imp - f.exp))]
            : parts(f)
        return scrubBox(time.formatted(date: .omitted, time: .shortened), rows.map { ($0, String(format: "%.1f kW", $0.kwh * perHour)) })
    }

    private func scrubBox(_ title: String, _ rows: [(EnergyPart, String)]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 11, weight: .semibold))
            ForEach(rows, id: \.0.id) { row in
                HStack(spacing: 5) {
                    Circle().fill(row.0.color).frame(width: 6, height: 6)
                    Text(row.0.name).font(.system(size: 11)).foregroundStyle(TeslaDark.labelGrey)
                    Spacer(minLength: 6)
                    Text(row.1).font(.system(size: 11, weight: .medium))
                }
            }
        }
        .padding(8)
        .frame(width: 140)
        .background(Color(white: 0.17))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// Bars: one per day (Week, Month) or per month (Year, Lifetime).
    private func buckets(_ r: PeriodRange) -> [(date: Date, flow: EnergyFlow)] {
        let byMonth = period == .year || period == .lifetime
        var out: [(date: Date, flow: EnergyFlow)] = []
        var d = r.start
        while d < r.end {
            let next = cal.date(byAdding: byMonth ? .month : .day, value: 1, to: d) ?? r.end
            var f = EnergyFlow()
            var x = d
            while x < min(next, r.end) {
                if let df = store.flow(x) { f = f + df }
                x = cal.date(byAdding: .day, value: 1, to: x) ?? next
            }
            out.append((date: d, flow: f))
            d = byMonth ? (cal.dateInterval(of: .month, for: next)?.start ?? next) : next
        }
        return out
    }

    private func barChart(_ r: PeriodRange, names: [String], colors: [Color]) -> some View {
        let byMonth = period == .year || period == .lifetime
        let unit: Calendar.Component = byMonth ? .month : .day
        let b = buckets(r)
        var points: [ChartPoint] = []
        for (date, f) in b {
            if comp == .grid {
                points.append(ChartPoint(date: date, part: "Imported", value: f.imp))
                points.append(ChartPoint(date: date, part: "Exported", value: -f.exp))
            } else {
                for p in parts(f) { points.append(ChartPoint(date: date, part: p.name, value: p.kwh)) }
            }
        }
        return Chart {
            ForEach(points) { p in
                BarMark(x: .value("Date", p.date, unit: unit), y: .value("kWh", p.value), width: .ratio(0.6))
                    .foregroundStyle(by: .value("Part", p.part))
            }
            if let sel = selection, let hit = b.first(where: { cal.isDate($0.date, equalTo: sel, toGranularity: unit) }) {
                RuleMark(x: .value("Selected", hit.date, unit: unit))
                    .foregroundStyle(Color.white.opacity(0.12))
                    .lineStyle(StrokeStyle(lineWidth: byMonth ? 18 : 8))
                    .annotation(position: side(sel, r), alignment: .top, spacing: 8,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        scrubBox(hit.date.formatted(byMonth ? .dateTime.month(.wide).year() : .dateTime.weekday(.abbreviated).day().month(.abbreviated)),
                                 parts(hit.flow).map { ($0, kwh($0.kwh)) })
                    }
            }
        }
        .chartForegroundStyleScale(domain: names, range: colors)
        .chartLegend(.hidden)
        .chartXSelection(value: $selection)
        .chartXAxis {
            AxisMarks(values: .stride(by: axisUnit, count: axisCount(b.count))) { _ in
                AxisValueLabel(format: axisFormat, centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { v in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                AxisValueLabel { if let d = v.as(Double.self) { Text("\(Int(d))") } }
            }
        }
    }

    private var axisUnit: Calendar.Component { period == .year || period == .lifetime ? .month : .day }

    private func axisCount(_ n: Int) -> Int {
        switch period {
        case .month: return 7
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

    // MARK: All (the four lines together, with the six numbers)

    private static let allNames = ["Solar", "Home", "Model 3", "Grid"]
    private static let allColors = [EnergyColor.solar, EnergyColor.home, EnergyColor.vehicle, EnergyColor.grid]
    /// One time step on the All graph (kW for a day, kWh per day / month otherwise).
    private struct StackPoint: Identifiable {
        let date: Date
        let home, car, solar, imp, exp: Double
        var id: Double { date.timeIntervalSince1970 }
    }

    private func allSeries(_ r: PeriodRange) -> (points: [StackPoint], step: TimeInterval, unit: Calendar.Component?) {
        func point(_ t: Date, _ f: EnergyFlow, _ k: Double) -> StackPoint {
            StackPoint(date: t, home: f.house * k, car: f.car * k, solar: f.solar * k, imp: f.imp * k, exp: f.exp * k)
        }
        if period == .day {
            guard let c = curve else { return ([], 900, nil) }
            let step = TimeInterval(c.minutes * 60)
            var last = c.count
            if cal.isDateInToday(r.start) { last = min(c.count, max(0, Int(Date().timeIntervalSince(r.start) / step))) }
            let k = 60.0 / Double(c.minutes)
            return ((0..<last).map { point(r.start.addingTimeInterval(Double($0) * step + step / 2), c.flow($0), k) }, step, nil)
        }
        return (buckets(r).map { point($0.date, $0.flow, 1) }, 0, axisUnit)
    }

    /// Stacked so the totals line up: Model 3 sits on Home (red top = everything used), grid import sits on Solar
    /// (grey top = everything supplied); export is shown below zero.
    private func allChart(_ r: PeriodRange) -> some View {
        let (points, step, unit) = allSeries(r)
        return Chart {
            ForEach(points) { p in
                AreaMark(x: .value("Time", p.date), yStart: .value("Lo", 0.0), yEnd: .value("Hi", p.solar), series: .value("F", "solar"))
                    .foregroundStyle(EnergyColor.solar.opacity(0.22)).interpolationMethod(.monotone)
            }
            ForEach(points) { p in
                AreaMark(x: .value("Time", p.date), yStart: .value("Lo", p.solar), yEnd: .value("Hi", p.solar + p.imp), series: .value("F", "import"))
                    .foregroundStyle(EnergyColor.grid.opacity(0.25)).interpolationMethod(.monotone)
            }
            ForEach(points) { p in
                AreaMark(x: .value("Time", p.date), yStart: .value("Lo", 0.0), yEnd: .value("Hi", -p.exp), series: .value("F", "export"))
                    .foregroundStyle(EnergyColor.grid.opacity(0.3)).interpolationMethod(.monotone)
            }
            ForEach(points) { p in
                AreaMark(x: .value("Time", p.date), yStart: .value("Lo", 0.0), yEnd: .value("Hi", p.home), series: .value("F", "home"))
                    .foregroundStyle(EnergyColor.home.opacity(0.25)).interpolationMethod(.monotone)
            }
            ForEach(points) { p in
                AreaMark(x: .value("Time", p.date), yStart: .value("Lo", p.home), yEnd: .value("Hi", p.home + p.car), series: .value("F", "car"))
                    .foregroundStyle(EnergyColor.vehicle.opacity(0.28)).interpolationMethod(.monotone)
            }
            // Lines on top: grey (supply top, export), yellow, red, then blue over red, so red only shows while charging.
            ForEach(points) { p in
                LineMark(x: .value("Time", p.date), y: .value("V", p.solar + p.imp), series: .value("L", "supply"))
                    .foregroundStyle(EnergyColor.grid).lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round)).interpolationMethod(.monotone)
            }
            ForEach(points) { p in
                LineMark(x: .value("Time", p.date), y: .value("V", -p.exp), series: .value("L", "export"))
                    .foregroundStyle(EnergyColor.grid).lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round)).interpolationMethod(.monotone)
            }
            ForEach(points) { p in
                LineMark(x: .value("Time", p.date), y: .value("V", p.solar), series: .value("L", "solar"))
                    .foregroundStyle(EnergyColor.solar).lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round)).interpolationMethod(.monotone)
            }
            ForEach(points) { p in
                LineMark(x: .value("Time", p.date), y: .value("V", p.home + p.car), series: .value("L", "used"))
                    .foregroundStyle(EnergyColor.vehicle).lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round)).interpolationMethod(.monotone)
            }
            ForEach(points) { p in
                LineMark(x: .value("Time", p.date), y: .value("V", p.home), series: .value("L", "home"))
                    .foregroundStyle(EnergyColor.home).lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round)).interpolationMethod(.monotone)
            }
            if let sel = selection {
                RuleMark(x: .value("Selected", sel))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: side(sel, r), alignment: .top, spacing: 8,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        allScrub(sel, r, step: step, unit: unit)
                    }
            }
        }
        .chartLegend(.hidden)
        .chartXScale(domain: r.start...r.end)
        .chartXSelection(value: $selection)
        .chartXAxis {
            AxisMarks(values: .stride(by: period == .day ? .hour : axisUnit,
                                      count: period == .day ? 6 : axisCount(points.count))) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                AxisValueLabel(format: period == .day ? Date.FormatStyle.dateTime.hour(.twoDigits(amPM: .omitted)) : axisFormat)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { v in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                AxisValueLabel { if let d = v.as(Double.self) { Text("\(Int(d))") } }
            }
        }
        .overlay {
            if points.isEmpty && !store.loading {
                Text("No data for this period").font(.system(size: 12)).foregroundStyle(TeslaDark.rowLabel)
            }
        }
    }

    private func allScrub(_ sel: Date, _ r: PeriodRange, step: TimeInterval, unit: Calendar.Component?) -> some View {
        let f: EnergyFlow
        let title: String
        let k: Double
        let fmt: String
        if period == .day {
            let i = max(0, min((curve?.count ?? 1) - 1, Int(sel.timeIntervalSince(r.start) / max(step, 1))))
            f = curve.map { $0.flow(i) } ?? EnergyFlow()
            title = r.start.addingTimeInterval(Double(i) * step).formatted(date: .omitted, time: .shortened)
            k = 3600 / max(step, 1)
            fmt = "%.1f kW"
        } else {
            let u = unit ?? .day
            let hit = buckets(r).first { cal.isDate($0.date, equalTo: sel, toGranularity: u) }
            f = hit?.flow ?? EnergyFlow()
            title = (hit?.date ?? sel).formatted(u == .month ? .dateTime.month(.wide).year() : .dateTime.weekday(.abbreviated).day().month(.abbreviated))
            k = 1
            fmt = "%.1f kWh"
        }
        let vals = [f.solar, f.house, f.car, f.imp - f.exp]
        let rows = (0..<4).map { (EnergyPart(name: Self.allNames[$0], color: Self.allColors[$0], kwh: vals[$0]), String(format: fmt, vals[$0] * k)) }
        return scrubBox(title, rows)
    }

    private var allLegend: some View {
        HStack(spacing: 14) {
            ForEach([1, 2, 0, 3], id: \.self) { i in
                HStack(spacing: 5) {
                    Circle().fill(Self.allColors[i]).frame(width: 8, height: 8)
                    Text(Self.allNames[i]).font(.system(size: 12)).foregroundStyle(TeslaDark.labelGrey)
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

    private func tile(_ icon: String, _ color: Color, _ title: String, _ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(color)
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(TeslaDark.labelGrey)
            }
            Text(value).font(.system(size: 19, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(caption).font(.system(size: 10.5)).foregroundStyle(TeslaDark.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(TeslaDark.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Scrub box goes beside the line, inside the graph: right of it in the first half, left of it after.
    private func side(_ sel: Date, _ r: PeriodRange) -> AnnotationPosition {
        sel.timeIntervalSince(r.start) > r.end.timeIntervalSince(r.start) * 0.55 ? .leading : .trailing
    }

    // MARK: Energy flow

    private func flowRows(_ f: EnergyFlow) -> some View {
        let ps = parts(f)
        let sum = ps.reduce(0) { $0 + $1.kwh }
        return VStack(alignment: .leading, spacing: 0) {
            if !comp.flowCaption.isEmpty {
                Text(comp.flowCaption).font(.system(size: 11, weight: .semibold)).kerning(0.5)
                    .foregroundStyle(TeslaDark.dim).padding(.bottom, 4)
            }
            ForEach(ps) { p in
                HStack(spacing: 10) {
                    Circle().fill(p.color).frame(width: 9, height: 9)
                    Text(p.name).font(.system(size: 15))
                    Spacer()
                    Text(kwh(p.kwh)).font(.system(size: 15))
                    if comp != .grid {
                        Text(sum > 0 ? "\(Int((p.kwh / sum * 100).rounded()))%" : "—")
                            .font(.system(size: 13)).foregroundStyle(TeslaDark.rowLabel)
                            .frame(width: 42, alignment: .trailing)
                    }
                }
                .padding(.vertical, 11)
                Divider().overlay(Color.white.opacity(0.08))
            }
        }
    }

    // MARK: Component bar

    private var componentBar: some View {
        HStack(spacing: 0) {
            ForEach(EnergyComponent.allCases) { c in
                Button { compRaw = c.rawValue } label: {
                    VStack(spacing: 3) {
                        Image(systemName: c.icon).font(.system(size: 19)).frame(height: 24)
                        Text(c.name).font(.system(size: 10, weight: comp == c ? .semibold : .regular))
                    }
                    .foregroundStyle(comp == c ? Color.white : TeslaDark.dim)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
        .background(TeslaDark.bg)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5) }
    }
}
