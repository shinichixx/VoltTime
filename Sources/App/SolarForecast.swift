import SwiftUI
import Charts

// Build 54: one solar forecast a day, kept forever, to set against what the inverter actually made.

/// Each day's solar forecast (kWh): Solcast (Forecast.Solar before), as it stood before sunrise that day.
@MainActor
final class SolarForecastLog: ObservableObject {
    static let shared = SolarForecastLog()
    nonisolated static var file: URL { AppData.support.appendingPathComponent("solar-forecast.json") }
    static var todaySensor: String { SolarSensors.current.today }
    private static let solcastKey = "forecastLog.solcastSince"

    /// First day whose forecast comes from Solcast (Forecast.Solar before it).
    var solcastSince: Date? { UserDefaults.standard.object(forKey: Self.solcastKey) as? Date }

    func noteSolcast() {
        let d = UserDefaults.standard
        guard d.object(forKey: Self.solcastKey) == nil else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // Today already saved from Forecast.Solar? Then Solcast starts tomorrow.
        let start = days[EnergyStore.keyFormatter.string(from: today)] != nil ? (cal.date(byAdding: .day, value: 1, to: today) ?? today) : today
        d.set(start, forKey: Self.solcastKey)
        d.removeObject(forKey: Self.checkedKey)
    }
    private static let checkedKey = "forecastLog.checked"
    /// No day on an 8.85 kWp roof makes this much: a bigger figure is a unit mix-up.
    static let maxDay = 150.0

    @Published private(set) var days: [String: Double] = [:]

    private init() {
        if let d = try? Data(contentsOf: Self.file), let v = try? JSONDecoder().decode([String: Double].self, from: d) { days = v }
        // Build 54 read the wrong moment of the day: start again (Home Assistant still has the last 10 days).
        let ud = UserDefaults.standard
        if !ud.bool(forKey: "forecastLog.v55") {
            days = [:]
            try? FileManager.default.removeItem(at: Self.file)
            ud.removeObject(forKey: Self.checkedKey)
            ud.set(true, forKey: "forecastLog.v55")
        }
        // Build 65 saved Solcast's Wh figure as kWh: drop anything impossible for the roof.
        let bad = days.filter { $0.value >= Self.maxDay }.map(\.key)
        if !bad.isEmpty {
            bad.forEach { days[$0] = nil }
            save()
            ud.removeObject(forKey: Self.checkedKey)
        }
    }

    var firstDay: Date? { days.keys.min().flatMap { EnergyStore.keyFormatter.date(from: $0) } }

    func forecast(_ day: Date) -> Double? { days[EnergyStore.keyFormatter.string(from: day)] }

