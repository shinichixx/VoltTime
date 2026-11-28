import SwiftUI

// Energy Value (Impact): what the solar saved on the TNB bill, an estimate.
// - Solar used at home or by the car: priced at the ToU rate of the time it was used
//   (peak Mon–Fri 14:00–22:00, off-peak the rest of the week).
// - Solar exported: NEM 3.0 offsets it against the month's import, off-peak kWh first (off-peak rate),
//   then peak kWh (peak rate). Each day gets the month's credit in proportion to what it exported.

enum Tariff {
    static let peakKey = "tariff.peak"
    static let offPeakKey = "tariff.offPeak"
    static let peakDefault = 0.5429
    static let offPeakDefault = 0.4981

    static var peak: Double { let v = UserDefaults.standard.double(forKey: peakKey); return v > 0 ? v : peakDefault }
    static var offPeak: Double { let v = UserDefaults.standard.double(forKey: offPeakKey); return v > 0 ? v : offPeakDefault }
    static var stamp: String { "\(peak)-\(offPeak)" }

    /// Saturday and Sunday, whatever the phone's region calls the weekend.
    static func isWeekend(_ day: Date) -> Bool {
        let wd = Calendar.current.component(.weekday, from: day)
        return wd == 1 || wd == 7
    }

    /// Peak is Mon–Fri 14:00–22:00; `minute` counts from midnight.
    static func isPeak(minute: Int, weekend: Bool) -> Bool {
        !weekend && minute >= 14 * 60 && minute < 22 * 60
    }
}

/// One day: solar-used value (RM) and export (kWh) per hour, plus the off-peak import (kWh).
struct DayValue {
    var selfRM = [Double](repeating: 0, count: 24)
    var exp = [Double](repeating: 0, count: 24)
    var offImp = 0.0
}

@MainActor
enum ValueBook {
    static var days: [String: DayValue] = [:]
    static var months: [String: Double] = [:]   // RM per exported kWh
}

extension EnergyStore {
    func dayValue(_ day: Date) -> DayValue? {
        guard let c = curve(day) else { return nil }
        let cal = Calendar.current
        let today = cal.isDateInToday(day)
        let ck = "\(Self.keyFormatter.string(from: day))|\(c.minutes)|\(Tariff.stamp)"
        if let v = today ? liveDays[ck] : ValueBook.days[ck] { return v }
        var v = DayValue()
        let start = cal.startOfDay(for: day)
        let peak = Tariff.peak, off = Tariff.offPeak
        let weekend = Tariff.isWeekend(start)
        let fs = c.flows
        for i in 0..<c.count {
            let isPeak = Tariff.isPeak(minute: i * c.minutes, weekend: weekend)
            let f = fs[i]
            let h = min(23, i * c.minutes / 60)
            v.selfRM[h] += (f.carSolar + f.homeSolar) * (isPeak ? peak : off)
            v.exp[h] += f.exp
            if !isPeak { v.offImp += f.imp }
        }
        if today { liveDays[ck] = v } else { ValueBook.days[ck] = v }
        return v
    }

    /// RM per exported kWh in the month holding `day`.
    func exportRate(_ day: Date) -> Double {
        let cal = Calendar.current
        guard let iv = cal.dateInterval(of: .month, for: day) else { return Tariff.offPeak }
        let current = iv.contains(Date())
        let ck = "\(Self.keyFormatter.string(from: iv.start))|\(Tariff.stamp)"
        if let r = current ? liveMonths[ck] : ValueBook.months[ck] { return r }
        var exp = 0.0, offImp = 0.0
        var d = iv.start
        while d < iv.end {
            if let v = dayValue(d) { exp += v.exp.reduce(0, +); offImp += v.offImp }
            guard let n = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = n
        }
        let credit = min(exp, offImp) * Tariff.offPeak + max(exp - offImp, 0) * Tariff.peak
        let r = exp > 0 ? credit / exp : Tariff.offPeak
        if current { liveMonths[ck] = r } else { ValueBook.months[ck] = r }
        return r
    }

    func value(day: Date) -> Double {
        guard let v = dayValue(day) else { return 0 }
        return v.selfRM.reduce(0, +) + v.exp.reduce(0, +) * exportRate(day)
    }

    func value(from start: Date, to end: Date) -> Double {
        let cal = Calendar.current
        var t = 0.0
        var d = cal.startOfDay(for: start)
        while d < end {
            t += value(day: d)
            guard let n = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = n
        }
        return t
    }

