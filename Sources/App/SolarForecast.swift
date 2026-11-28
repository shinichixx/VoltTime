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

// MARK: - Solar Forecast card (Impact)

struct FBucket: Identifiable {
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

/// A period's bars and totals, added up once and kept until the saved energy or forecasts change.
struct ForecastNumbers {
    var buckets: [FBucket] = []
    var typicalMiss: Double? = nil   // average size of the daily difference (finished days only)
}

/// Grey within ±10 %, green when the sun beat the forecast, amber 10–30 % short, red beyond.
func forecastDiffColor(_ p: Double) -> Color {
    if abs(p) <= 10 { return TeslaDark.rowLabel }
    if p > 0 { return TeslaDark.exporting }
    return p < -30 ? CarColors.red : CarColors.amber
}

extension EnergyStore {
    /// One bucket per day (Week, Month) or per month (Year, Lifetime).
    func forecastNumbers(_ r: PeriodRange, byMonth: Bool) -> ForecastNumbers {
        let cal = Calendar.current
        let log = SolarForecastLog.shared
        let todayStart = cal.startOfDay(for: Date())
        let key = "\(byMonth)|\(r.start.timeIntervalSince1970)|\(r.end.timeIntervalSince1970)|\(todayStart.timeIntervalSince1970)|\(log.days.count)"
        if let n = forecastCache[key] { return n }
        var out = ForecastNumbers()
        var miss = 0.0, missDays = 0
        let todayEnd = cal.date(byAdding: .day, value: 1, to: todayStart) ?? Date()
        var d = byMonth ? (cal.dateInterval(of: .month, for: r.start)?.start ?? r.start) : r.start
        while d < r.end {
            guard let next = cal.date(byAdding: byMonth ? .month : .day, value: 1, to: d) else { break }
            var f = 0.0, a = 0.0, m = 0.0, anyF = false, anyA = false
            var x = max(d, cal.startOfDay(for: r.start))
            while x < min(next, r.end, todayEnd) {
                let ax = flow(x)?.solar
                if let ax { a += ax; anyA = true }
                if let fx = log.forecast(x) {
                    f += fx; m += ax ?? 0; anyF = true
                    if x < todayStart, fx > 0, let ax { miss += abs(ax - fx) / fx * 100; missDays += 1 }
                }
                guard let n = cal.date(byAdding: .day, value: 1, to: x) else { break }
                x = n
            }
            var b = FBucket(date: d, forecast: anyF ? f : nil, actual: anyA ? a : nil)
            b.matchedActual = anyF ? m : nil
            b.isToday = !byMonth && cal.isDate(d, inSameDayAs: todayStart)
            out.buckets.append(b)
            d = next
        }
        out.typicalMiss = missDays > 0 ? miss / Double(missDays) : nil
        forecastCache[key] = out
        return out
    }
}

/// Follows the Impact page's period: today shows the forecast curve, a past day two bars, longer periods
/// the actual bars with white forecast marks.
struct SolarForecastCard: View {
    @ObservedObject var model: EnergyStore
    let period: ImpactPeriod
    let range: PeriodRange
    @ObservedObject private var log = SolarForecastLog.shared
    @State private var picked: Int?
    @State private var showInfo = false

    private let cal = Calendar.current
    private static let yellow = Color(red: 1, green: 0.8, blue: 0.2)

    private var singleDay: Bool {
        period == .day || (period == .custom && range.end.timeIntervalSince(range.start) <= 90_000)
    }
    private var byMonth: Bool {
        period == .year || period == .lifetime || (period == .custom && range.end.timeIntervalSince(range.start) > 62 * 86_400)
    }
    private var isToday: Bool { singleDay && cal.isDateInToday(range.start) }