    /// When Solcast made the saved read (its first after sunrise), per day.
    private var readTimes: [String: Double] {
        get { UserDefaults.standard.dictionary(forKey: "forecastLog.readTimes") as? [String: Double] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "forecastLog.readTimes") }
    }
    func readTime(_ day: Date) -> Date? { readTimes[EnergyStore.keyFormatter.string(from: day)].map { Date(timeIntervalSince1970: $0) } }
    func isSolcast(_ day: Date) -> Bool { solcastSince.map { day >= $0 } ?? false }

    private func save() {
        try? FileManager.default.createDirectory(at: AppData.support, withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(days) { try? d.write(to: Self.file, options: .atomic) }
    }

    /// For each of the last 10 days not yet recorded, asks Home Assistant for the forecast as it stood at 06:00
    /// (one small history request per day: the first value returned is the state at that moment).
    /// At most once an hour.
    func update(_ ha: HAClient) async {
        let d = UserDefaults.standard
        if let last = d.object(forKey: Self.checkedKey) as? Date, Date().timeIntervalSince(last) < 1800 { return }
        d.set(Date(), forKey: Self.checkedKey)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var changed = false
        for back in 0...10 {
            guard let day = cal.date(byAdding: .day, value: -back, to: today) else { continue }
            let k = EnergyStore.keyFormatter.string(from: day)
            let six = day.addingTimeInterval(6 * 3600)
            if SolarSensors.current.isSolcast, let since = solcastSince, day >= since {
                // Solcast reads 5 times a day from sunrise (the times move with sunrise). Save its first read of
                // the day: the first change after 05:00. None by 10:00? Then the value it had at 05:00.
                let five = day.addingTimeInterval(5 * 3600), ten = day.addingTimeInterval(10 * 3600)
                guard days[k] == nil, Date() > five else { continue }
                guard let h = try? await ha.history([Self.todaySensor], since: five, until: min(Date(), ten)),
                      let pts = h[Self.todaySensor], !pts.isEmpty else { continue }
                let pick: (Date, Double)?
                if let first = pts.first(where: { $0.0 > five.addingTimeInterval(30) }) { pick = first }
                else if Date() > ten { pick = (pts[0].0, pts[0].1) } else { pick = nil }
                guard let pick else { continue }
                let (t, raw) = pick
                let v = raw * SolarSensors.current.scale
                guard v > 0, v < Self.maxDay else { continue }
                days[k] = v
                if t > five.addingTimeInterval(30) { readTimes[k] = t.timeIntervalSince1970 }
                changed = true
                continue
            }
            guard days[k] == nil, Date() > six else { continue }
            guard let h = try? await ha.history([Self.todaySensor], since: six, until: six.addingTimeInterval(60)),
                  let raw = h[Self.todaySensor]?.first?.1 else { continue }
            let v = raw * SolarSensors.current.scale
            guard v > 0, v < Self.maxDay else { continue }
            days[k] = v
            changed = true
        }
        if changed { save() }
    }

    /// The live figure, if nothing was saved for today yet (e.g. history is unavailable).
    func noteToday(_ v: Double) {
        let k = EnergyStore.keyFormatter.string(from: Date())
        guard !SolarSensors.current.isSolcast,   // Solcast days come from its first read after sunrise (update)
              v > 0, v < Self.maxDay, days[k] == nil else { return }
        days[k] = v
        save()
    }

    /// Restore: adds days the app doesn't have.
    func merge(_ data: Data) -> Int {
        guard let v = try? JSONDecoder().decode([String: Double].self, from: data) else { return 0 }
        var n = 0
        for (k, x) in v where days[k] == nil { days[k] = x; n += 1 }
        if n > 0 { save() }
        return n
    }
}

// MARK: - Forecast vs actual page

private struct FBucket: Identifiable {
    let date: Date
    let forecast: Double?      // sum over days with a forecast
    let actual: Double?        // sum over every day
    var matchedActual: Double? = nil   // actual over the days that have a forecast
    var isToday = false
    var id: Date { date }
    var diff: Double? {
        guard let f = forecast, let a = matchedActual, f > 0 else { return nil }
        return (a - f) / f * 100
    }
}

/// Grey within ±10 %, green when the sun beat the forecast, amber 10–30 % short, red beyond.
func forecastDiffColor(_ p: Double) -> Color {
    if abs(p) <= 10 { return TeslaDark.rowLabel }
    if p > 0 { return TeslaDark.exporting }
    return p < -30 ? CarColors.red : CarColors.amber
}

struct ForecastVsActualView: View {
    @ObservedObject var model: EnergyStore
    @ObservedObject private var log = SolarForecastLog.shared
    @AppStorage("forecast.period") private var periodRaw = ImpactPeriod.month.rawValue
    @State private var offset = 0
    @State private var picked: Date?
    @State private var forward = false

    private let cal = Calendar.current
    private var period: ImpactPeriod { ImpactPeriod(rawValue: periodRaw) ?? .month }
    private var byMonth: Bool { period == .year || period == .lifetime }
    private static let yellow = Color(red: 1, green: 0.8, blue: 0.2)

    private var first: Date { log.firstDay ?? cal.startOfDay(for: Date()) }

