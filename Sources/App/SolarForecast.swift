import SwiftUI
import Charts

// Build 54: one solar forecast a day, kept forever, to set against what the inverter actually made.

/// Each day's forecast (kWh), as Forecast.Solar gave it before sunrise that day.
@MainActor
final class SolarForecastLog: ObservableObject {
    static let shared = SolarForecastLog()
    nonisolated static var file: URL { AppData.support.appendingPathComponent("solar-forecast.json") }
    static let todaySensor = "sensor.energy_production_today"
    private static let checkedKey = "forecastLog.checked"

    @Published private(set) var days: [String: Double] = [:]

    private init() {
        if let d = try? Data(contentsOf: Self.file), let v = try? JSONDecoder().decode([String: Double].self, from: d) { days = v }
    }

    var firstDay: Date? { days.keys.min().flatMap { EnergyStore.keyFormatter.date(from: $0) } }

    func forecast(_ day: Date) -> Double? { days[EnergyStore.keyFormatter.string(from: day)] }

    private func save() {
        try? FileManager.default.createDirectory(at: AppData.support, withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(days) { try? d.write(to: Self.file, options: .atomic) }
    }

    /// Reads Home Assistant's history of today's-forecast sensor (it keeps about 10 days) and fills in any day not
    /// yet recorded. A day's forecast is the last value before 06:00 (before any sun), else the day's first value.
    /// At most once an hour.
    func update(_ ha: HAClient) async {
        let d = UserDefaults.standard
        if let last = d.object(forKey: Self.checkedKey) as? Date, Date().timeIntervalSince(last) < 3600 { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let since = cal.date(byAdding: .day, value: -10, to: today),
              let h = try? await ha.history([Self.todaySensor], since: since),
              let pts = h[Self.todaySensor], !pts.isEmpty else { return }
        d.set(Date(), forKey: Self.checkedKey)
        var day = since
        var changed = false
        while day <= today {
            let k = EnergyStore.keyFormatter.string(from: day)
            let six = day.addingTimeInterval(6 * 3600)
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            let early = pts.last { $0.0 >= day && $0.0 <= six }
            let carried = pts.last { $0.0 < day }        // value still showing at midnight, if it was updated after
            let first = pts.first { $0.0 >= day && $0.0 < next }
            let still = day == today && Date() < six    // today's value can still be updated until 06:00
            if days[k] == nil || still, let v = (early ?? first)?.1 ?? (still ? carried?.1 : nil), v > 0 {
                if days[k] != v { days[k] = v; changed = true }
            }
            day = next
        }
        if changed { save() }
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
    let forecast: Double?
    let actual: Double?
    var id: Date { date }
    var diff: Double? {
        guard let f = forecast, let a = actual, f > 0 else { return nil }
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

    private let cal = Calendar.current
    private var period: ImpactPeriod { ImpactPeriod(rawValue: periodRaw) ?? .month }
    private var byMonth: Bool { period == .year || period == .lifetime }
    private static let yellow = Color(red: 1, green: 0.8, blue: 0.2)

    var body: some View {
        let r = PeriodRange.make(period, offset: offset, firstDay: log.firstDay)
        let bs = buckets(r)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                PeriodBar(range: r, period: period, firstDay: log.firstDay, offset: $offset)
                if log.days.isEmpty {
                    Text("No forecast saved yet. TesLah records one each day from Home Assistant, starting today.")
                        .font(.app(size: 13)).foregroundStyle(TeslaDark.rowLabel)
                        .frame(maxWidth: .infinity, minHeight: 160)
                        .multilineTextAlignment(.center)
                } else if period == .day {
                    dayCard(r.start)
                } else {
                    summary(r, bs)
                    chart(r, bs)
                    table(bs)
                }
                Text("Forecast = what Forecast.Solar said for that day before sunrise. Actual = the inverter's total for the day; today shows the total so far.")
                    .font(.app(size: 11)).foregroundStyle(TeslaDark.dim)
                    .padding(.top, 6).padding(.horizontal, 4)
            }
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .teslaPage("Forecast vs actual")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { PeriodMenu(periodRaw: $periodRaw, offset: $offset) } }
        .onChange(of: periodRaw) { _, _ in picked = nil }
        .onChange(of: offset) { _, _ in picked = nil }
    }

    // MARK: Data

    private func actual(_ day: Date) -> Double? { model.flow(day)?.solar }

    /// One bucket per day (Week, Month) or per month (Year, Lifetime). Only days with a saved forecast count.
    private func buckets(_ r: PeriodRange) -> [FBucket] {
        var out: [FBucket] = []
        let todayEnd = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date()
        var d = r.start
        while d < r.end {
            let next = cal.date(byAdding: byMonth ? .month : .day, value: 1, to: d) ?? r.end
            var f = 0.0, a = 0.0, any = false
            var x = d
            while x < min(next, r.end, todayEnd) {
                if let fx = log.forecast(x) {
                    f += fx; a += actual(x) ?? 0; any = true
                }
                x = cal.date(byAdding: .day, value: 1, to: x) ?? next
            }
            out.append(FBucket(date: d, forecast: any ? f : nil, actual: any ? a : nil))
            d = byMonth ? (cal.dateInterval(of: .month, for: next)?.start ?? next) : next
        }
        return out
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

    private func k(_ v: Double) -> String { v >= 100 ? String(format: "%.0f", v) : String(format: "%.1f", v) }

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
        let p = f > 0 ? (a - f) / f * 100 : 0
        return cardBox {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summaryLabel(r)).font(.app(size: 10, weight: .medium)).kerning(0.6).foregroundStyle(TeslaDark.rowLabel)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(k(a)) kWh").font(.app(size: 28, weight: .semibold))
                        Text("actual").font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                    }
                    Text(f > 0 ? "Forecast \(k(f)) kWh · actual came \(String(format: "%.0f", abs(p)))% \(p < 0 ? "lower" : "higher")"
                               : "No forecast saved for this period")
                        .font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                }
                Spacer()
                if let m = typicalMiss(r) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("±\(String(format: "%.0f", m))%").font(.app(size: 22, weight: .semibold))
                        Text("typical miss").font(.app(size: 11)).foregroundStyle(TeslaDark.rowLabel)
                    }
                    .padding(.top, 14)
                }
            }
        }
    }

    private func chart(_ r: PeriodRange, _ bs: [FBucket]) -> some View {
        let unit: Calendar.Component = byMonth ? .month : .day
        let sel = picked.flatMap { p in bs.first { cal.isDate($0.date, equalTo: p, toGranularity: unit) } }
        return cardBox {
            HStack(spacing: 14) {
                HStack(spacing: 5) { RoundedRectangle(cornerRadius: 2).fill(Self.yellow).frame(width: 11, height: 8); Text("Actual") }
                HStack(spacing: 5) { Capsule().fill(.white).frame(width: 14, height: 2.5); Text("Forecast") }
                Spacer()
                if let s = sel, let f = s.forecast, let a = s.actual {
                    Text("\(byMonth ? s.date.formatted(.dateTime.month(.abbreviated).year()) : s.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) · \(k(f)) → \(k(a)) kWh")
                        .foregroundStyle(.white)
                } else {
                    Text("Press and slide")
                }
            }
            .font(.app(size: 11)).foregroundStyle(TeslaDark.rowLabel)
            .padding(.bottom, 12)
            Chart {
                ForEach(bs) { b in
                    if let a = b.actual {
                        BarMark(x: .value("Date", b.date, unit: unit), y: .value("Actual", a), width: .ratio(0.62))
                            .foregroundStyle(Self.yellow.opacity(sel == nil || sel?.id == b.id ? 1 : 0.35))
                            .cornerRadius(3)
                    }
                    if let f = b.forecast {
                        RectangleMark(x: .value("Date", b.date, unit: unit), y: .value("Forecast", f), width: .ratio(0.8), height: 2.5)
                            .foregroundStyle(.white)
                    }
                }
            }
            .chartXScale(domain: r.start...r.end)
            .chartXSelection(value: $picked)
            .chartYAxis {
                AxisMarks(position: .trailing) { _ in
                    AxisGridLine().foregroundStyle(Color(white: 0.25))
                    AxisValueLabel().font(.app(size: 9)).foregroundStyle(TeslaDark.rowLabel)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: unit, count: xStride(bs.count))) { v in
                    AxisValueLabel {
                        if let d = v.as(Date.self) { Text(xLabel(d)).font(.app(size: 10)).foregroundStyle(TeslaDark.rowLabel) }
                    }
                }
            }
            .frame(height: 200)
        }
    }

    private func xStride(_ n: Int) -> Int {
        switch period {
        case .month: return 7
        case .lifetime: return n > 12 ? 3 : 1
        default: return 1
        }
    }

    private func xLabel(_ d: Date) -> String {
        switch period {
        case .week: return String(d.formatted(.dateTime.weekday(.narrow)))
        case .month: return d.formatted(.dateTime.day())
        case .year: return String(d.formatted(.dateTime.month(.narrow)))
        default: return d.formatted(.dateTime.month(.abbreviated))
        }
    }

    private func table(_ bs: [FBucket]) -> some View {
        let rows = bs.filter { $0.forecast != nil }.reversed()
        return VStack(spacing: 0) {
            HStack {
                Text(byMonth ? "EVERY MONTH" : "EVERY DAY").font(.app(size: 11, weight: .medium)).kerning(0.6)
                Spacer()
                Text("FORECAST").frame(width: 70, alignment: .trailing)
                Text("ACTUAL").frame(width: 62, alignment: .trailing)
                Text("DIFF").frame(width: 56, alignment: .trailing)
            }
            .font(.app(size: 9, weight: .medium)).foregroundStyle(TeslaDark.rowLabel)
            .padding(.top, 16).padding(.bottom, 6)
            ForEach(Array(rows)) { b in
                Rectangle().fill(Color(white: 0.2)).frame(height: 0.5)
                HStack {
                    Text(rowTitle(b.date)).font(.app(size: 14))
                    Spacer()
                    Text(b.forecast.map(k) ?? "—").foregroundStyle(TeslaDark.rowLabel).frame(width: 70, alignment: .trailing)
                    Text(b.actual.map(k) ?? "—").frame(width: 62, alignment: .trailing)
                    Text(b.diff.map { String(format: "%+.0f%%", $0) } ?? "—")
                        .foregroundStyle(b.diff.map(forecastDiffColor) ?? TeslaDark.rowLabel)
                        .frame(width: 56, alignment: .trailing)
                }
                .font(.app(size: 14))
                .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 4)
    }

    private func rowTitle(_ d: Date) -> String {
        if byMonth {
            let s = d.formatted(.dateTime.month(.abbreviated).year())
            return cal.isDate(d, equalTo: Date(), toGranularity: .month) ? s + " (so far)" : s
        }
        let s = d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        return cal.isDateInToday(d) ? s + " (today)" : s
    }

    private func dayCard(_ day: Date) -> some View {
        let f = log.forecast(day)
        let a = actual(day)
        let scale = max(f ?? 0, a ?? 0, 1) * 1.1
        return cardBox {
            Text(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased())
                .font(.app(size: 10, weight: .medium)).kerning(0.6).foregroundStyle(TeslaDark.rowLabel)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Forecast").font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                    Text(f.map { "\(k($0)) kWh" } ?? "—").font(.app(size: 28, weight: .semibold))
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text(cal.isDateInToday(day) ? "Actual so far" : "Actual").font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                    Text(a.map { "\(k($0)) kWh" } ?? "—").font(.app(size: 28, weight: .semibold)).foregroundStyle(Self.yellow)
                }
                Spacer()
            }
            .padding(.top, 12)
            if let f, let a, f > 0 {
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
        }
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