    private var source: String {
        let solcastNow = SolarSensors.current.isSolcast
        if isToday { return solcastNow ? "Solcast" : "Forecast.Solar" }
        guard let since = log.solcastSince else { return "Forecast.Solar" }
        return (singleDay ? range.start >= since : range.end > since) ? "Solcast" : "Forecast.Solar"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("Solar Forecast").font(.app(size: 14, weight: .semibold))
                Text(source).font(.app(size: 10, weight: .medium)).foregroundStyle(Color(white: 0.8))
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Capsule().fill(Color(white: 0.22)))
                Spacer(minLength: 0)
                Button { withAnimation { showInfo.toggle() } } label: {
                    Image(systemName: "info.circle").font(.system(size: 16))
                }
                .buttonStyle(.plain).foregroundStyle(TeslaDark.labelGrey)
            }
            if isToday { today }
            else if singleDay { pastDay(range.start) }
            else { longer }
            if showInfo {
                Text("Forecast from Solcast (older days: Forecast.Solar).\nActual = solar your inverter generated.\n% = (actual − forecast) ÷ forecast.")
                    .font(.app(size: 11)).foregroundStyle(TeslaDark.dim)
                    .padding(.top, 12)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TeslaDark.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Today

    private var today: some View {
        let morning = log.forecast(range.start)
        return VStack(alignment: .leading, spacing: 0) {
            bigNumber(model.forecastToday.map { Num.one($0) } ?? "—").padding(.top, 8)
            if SolarSensors.current.isSolcast, !readLine.isEmpty {
                Text(readLine).font(.app(size: 11)).foregroundStyle(TeslaDark.rowLabel).padding(.top, 2)
            }
            ForecastCurveView(today: model.forecastCurveToday, tomorrow: model.forecastCurveTomorrow,
                              todayKWh: model.forecastToday, tomorrowKWh: model.forecastTomorrow,
                              peakToday: model.peakToday, peakTomorrow: model.peakTomorrow)
                .frame(height: 150)
                .padding(.top, 14)
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Capsule().fill(Self.yellow).frame(width: 14, height: 2)
                    Text(SolarSensors.current.isSolcast ? "Today, hourly Solcast" : "Today")
                }
                HStack(spacing: 6) {
                    HStack(spacing: 2) { ForEach(0..<3, id: \.self) { _ in Capsule().fill(Color(white: 0.45)).frame(width: 3, height: 1.5) } }
                    Text("Tomorrow")
                }
            }
            .font(.app(size: 9)).foregroundStyle(TeslaDark.rowLabel)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            divider.padding(.top, 14)
            footRow("Morning forecast",
                    morning == nil ? "Not saved yet" : (log.isSolcast(range.start) ? log.readTime(range.start).map { "Set \(hm($0))" } : nil),
                    morning)
            divider.padding(.top, 12)
            footRow("Tomorrow", model.peakTomorrow.map { "Peak \(hm($0))" }, model.forecastTomorrow)
        }
    }

    private var readLine: String {
        var parts: [String] = []
        if let r = model.forecastReadAt { parts.append("Read \(hm(r))") }
        if let n = model.forecastNextRead { parts.append("next \(hm(n))") }
        return parts.joined(separator: " · ")
    }

    private func footRow(_ name: String, _ note: String?, _ v: Double?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.app(size: 12))
                if let note { Text(note).font(.app(size: 10)).foregroundStyle(TeslaDark.rowLabel) }
            }
            Spacer()
            Text(v.map { Num.one($0) + " kWh" } ?? "—").font(.app(size: 13, weight: .semibold))
        }
        .padding(.top, 12)
    }

    // MARK: A past day

    private func pastDay(_ day: Date) -> some View {
        let f = log.forecast(day)
        let a = model.flow(day)?.solar
        let top = max(f ?? 0, a ?? 0, 1) * 1.1
        return VStack(alignment: .leading, spacing: 0) {
            bigNumber(a.map { Num.one($0) } ?? "—").padding(.top, 8)
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Forecast").font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                    Text(f.map { Num.one($0) + " kWh" } ?? "—").font(.app(size: 24, weight: .semibold))
                    if f != nil, log.isSolcast(day), let t = log.readTime(day) {
                        Text("Set \(hm(t))").font(.app(size: 11)).foregroundStyle(TeslaDark.rowLabel)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Actual").font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                    Text(a.map { Num.one($0) + " kWh" } ?? "—").font(.app(size: 24, weight: .semibold)).foregroundStyle(Self.yellow)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 14)
            if let f, let a, f > 0 {
                let p = (a - f) / f * 100
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(String(format: "%+.0f%%", p)).font(.app(size: 22, weight: .semibold)).foregroundStyle(forecastDiffColor(p))
                    Text("actual came \(Num.one(abs(a - f))) kWh \(a < f ? "lower" : "higher")")
                        .font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                }
                .padding(.top, 14)
            } else if f == nil {
                Text("No forecast saved for this day").font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel).padding(.top, 14)
            }
            bar("Forecast", f, top, .white).padding(.top, 16)
            bar("Actual", a, top, Self.yellow).padding(.top, 12)
        }
    }

    private func bar(_ name: String, _ v: Double?, _ top: Double, _ c: Color) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(name).foregroundStyle(TeslaDark.rowLabel)
                Spacer()
                Text(v.map { Num.one($0) } ?? "—")
            }
            .font(.app(size: 11))
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(white: 0.22))
                    if let v, v > 0 { Capsule().fill(c).frame(width: g.size.width * min(v / top, 1)) }
                }
            }
            .frame(height: 12)
        }
    }

    // MARK: Week, Month, Year, Lifetime

    private var longer: some View {
        let n = model.forecastNumbers(range, byMonth: byMonth)
        let bs = n.buckets
        let sel = picked.flatMap { bs.indices.contains($0) ? bs[$0] : nil }
        let f = bs.compactMap(\.forecast).reduce(0, +)
        let a = bs.compactMap(\.actual).reduce(0, +)
        let m = bs.compactMap(\.matchedActual).reduce(0, +)
        let big: Double? = sel.map { $0.actual } ?? (bs.contains { $0.actual != nil } ? a : nil)
        let line: String
        if let s = sel {
            let name = byMonth ? s.date.formatted(.dateTime.month(.abbreviated).year())
                : (s.isToday ? "Today" : s.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
            let diff = s.isToday
                ? (s.forecast.flatMap { x in s.actual.map { String(format: "%.0f%% so far", $0 / max(x, 0.01) * 100) } })
                : s.diff.map { String(format: "%+.0f%%", $0) }
            line = [name, s.forecast.map { "Forecast \(k($0)) kWh" } ?? "No forecast", diff].compactMap { $0 }.joined(separator: " · ")
        } else if f > 0 {
            let p = (m - f) / f * 100
            line = "Forecast \(k(f)) kWh · \(String(format: "%.0f", abs(p)))% \(p < 0 ? "lower" : "higher") than forecast"
        } else {
            line = "No forecast saved for these days yet"
        }
        return VStack(alignment: .leading, spacing: 0) {
            bigNumber(big.map { k($0) } ?? "—").padding(.top, 8)
            Text(line).font(.app(size: 11)).foregroundStyle(TeslaDark.rowLabel)
                .lineLimit(1).minimumScaleFactor(0.75)
                .padding(.top, 2)
            ForecastBars(buckets: bs, labels: labels(bs), picked: picked)
                .equatable()
                .frame(height: 176)
                .overlay {
                    GeometryReader { g in
                        Color.clear.contentShape(Rectangle())
                            .holdToRead { x in
                                guard let x, !bs.isEmpty else { picked = nil; return }
                                let i = min(max(Int(x / max(g.size.width, 1) * CGFloat(bs.count)), 0), bs.count - 1)
                                if picked != i { picked = i }
                            }
                    }
                }
                .padding(.top, 16)
            HStack(spacing: 18) {
                HStack(spacing: 5) { Circle().fill(Self.yellow).frame(width: 8, height: 8); Text("Actual") }
                HStack(spacing: 5) { Capsule().fill(.white).frame(width: 14, height: 2.5); Text("Forecast") }
            }
            .font(.app(size: 10)).foregroundStyle(TeslaDark.rowLabel)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            if let miss = n.typicalMiss {
                Text("Typical miss ±\(String(format: "%.0f", miss))%")
                    .font(.app(size: 11)).foregroundStyle(TeslaDark.rowLabel)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
            }
        }
    }

    /// Which bars are named underneath.
    private func labels(_ bs: [FBucket]) -> [String?] {
        let n = bs.count
        return bs.enumerated().map { i, b in
            if byMonth {
                if n <= 12 { return String(b.date.formatted(.dateTime.month(.narrow))) }
                return i % max(n / 4, 1) == 0 ? b.date.formatted(.dateTime.month(.abbreviated).year(.twoDigits)) : nil
            }
            if period == .week { return String(b.date.formatted(.dateTime.weekday(.narrow))) }
            return n <= 7 || i % 7 == 0 ? "\(cal.component(.day, from: b.date))" : nil
        }
    }

    // MARK: Pieces

    private func k(_ v: Double) -> String { Num.kwh(v, whole: v >= 100) }
    private func hm(_ d: Date) -> String { d.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) }
    private var divider: some View { Rectangle().fill(Color.white.opacity(0.09)).frame(height: 0.5) }

    private func bigNumber(_ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value).font(.app(size: 38, weight: .medium)).foregroundStyle(Self.yellow)
            Text("kWh").font(.app(size: 13)).foregroundStyle(TeslaDark.rowLabel)
        }
    }
}

