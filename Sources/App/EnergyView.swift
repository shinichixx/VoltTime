import SwiftUI
import Charts

/// Tesla-app style Energy page: timescale menu top right, one component at a time (bar at the bottom),
/// stacked areas for a day (tap and hold to scrub), stacked bars for longer periods, Energy Flow rows below.
enum EnergyComponent: String, CaseIterable, Identifiable {
    case home, solar, vehicle, grid
    var id: String { rawValue }

    var name: String {
        switch self {
        case .home: return "Home"
        case .solar: return "Solar"
        case .vehicle: return "Vehicle"
        case .grid: return "Grid"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .solar: return "sun.max.fill"
        case .vehicle: return "car.side.fill"
        case .grid: return "bolt.horizontal.fill"
        }
    }

    var title: String {
        switch self {
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
        case .grid: return ""
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
    @ObservedObject var energy: EnergyModel
    @ObservedObject var impact: ImpactModel
    @AppStorage("energy.period") private var periodRaw = ImpactPeriod.day.rawValue
    @AppStorage("energy.component") private var compRaw = EnergyComponent.home.rawValue
    @State private var offset = 0
    @State private var curve: DayCurve?
    @State private var curveDay: Date?
    @State private var selection: Date?

    private let cal = Calendar.current
    private var period: ImpactPeriod { ImpactPeriod(rawValue: periodRaw) ?? .day }
    private var comp: EnergyComponent { EnergyComponent(rawValue: compRaw) ?? .home }

    var body: some View {
        let r = PeriodRange.make(period, offset: offset, firstDay: impact.firstDay)
        let total = periodTotal(r)
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PeriodBar(range: r, period: period, firstDay: impact.firstDay, offset: $offset)
                        .padding(.horizontal, -6)
                    Text(comp.title).font(.system(size: 13)).foregroundStyle(TeslaDark.rowLabel)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(totalText(total)).font(.system(size: 32, weight: .semibold))
                        if (period == .day ? energy.loading : impact.loading) { ProgressView().tint(.white).scaleEffect(0.7) }
                    }
                    .padding(.bottom, 10)
                    chart(r)
                        .frame(height: 230)
                    flowRows(total)
                        .padding(.top, 14)
                    if let msg = energy.message ?? impact.message {
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
            guard period == .day else { return }
            let day = r.start
            if curveDay != day {
                curve = energy.cached(day)
                curveDay = day
            }
            if let c = await energy.curve(day), curveDay == day { curve = c }
        }
        .task { await impact.refresh() }
    }

    // MARK: Totals and parts

    private func periodTotal(_ r: PeriodRange) -> EnergyFlow {
        if period == .day { return curve?.total ?? EnergyFlow() }
        var t = EnergyFlow()
        var d = r.start
        while d < r.end {
            if let s = impact.days[ImpactModel.keyFormatter.string(from: d)] { t = t + EnergyFlow(s) }
            guard let n = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = n
        }
        return t
    }

    private func parts(_ f: EnergyFlow) -> [EnergyPart] {
        switch comp {
        case .home:
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
        case .home: return kwh(f.house)
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
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
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
            if curve == nil && !energy.loading {
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
                if let s = impact.days[ImpactModel.keyFormatter.string(from: x)] { f = f + EnergyFlow(s) }
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
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
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