    var body: some View {
        let r = PeriodRange.make(period, offset: offset, firstDay: first)
        let bs = buckets(r)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(r, bs).padding(.horizontal, 20)
                if period == .day {
                    dayCard(r.start).padding(.horizontal, 16).padding(.top, 14)
                        .gesture(DragGesture(minimumDistance: 18).onEnded { d in
                            let w = d.translation.width
                            guard abs(w) > 50, abs(w) > abs(d.translation.height) * 1.4 else { return }
                            step(w < 0 ? 1 : -1, r)
                        })
                } else {
                    ZStack {
                        chart(r, bs)
                            .id("\(periodRaw)|\(offset)")
                            .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading),
                                                    removal: .move(edge: forward ? .leading : .trailing)))
                    }
                    .frame(height: 270)
                    .clipShape(OpenTopClip())
                    .padding(.top, 18)
                    Group {
                        legend.padding(.horizontal, 20).padding(.top, 8)
                        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5).padding(.top, 14)
                        summaryLines(r, bs).padding(.horizontal, 20).padding(.top, 16)
                        table(bs).padding(.horizontal, 20).padding(.top, 22)
                    }
                    .opacity(picked == nil ? 1 : 0.25)
                    .animation(.easeOut(duration: 0.15), value: picked == nil)
                }
                Text(footnote)
                    .font(.app(size: 11)).foregroundStyle(TeslaDark.dim)
                    .lineSpacing(3)
                    .padding(.top, 18).padding(.horizontal, 20)
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .pinnedTop { titleRow(r).padding(.horizontal, 20) }
        .teslaPage("Forecast vs actual")
        .onChange(of: periodRaw) { _, _ in picked = nil }
        .onChange(of: offset) { _, _ in picked = nil }
    }

    /// One swipe, one period (the graph slides in from that side).
    private func step(_ by: Int, _ r: PeriodRange) {
        if by < 0 { guard period != .lifetime, r.start > first else { return } }
        else { guard period != .lifetime, offset < 0 else { return } }
        forward = by > 0
        picked = nil
        DispatchQueue.main.async { withAnimation(.easeInOut(duration: 0.28)) { offset += by } }
    }

    // MARK: Header (Energy page style)

    private func header(_ r: PeriodRange, _ bs: [FBucket]) -> some View {
        let f = bs.compactMap(\.forecast).reduce(0, +)
        let a = bs.compactMap(\.actual).reduce(0, +)
        let m = bs.compactMap(\.matchedActual).reduce(0, +)
        return VStack(alignment: .leading, spacing: 0) {
            if period != .day {
                HStack(alignment: .top, spacing: 0) {
                    figure("Generated", a)
                    figure("Forecast", f)
                    figure("Actual", m)
                }
                .padding(.top, 14)
                .opacity(picked == nil ? 1 : 0)
            }
        }
    }

    /// Pinned under the top bar; the page scrolls beneath it.
    private func titleRow(_ r: PeriodRange) -> some View {
        HStack {
            Text(headerLabel(r)).font(.app(size: 17, weight: .semibold))
            Spacer()
            PeriodMenu(periodRaw: $periodRaw, offset: $offset, boxed: true, firstDay: log.firstDay)
                .opacity(picked == nil ? 1 : 0)
                .allowsHitTesting(picked == nil)
        }
        .padding(.top, 6)
    }

    private func headerLabel(_ r: PeriodRange) -> String {
        guard let p = picked else { return r.label }
        return byMonth ? p.formatted(.dateTime.month(.wide).year())
                       : (cal.isDateInToday(p) ? "Today" : p.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
    }

    private func figure(_ title: String, _ v: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.app(size: 13)).foregroundStyle(TeslaDark.rowLabel)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(k(v)).font(.app(size: 24, weight: .semibold))
                Text("kWh").font(.app(size: 13)).foregroundStyle(TeslaDark.rowLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) { Circle().fill(Self.yellow).frame(width: 8, height: 8); Text("Actual") }
            HStack(spacing: 5) { Capsule().fill(.white).frame(width: 14, height: 2.5); Text("Forecast") }
        }
        .font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
    }

    private func summaryLines(_ r: PeriodRange, _ bs: [FBucket]) -> some View {
        let f = bs.compactMap(\.forecast).reduce(0, +)
        let m = bs.compactMap(\.matchedActual).reduce(0, +)
        let p = f > 0 ? (m - f) / f * 100 : 0
        let (have, _) = dayCounts(r)
        return VStack(alignment: .leading, spacing: 6) {
            if f > 0 {
                Text("Actual came \(String(format: "%.0f", abs(p)))% \(p < 0 ? "lower" : "higher") than forecast")
                    .font(.app(size: 14, weight: .semibold))
                Text("On the \(have) \(have == 1 ? "day" : "days") with a forecast"
                     + (typicalMiss(r).map { " · typical miss ±" + String(format: "%.0f", $0) + "%" } ?? ""))
                    .font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
            } else {
                Text("No forecast saved for these days yet").font(.app(size: 14, weight: .semibold))
            }
        }
    }

    private var footnote: String {
        guard let since = log.solcastSince else {
            return "Forecast: the solar forecast for the day, saved each morning.\nActual: what the inverter produced."
        }
        let day = since.formatted(.dateTime.day().month(.abbreviated))
        let older = (log.firstDay.map { $0 < since } ?? false) ? " Forecast.Solar before \(day)." : ""
        return "Forecast: Solcast (2 roof planes), first read after sunrise each day." + older
            + "\nLatest: Solcast updates 5 times a day.\nActual: what the inverter produced."
    }

    // MARK: Data

    private func actual(_ day: Date) -> Double? { model.flow(day)?.solar }

    /// One bucket per day (Week, Month) or per month (Year, Lifetime). Only days with a saved forecast count.
    private func buckets(_ r: PeriodRange) -> [FBucket] {
        var out: [FBucket] = []
        let todayStart = cal.startOfDay(for: Date())
        let todayEnd = cal.date(byAdding: .day, value: 1, to: todayStart) ?? Date()
        var d = byMonth ? (cal.dateInterval(of: .month, for: r.start)?.start ?? r.start) : r.start
        while d < r.end {
            let next = cal.date(byAdding: byMonth ? .month : .day, value: 1, to: d) ?? r.end
            var f = 0.0, a = 0.0, m = 0.0, anyF = false, anyA = false
            var x = max(d, byMonth ? cal.startOfDay(for: r.start) : d)
            while x < min(next, r.end, todayEnd) {
                let ax = actual(x)
                if let ax { a += ax; anyA = true }
                if let fx = log.forecast(x) { f += fx; m += ax ?? 0; anyF = true }
                x = cal.date(byAdding: .day, value: 1, to: x) ?? next
            }
            var b = FBucket(date: d, forecast: anyF ? f : nil, actual: anyA ? a : nil)
            b.matchedActual = anyF ? m : nil
            b.isToday = !byMonth && cal.isDate(d, inSameDayAs: todayStart)
            out.append(b)
            d = next
        }
        return out
    }

    /// Days in the period up to today, and how many of them have a forecast.
    private func dayCounts(_ r: PeriodRange) -> (Int, Int) {
        var have = 0, total = 0
        var x = cal.startOfDay(for: r.start)
        let end = min(r.end, cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? r.end)
        while x < end {
            total += 1
            if log.forecast(x) != nil { have += 1 }
            x = cal.date(byAdding: .day, value: 1, to: x) ?? end
        }
        return (have, total)
    }

    /// Typical miss: the average size of the daily difference (finished days only).
    private func typicalMiss(_ r: PeriodRange) -> Double? {
        var sum = 0.0, n = 0
        var x = r.start
        let today = cal.startOfDay(for: Date())
        while x < min(r.end, today) {
            if let f = log.forecast(x), f > 0, let a = actual(x) { sum += abs(a - f) / f * 100; n += 1 }
            x = cal.date(byAdding: .day, value: 1, to: x) ?? r.end
        }
        return n > 0 ? sum / Double(n) : nil
    }

    // MARK: Views

    private func cardBox<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0, content: c)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TeslaDark.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func k(_ v: Double) -> String { Num.kwh(v, whole: byMonth) }

    private func summaryLabel(_ r: PeriodRange) -> String {
        let current = offset == 0
        switch period {
        case .week: return current ? "THIS WEEK SO FAR" : "THAT WEEK"
        case .month: return current ? "THIS MONTH SO FAR" : r.label.uppercased()
        case .year: return current ? "THIS YEAR SO FAR" : r.label
        default: return r.label.uppercased()
        }
    }

    private func summary(_ r: PeriodRange, _ bs: [FBucket]) -> some View {
        let f = bs.compactMap(\.forecast).reduce(0, +)
        let a = bs.compactMap(\.actual).reduce(0, +)
        let m = bs.compactMap(\.matchedActual).reduce(0, +)
        let p = f > 0 ? (m - f) / f * 100 : 0
        let (have, total) = dayCounts(r)
        return cardBox {
            Text(summaryLabel(r)).font(.app(size: 10, weight: .medium)).kerning(0.6).foregroundStyle(TeslaDark.rowLabel)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(k(a)).font(.app(size: 32, weight: .semibold)).foregroundStyle(Self.yellow)
                Text("kWh generated").font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
            }
            .padding(.top, 4)
            Rectangle().fill(Color(white: 0.22)).frame(height: 0.5).padding(.vertical, 12)
            if f > 0 {
                Text(have < total ? "ON THE \(have) \(have == 1 ? "DAY" : "DAYS") WITH A FORECAST" : "FORECAST VS ACTUAL")
                    .font(.app(size: 9, weight: .medium)).kerning(0.6).foregroundStyle(TeslaDark.rowLabel)
                HStack(alignment: .top, spacing: 0) {
                    stat("Forecast", k(f), "kWh")
                    stat("Actual", k(m), "kWh")
                    stat("Typical miss", typicalMiss(r).map { "±" + String(format: "%.0f", $0) } ?? "—", "%")
                }
                .padding(.top, 8)
                Text("Actual came \(String(format: "%.0f", abs(p)))% \(p < 0 ? "lower" : "higher") than forecast")
                    .font(.app(size: 11)).foregroundStyle(TeslaDark.rowLabel).padding(.top, 8)
            } else {
                Text("No forecast saved for these days yet").font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
            }
        }
    }

    private func stat(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.app(size: 11)).foregroundStyle(TeslaDark.rowLabel)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.app(size: 19, weight: .semibold))
                Text(unit).font(.app(size: 10)).foregroundStyle(TeslaDark.rowLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var unit: Calendar.Component { byMonth ? .month : .day }

    /// Edge to edge, the scale inside at the right (Energy page style); tap and hold to read a day.
    private func chart(_ r: PeriodRange, _ bs: [FBucket]) -> some View {
        let sel = picked.flatMap { p in bs.first { cal.isDate($0.date, equalTo: p, toGranularity: unit) } }
        let top = bs.map { max($0.actual ?? 0, $0.forecast ?? 0) }.max() ?? 0
        let scale = EnergyScale(lo: 0, hi: top)
        let domain = chartDomain(r)
        return Chart {
            ForEach(bs) { b in
                if let a = b.actual {
                    BarMark(x: .value("Date", b.date, unit: unit), y: .value("Actual", a), width: bs.count <= 3 ? .fixed(28) : .ratio(0.62))
                        .foregroundStyle(Self.yellow.opacity(sel == nil || sel?.id == b.id ? 1 : 0.35))
                        .cornerRadius(3)
                }
                if let f = b.forecast {
                    RectangleMark(x: .value("Date", b.date, unit: unit), y: .value("Forecast", f), width: bs.count <= 3 ? .fixed(38) : .ratio(0.8), height: 2.5)
                        .foregroundStyle(.white.opacity(sel == nil || sel?.id == b.id ? 1 : 0.4))
                }
            }
            if let s = sel {
                RuleMark(x: .value("Date", s.date, unit: unit))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, alignment: .center, spacing: 6,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        readingBox(s)
                    }
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: scale.domain)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: unit, count: xStride(bs.count))) { _ in
                AxisValueLabel { Text("0").font(.app(size: 11)).foregroundStyle(Color.clear) }   // keeps the room
            }
        }
        .chartBackground { proxy in
            GeometryReader { g in Canvas { ctx, size in drawScale(proxy, g, scale, r, &ctx, size, lines: true) } }
        }
        .chartOverlay { proxy in
            GeometryReader { g in
                ZStack {
                    Canvas { ctx, size in drawScale(proxy, g, scale, r, &ctx, size, lines: false) }
                        .allowsHitTesting(false)
                    Rectangle().fill(Color.clear).contentShape(Rectangle())
                        .simultaneousGesture(gestures(proxy, g, r, bs))
                }
            }
        }
    }

    private func readingBox(_ b: FBucket) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(b.isToday ? (b.forecast.flatMap { f in b.actual.map { a in String(format: "%.0f%% of forecast so far", a / max(f, 0.01) * 100) } } ?? "Today")
                           : (b.diff.map { String(format: "%+.0f%% vs forecast", $0) } ?? "No forecast"))
                .font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Forecast").font(.app(size: 10.5)).foregroundStyle(TeslaDark.rowLabel)
                    Text(b.forecast.map(k) ?? "—").font(.app(size: 12.5, weight: .semibold).monospacedDigit()).fixedSize()
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Actual").font(.app(size: 10.5)).foregroundStyle(Self.yellow)
                    Text(b.actual.map(k) ?? "—").font(.app(size: 12.5, weight: .semibold).monospacedDigit()).fixedSize()
                }
                Text("kWh").font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
            }
        }
        .foregroundStyle(.white)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: true)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(white: 0.21)))
    }

    /// Lines full width; each number just under its line at the right, none on the bottom line; bar labels
    /// centred under their bars.
    private func drawScale(_ proxy: ChartProxy, _ g: GeometryProxy, _ scale: EnergyScale, _ r: PeriodRange,
                           _ ctx: inout GraphicsContext, _ size: CGSize, lines: Bool) {
        guard let anchor = proxy.plotFrame else { return }
        let plot = g[anchor]
        var shadowed = ctx
        shadowed.addFilter(.shadow(color: .black.opacity(0.85), radius: 2))
        if !lines {
            for (d, label) in barLabels(r) {
                guard let px = proxy.position(forX: d) else { continue }
                let t = ctx.resolve(Text(label).font(.app(size: 11)).foregroundColor(TeslaDark.rowLabel))
                ctx.draw(t, at: CGPoint(x: plot.minX + px, y: plot.maxY + 6), anchor: .top)
            }
        }
        var v = scale.domain.lowerBound
        while v <= scale.domain.upperBound + 0.0001 {
            defer { v += scale.step }
            guard let py = proxy.position(forY: v) else { continue }
            let y = plot.minY + py
            let isTop = abs(v - scale.domain.upperBound) < 0.0001
            let isBottom = abs(v - scale.domain.lowerBound) < 0.0001
            if lines {
                var p = Path()
                p.move(to: CGPoint(x: plot.minX, y: y)); p.addLine(to: CGPoint(x: plot.maxX, y: y))
                ctx.stroke(p, with: .color(Color.white.opacity(0.09)), lineWidth: 0.7)
            } else if !isBottom {
                let t = ctx.resolve(Text(scale.label(v, top: isTop, unit: "kWh")).font(.app(size: 10.5)).foregroundColor(TeslaDark.rowLabel))
                shadowed.draw(t, at: CGPoint(x: plot.maxX - 4, y: y + 2), anchor: .topTrailing)
            }
        }
    }

    private func barLabels(_ r: PeriodRange) -> [(Date, String)] {
        var out: [(Date, String)] = []
        let dom = chartDomain(r)
        var d = dom.lowerBound
        var i = 0
        let months = cal.dateComponents([.month], from: dom.lowerBound, to: dom.upperBound).month ?? 0
        while d < dom.upperBound {
            guard let next = cal.date(byAdding: unit, value: 1, to: d) else { break }
            let mid = d.addingTimeInterval(next.timeIntervalSince(d) / 2)
            switch period {
            case .week: out.append((mid, d.formatted(.dateTime.weekday(.narrow))))
            case .month:
                let day = cal.component(.day, from: d)
                if [1, 8, 15, 22, 29].contains(day) { out.append((mid, "\(day)")) }
            case .year: out.append((mid, d.formatted(.dateTime.month(.narrow))))
            case .lifetime:
                let every = months > 24 ? 6 : (months > 12 ? 3 : 1)
                if i % every == 0 { out.append((mid, d.formatted(months > 12 ? .dateTime.month(.abbreviated).year(.twoDigits) : .dateTime.month(.narrow)))) }
            case .day: break
            }
            d = next
            i += 1
        }
        return out
    }

    /// Tap and hold (then move) reads a day; a sideways flick turns the page.
    private func gestures(_ proxy: ChartProxy, _ g: GeometryProxy, _ r: PeriodRange, _ bs: [FBucket]) -> some Gesture {
        let hold = LongPressGesture(minimumDuration: 0.25, maximumDistance: 12).sequenced(before: DragGesture(minimumDistance: 0))
        let flick = DragGesture(minimumDistance: 18)
        return hold.exclusively(before: flick)
            .onChanged { v in
                if case .first(let s) = v, case .second(true, let d?) = s {
                    let x = d.location.x - (proxy.plotFrame.map { g[$0].minX } ?? 0)
                    if let raw = proxy.value(atX: x, as: Date.self),
                       let b = bs.first(where: { cal.isDate($0.date, equalTo: raw, toGranularity: unit) }) {
                        if picked != b.date { picked = b.date }
                    }
                }
            }
            .onEnded { v in
                switch v {
                case .first: picked = nil
                case .second(let d):
                    let w = d.translation.width, h = d.translation.height
                    guard abs(w) > 50, abs(w) > abs(h) * 1.4 else { return }
                    step(w < 0 ? 1 : -1, r)
                }
            }
    }

    /// Whole months for Year and Lifetime, so a month's bar sits inside the chart.
    private func chartDomain(_ r: PeriodRange) -> ClosedRange<Date> {
        guard byMonth else { return r.start...r.end }
        let s = cal.dateInterval(of: .month, for: r.start)?.start ?? r.start
        let e = cal.dateInterval(of: .month, for: r.end.addingTimeInterval(-1))?.end ?? r.end
        return s...e
    }

    private func xStride(_ n: Int) -> Int {
        switch period {
        case .month: return 7
        case .lifetime: return n > 12 ? 3 : 1
        default: return 1
        }
    }

    /// Bordered table like the Energy Flow tables.
    private func table(_ bs: [FBucket]) -> some View {
        let rows = Array(bs.filter { $0.forecast != nil || $0.actual != nil }.reversed())
        let border = Color(white: 0.24)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(byMonth ? "Every Month" : "Every Day").font(.app(size: 14, weight: .semibold))
                Spacer()
                Text("FORECAST").frame(width: 70, alignment: .trailing)
                Text("ACTUAL").frame(width: 62, alignment: .trailing)
                Color.clear.frame(width: 84)
            }
            .font(.app(size: 9.5, weight: .medium))
            .foregroundStyle(TeslaDark.rowLabel)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, b in
                    if i > 0 { Rectangle().fill(border).frame(height: 1) }
                    HStack {
                        Text(rowTitle(b.date)).font(.app(size: 14.5))
                        Spacer()
                        Text(b.forecast.map(k) ?? "—").foregroundStyle(TeslaDark.rowLabel).frame(width: 70, alignment: .trailing)
                        Text(b.actual.map(k) ?? "—").frame(width: 62, alignment: .trailing)
                        Group {
                            if b.isToday, let f = b.forecast, let a = b.actual, f > 0 {
                                pill("\(String(format: "%.0f", a / f * 100))% so far", TeslaDark.rowLabel)
                            } else if let p = b.diff {
                                pill(String(format: "%+.0f%%", p), forecastDiffColor(p), bold: true)
                            } else {
                                Text("—").foregroundStyle(TeslaDark.rowLabel)
                            }
                        }
                        .frame(width: 84, alignment: .trailing)
                    }
                    .font(.app(size: 14.5))
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(border, lineWidth: 1))
        }
    }

    private func pill(_ t: String, _ c: Color, bold: Bool = false) -> some View {
        Text(t).font(.app(size: 12, weight: bold ? .semibold : .regular)).foregroundStyle(c)
            .lineLimit(1).minimumScaleFactor(0.8)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(c == TeslaDark.rowLabel ? Color(white: 0.2) : c.opacity(0.16)))
    }

    private func rowTitle(_ d: Date) -> String {
        if byMonth {
            let s = d.formatted(.dateTime.month(.abbreviated).year())
            return cal.isDate(d, equalTo: Date(), toGranularity: .month) ? s + " (so far)" : s
        }
        if cal.isDateInToday(d) { return "Today" }
        return d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    private func dayCard(_ day: Date) -> some View {
        let f = log.forecast(day) ?? (cal.isDateInToday(day) ? model.forecastToday : nil)
        let a = actual(day)
        let scale = max(f ?? 0, a ?? 0, 1) * 1.1
        return cardBox {
            Text(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased())
                .font(.app(size: 10, weight: .medium)).kerning(0.6).foregroundStyle(TeslaDark.rowLabel)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Forecast").font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                    Text(f.map { "\(k($0)) kWh" } ?? "—").font(.app(size: 28, weight: .semibold))
                    if log.forecast(day) != nil {
                        Text(sourceLine(day)).font(.app(size: 11)).foregroundStyle(TeslaDark.rowLabel)
                    }
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text(cal.isDateInToday(day) ? "Actual so far" : "Actual").font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                    Text(a.map { "\(k($0)) kWh" } ?? "—").font(.app(size: 28, weight: .semibold)).foregroundStyle(Self.yellow)
                }
                Spacer()
            }
            .padding(.top, 12)
            if cal.isDateInToday(day), let f, let a, f > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(String(format: "%.0f%%", a / f * 100)).font(.app(size: 22, weight: .semibold)).foregroundStyle(TeslaDark.rowLabel)
                    Text("of today's forecast so far").font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                }
                .padding(.top, 14)
            } else if let f, let a, f > 0 {
                let p = (a - f) / f * 100
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(String(format: "%+.0f%%", p)).font(.app(size: 22, weight: .semibold)).foregroundStyle(forecastDiffColor(p))
                    Text("actual came \(k(abs(a - f))) kWh \(a < f ? "lower" : "higher")").font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                }
                .padding(.top, 14)
            }
            VStack(spacing: 8) {
                bar(f ?? 0, scale, .white)
                bar(a ?? 0, scale, Self.yellow)
            }
            .padding(.top, 14)
            if cal.isDateInToday(day), SolarSensors.current.isSolcast, let latest = model.forecastToday {
                Rectangle().fill(Color(white: 0.22)).frame(height: 0.7).padding(.top, 14)
                HStack(alignment: .center) {
                    Text("Latest from Solcast").font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(k(latest)) kWh").font(.app(size: 13, weight: .semibold))
                        Text(latestLine).font(.app(size: 10)).foregroundStyle(TeslaDark.rowLabel)
                    }
                }
                .padding(.top, 10)
            }
        }
    }

    private func hm(_ d: Date) -> String { d.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) }

    private func sourceLine(_ day: Date) -> String {
        guard log.isSolcast(day) else { return "Forecast.Solar" }
        return log.readTime(day).map { "Solcast · first read \(hm($0))" } ?? "Solcast"
    }

    private var latestLine: String {
        var parts: [String] = []
        if let r = model.forecastReadAt { parts.append("read \(hm(r))") }
        if let n = model.forecastNextRead {
            parts.append(cal.isDateInToday(n) ? "next ~\(hm(n))" : "next tomorrow ~\(hm(n))")
        }
        return parts.joined(separator: " · ")
    }

    private func bar(_ v: Double, _ scale: Double, _ c: Color) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(white: 0.22))
                Capsule().fill(c).frame(width: g.size.width * min(v / scale, 1))
            }
        }
        .frame(height: 12)
    }
}