/// Actual as yellow bars, the forecast as a white mark over each; drawn in one pass so scrolling stays light.
private struct ForecastBars: View, Equatable {
    let buckets: [FBucket]
    let labels: [String?]
    let picked: Int?

    static func == (a: Self, b: Self) -> Bool {
        a.picked == b.picked && a.labels == b.labels && a.buckets.count == b.buckets.count
            && zip(a.buckets, b.buckets).allSatisfy { $0.date == $1.date && $0.actual == $1.actual && $0.forecast == $1.forecast }
    }

    var body: some View {
        Canvas { ctx, size in
            let n = buckets.count
            guard n > 0 else { return }
            let top = buckets.map { max($0.actual ?? 0, $0.forecast ?? 0) }.max() ?? 0
            let scale = EnergyScale(lo: 0, hi: top)
            let lo = scale.domain.lowerBound, hi = scale.domain.upperBound
            let plotH = size.height - 18
            func y(_ v: Double) -> CGFloat { plotH * CGFloat(1 - (v - lo) / max(hi - lo, 0.0001)) + 1 }
            var v = lo
            while v <= hi + 0.0001 {
                ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y(v))); $0.addLine(to: CGPoint(x: size.width, y: y(v))) },
                           with: .color(Color.white.opacity(0.09)), lineWidth: 0.7)
                v += scale.step
            }
            let slot = size.width / CGFloat(n)
            let w = min(slot * 0.66, 26)
            for (i, b) in buckets.enumerated() {
                let x = slot * (CGFloat(i) + 0.5)
                let dim = picked != nil && picked != i
                if let a = b.actual, a > 0 {
                    let h = max(y(lo) - y(a), 1.5)
                    ctx.fill(Path(roundedRect: CGRect(x: x - w / 2, y: y(lo) - h, width: w, height: h), cornerRadius: min(w / 2, 3)),
                             with: .color(Color(red: 1, green: 0.8, blue: 0.2).opacity(dim ? 0.35 : 1)))
                }
                if let f = b.forecast {
                    let fw = min(slot * 0.86, 34)
                    ctx.fill(Path(CGRect(x: x - fw / 2, y: y(f) - 1.25, width: fw, height: 2.5)),
                             with: .color(.white.opacity(dim ? 0.4 : 1)))
                }
                if i < labels.count, let l = labels[i] {
                    let t = ctx.resolve(Text(l).font(.app(size: 10)).foregroundColor(TeslaDark.rowLabel))
                    let half = t.measure(in: size).width / 2
                    ctx.draw(t, at: CGPoint(x: min(max(x, half), size.width - half), y: plotH + 6), anchor: .top)
                }
            }
            v = lo + scale.step
            while v <= hi + 0.0001 {
                let t = ctx.resolve(Text(scale.label(v, top: v + scale.step > hi + 0.0001, unit: "kWh"))
                    .font(.app(size: 9.5)).foregroundColor(TeslaDark.rowLabel))
                ctx.drawGlowing(t, at: CGPoint(x: size.width - 2, y: y(v) + 2), anchor: .topTrailing)
                v += scale.step
            }
        }
    }
}