    /// Bars for the Energy Value card: hours (Day), days (Week, Month), months (Year, Lifetime).
    func valueBars(_ period: ImpactPeriod, _ r: PeriodRange) -> (values: [Double], labels: [String?]) {
        let cal = Calendar.current
        switch period {
        case .day:
            guard let v = dayValue(r.start) else { return (Array(repeating: 0, count: 24), Self.hourLabels) }
            let rate = exportRate(r.start)
            return ((0..<24).map { v.selfRM[$0] + v.exp[$0] * rate }, Self.hourLabels)
        case .week, .month:
            var vals: [Double] = []
            var d = r.start
            while d < r.end {
                vals.append(value(day: d))
                guard let n = cal.date(byAdding: .day, value: 1, to: d) else { break }
                d = n
            }
            let n = vals.count
            if period == .week {
                return (vals, (0..<n).map { i in
                    let day = cal.date(byAdding: .day, value: i, to: r.start) ?? r.start
                    return String(day.formatted(.dateTime.weekday(.narrow)))
                })
            }
            return (vals, (0..<n).map { i in
                i == 0 ? "1st" : i == 14 ? "15th" : i == n - 1 ? Self.ordinal(n) : nil
            })
        case .custom:
            var vals: [Double] = [], days: [Date] = []
            var d = r.start
            while d < r.end {
                vals.append(value(day: d))
                days.append(d)
                guard let n = cal.date(byAdding: .day, value: 1, to: d) else { break }
                d = n
            }
            let n = vals.count
            return (vals, days.enumerated().map { i, d in
                i == 0 || i == n - 1 || (n > 4 && i == n / 2) ? d.formatted(.dateTime.day().month(.abbreviated)) : nil
            })
        case .year, .lifetime:
            var vals: [Double] = [], starts: [Date] = []
            var m = cal.dateInterval(of: .month, for: r.start)?.start ?? r.start
            while m < r.end {
                let next = cal.date(byAdding: .month, value: 1, to: m) ?? r.end
                vals.append(value(from: m, to: min(next, r.end)))
                starts.append(m)
                m = next
            }
            let n = vals.count
            return (vals, starts.enumerated().map { i, d in
                if n <= 12 { return String(d.formatted(.dateTime.month(.narrow))) }
                return i == 0 || i == n - 1 || i == n / 2 ? d.formatted(.dateTime.month(.abbreviated).year(.twoDigits)) : nil
            })
        }
    }

    private static let hourLabels: [String?] = (0..<24).map { $0 == 0 ? "12 AM" : $0 == 12 ? "12 PM" : $0 == 23 ? "11 PM" : nil }

    private static func ordinal(_ n: Int) -> String {
        switch n % 10 {
        case 1 where n != 11: return "\(n)st"
        case 2 where n != 12: return "\(n)nd"
        case 3 where n != 13: return "\(n)rd"
        default: return "\(n)th"
        }
    }
}

enum RM {
    static func text(_ v: Double) -> String {
        v < 100 ? "RM " + v.formatted(.number.locale(Num.en).precision(.fractionLength(2))) : "RM " + Num.whole(v)
    }
}

/// Explains Energy Value, with the two TNB rates editable.
struct EnergyValueInfoView: View {
    @AppStorage(Tariff.peakKey) private var peak = Tariff.peakDefault
    @AppStorage(Tariff.offPeakKey) private var offPeak = Tariff.offPeakDefault

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("Rates", [
                    AnyView(rateRow("Peak", "Mon–Fri 2pm–10pm", $peak)),
                    AnyView(rateRow("Off-peak", "Mon–Fri 10pm–2pm, Sat & Sun all day", $offPeak)),
                ])
                VStack(alignment: .leading, spacing: 10) {
                    Text("How it's worked out").font(.app(size: 14, weight: .semibold))
                    Text("Solar used by the house or the Model 3 is valued at the rate for the time it was used.")
                    Text("Solar exported is credited each month under NEM 3.0: it offsets that month's off-peak import at the off-peak rate first, then peak import at the peak rate.")
                    Text("AFA, the incentive tier and the capacity and network charges aren't included, so this is an estimate, not your bill.")
                }
                .font(.app(size: 13)).foregroundStyle(TeslaDark.labelGrey)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(TeslaDark.card, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(16)
        }
        .teslaPage("Energy Value")
    }

    private func section(_ title: String, _ rows: [AnyView]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.app(size: 13)).foregroundStyle(TeslaDark.rowLabel).padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(rows.indices, id: \.self) { i in
                    rows[i]
                    if i < rows.count - 1 { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5).padding(.leading, 16) }
                }
            }
            .background(TeslaDark.card, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func rateRow(_ name: String, _ hours: String, _ v: Binding<Double>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.app(size: 14))
                Text(hours).font(.app(size: 11)).foregroundStyle(TeslaDark.rowLabel)
            }
            Spacer()
            Text("RM").font(.app(size: 14)).foregroundStyle(TeslaDark.rowLabel)
            TextField("", value: v, format: .number.precision(.fractionLength(4)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.app(size: 14, weight: .semibold))
                .frame(width: 80)
            Text("/kWh").font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

/// Thin green bars with a line at the tallest one (Tesla app's Energy Value).
struct ValueBarsView: View {
    let values: [Double]
    let labels: [String?]
    static let green = Color(red: 94 / 255, green: 214 / 255, blue: 140 / 255)

    var body: some View {
        let mx = values.max() ?? 0
        VStack(alignment: .leading, spacing: 6) {
            Text(RM.text(mx)).font(.app(size: 10)).foregroundStyle(TeslaDark.rowLabel)
            GeometryReader { g in
                let n = max(values.count, 1)
                let step = g.size.width / CGFloat(n)
                let bw = n > 14 ? max(2, min(3.5, step * 0.45)) : min(step * 0.38, 12)
                let peakI = values.firstIndex(of: mx) ?? 0
                ZStack(alignment: .topLeading) {
                    if mx > 0 {
                        Rectangle().fill(Color(white: 0.42))
                            .frame(width: step * (CGFloat(peakI) + 0.5) + bw / 2, height: 1)
                    }
                    ForEach(values.indices, id: \.self) { i in
                        let h = mx > 0 ? g.size.height * CGFloat(values[i] / mx) : 0
                        if values[i] > 0 {
                            RoundedRectangle(cornerRadius: min(bw / 2, 2.5), style: .continuous)
                                .fill(Self.green)
                                .frame(width: bw, height: max(h, 2))
                                .position(x: step * (CGFloat(i) + 0.5), y: g.size.height - max(h, 2) / 2)
                        }
                    }
                }
            }
            .frame(height: 120)
            GeometryReader { g in
                let n = max(values.count, 1)
                let step = g.size.width / CGFloat(n)
                ForEach(labels.indices, id: \.self) { i in
                    if let l = labels[i] {
                        let first = i == 0, last = i == labels.count - 1, every = labels.allSatisfy { $0 != nil }
                        Text(l).font(.app(size: 10)).foregroundStyle(TeslaDark.rowLabel)
                            .fixedSize()
                            .frame(width: every ? step : 60, alignment: every ? .center : first ? .leading : last ? .trailing : .center)
                            .position(x: every ? step * (CGFloat(i) + 0.5) : first ? 30 : last ? g.size.width - 30 : step * (CGFloat(i) + 0.5),
                                      y: 7)
                    }
                }
            }
            .frame(height: 14)
        }
    }
}

// Time-of-Use (Impact): where home use (house + car) came from, split by TNB peak / off-peak.
struct TouSplit {
    var peak = EnergyFlow()
    var off = EnergyFlow()
}

extension EnergyStore {
    /// Sums the saved slots of each day in [start, end) into peak and off-peak, by each slot's own time.
    func touSplit(from start: Date, to end: Date) -> TouSplit {
        let cal = Calendar.current
        var out = TouSplit()
        var d = cal.startOfDay(for: start)
        while d < end {
            if let c = curve(d) {
                let weekend = Tariff.isWeekend(d)
                let fs = c.flows
                for i in 0..<c.count {
                    if Tariff.isPeak(minute: i * c.minutes, weekend: weekend) { out.peak = out.peak + fs[i] } else { out.off = out.off + fs[i] }
                }
            }
            guard let n = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = n
        }
        return out
    }
}

/// Everything the Impact cards add up for one period.
struct ImpactNumbers {
    let total: DaySummary
    let coverage: Coverage
    let tou: TouSplit
    let bars: (values: [Double], labels: [String?])
}

extension EnergyStore {
    /// Added up once per period; redrawing the page (scrolling to a card, a tab, an (i)) reuses it.
    func impactNumbers(_ period: ImpactPeriod, _ r: PeriodRange) -> ImpactNumbers {
        let today = Self.keyFormatter.string(from: Date())
        let k = "\(period.rawValue)|\(r.start.timeIntervalSince1970)|\(r.end.timeIntervalSince1970)|\(Tariff.stamp)|\(today)"
        if let n = numberCache[k] { return n }
        let n = ImpactNumbers(total: total(from: r.start, to: r.end), coverage: coverage(r),
                              tou: touSplit(from: r.start, to: r.end), bars: valueBars(period, r))
        numberCache[k] = n
        return n
    }
}
