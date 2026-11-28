import SwiftUI

// Energy › Grid › Utility Bill: the TNB bill from the meter's import and export (maths in Core's `Bill`).

/// kWh that matter to the bill.
struct BillUse {
    var peak = 0.0, off = 0.0, exp = 0.0
    var imp: Double { peak + off }
    static func + (a: BillUse, b: BillUse) -> BillUse { BillUse(peak: a.peak + b.peak, off: a.off + b.off, exp: a.exp + b.exp) }
    /// A bill is read in whole kWh.
    var bill: (Date) -> Bill {
        { month in
            Bill.month(peak: peak.rounded(), off: off.rounded(), export: exp.rounded(), afaSen: Tariff.afa(month),
                       threshold: Tariff.threshold(month), rates: Tariff.billRates)
        }
    }
}

struct BillSummary {
    var bill = Bill()
    var estimate: Double?     // full month, for the month still running
    var missing = 0           // days gone by with nothing recorded
    var have = 0
}

extension EnergyStore {
    func billUse(_ day: Date) -> BillUse? {
        guard let c = curve(day) else { return nil }
        let today = Calendar.current.isDateInToday(day)
        let k = "\(Self.keyFormatter.string(from: day))|\(c.minutes)|\(Tariff.stamp)"
        if !today, let u = billCache[k] { return u }
        let offDay = Tariff.isWeekend(day)
        var u = BillUse()
        for i in 0..<c.count {
            if Tariff.isPeak(minute: i * c.minutes, weekend: offDay) { u.peak += Double(c.imp[i]) } else { u.off += Double(c.imp[i]) }
            u.exp += Double(c.exp[i])
        }
        if !today { billCache[k] = u }
        return u
    }

    /// A month's use so far, how many days have data, and how many gone by don't.
    private func monthUse(_ start: Date, _ end: Date) -> (use: BillUse, have: Int, missing: Int) {
        let cal = Calendar.current
        var u = BillUse(), have = 0, missing = 0
        var d = start
        while d < end, d <= Date() {
            if let x = billUse(d) { u = u + x; have += 1 } else { missing += 1 }
            guard let n = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = n
        }
        return (u, have, missing)
    }

    /// Full-month use at the pace so far (only over the days there is data for).
    private func projected(_ use: BillUse, _ iv: DateInterval, missing: Int) -> BillUse {
        let cal = Calendar.current
        let days = Double(cal.range(of: .day, in: .month, for: iv.start)?.count ?? 30)
        let elapsed = Date().timeIntervalSince(iv.start) / 86400 - Double(missing)
        let k = max(days / max(elapsed, 1), 1)
        return BillUse(peak: use.peak * k, off: use.off * k, exp: use.exp * k)
    }

    func billSummary(_ period: ImpactPeriod, _ r: PeriodRange) -> BillSummary {
        let cal = Calendar.current
        var out = BillSummary()
        var m = cal.dateInterval(of: .month, for: r.start)?.start ?? r.start
        while m < r.end, m <= Date() {
            guard let iv = cal.dateInterval(of: .month, for: m) else { break }
            let u = monthUse(iv.start, iv.end)
            let current = iv.contains(Date())
            switch period {
            case .month:
                out.bill = u.use.bill(m)
                out.have = u.have; out.missing = u.missing
                if current, u.have > 0 { out.estimate = projected(u.use, iv, missing: u.missing).bill(m).total }
            case .year, .lifetime:
                // Months before the first record don't count as missing.
                if u.have > 0 { out.bill = out.bill + u.use.bill(m); out.have += u.have; out.missing += u.missing }
            default:
                // Day / Week / Custom: each day's share of its month's bill (the expected one while the month runs).
                let ref = current ? projected(u.use, iv, missing: u.missing) : u.use
                let b = ref.bill(m)
                let days = Double(cal.range(of: .day, in: .month, for: m)?.count ?? 30)
                var d = max(iv.start, r.start)
                while d < min(iv.end, r.end), d <= Date() {
                    if let x = billUse(d) {
                        out.bill = out.bill + b.share(peak: part(x.peak, ref.peak), off: part(x.off, ref.off),
                                                      imp: part(x.imp, ref.imp), exp: part(x.exp, ref.exp), day: 1 / days)
                        out.have += 1
                    } else { out.missing += 1 }
                    guard let n = cal.date(byAdding: .day, value: 1, to: d) else { break }
                    d = n
                }
            }
            m = iv.end
        }
        return out
    }

    private func part(_ v: Double, _ of: Double) -> Double { of > 0 ? v / of : 0 }
}

extension Bill {
    /// One day's slice; it can be negative on a day that exports more than it costs.
    func share(peak: Double, off: Double, imp: Double, exp: Double, day: Double) -> Bill {
        var s = Bill(energyPeak: energyPeak * peak, energyOff: energyOff * off, afa: afa * imp, capacity: capacity * imp,
                     network: network * imp, retail: retail * day, incentive: incentive * imp, serviceTax: serviceTax * imp,
                     kwtbb: kwtbb * imp, credit: credit * exp)
        s.total = s.energyPeak + s.energyOff + s.afa + s.capacity + s.network + s.retail + s.incentive
            + s.serviceTax + s.kwtbb - s.credit
        return s
    }
}

struct UtilityBillSection: View {
    @ObservedObject var store: EnergyStore
    let period: ImpactPeriod
    let range: PeriodRange
    @Binding var showBreakdown: Bool
    @Binding var folded: Bool

    private let border = Color(white: 0.24)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 18) {
                Text("Utility Bill").font(.app(size: 14, weight: .semibold))
                Spacer()
                Button { showBreakdown.toggle() } label: {
                    Image(systemName: showBreakdown ? "eye" : "eye.slash").font(.system(size: 15, weight: .medium))
                        .frame(width: 26, height: 26)
                }
                .accessibilityLabel(showBreakdown ? "Hide cost breakdown" : "Show cost breakdown")
                Button { withAnimation(.easeInOut(duration: 0.3)) { folded.toggle() } } label: {
                    Image(systemName: "chevron.up").font(.system(size: 14, weight: .medium))
                        .rotationEffect(.degrees(folded ? 180 : 0))
                        .frame(width: 26, height: 26)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .padding(.top, 22)
            if !folded { content.transition(.opacity) }
        }
    }

    private var current: Bool { range.start <= Date() && Date() < range.end }

    private var caption: String {
        switch period {
        case .day: return current ? "Today · estimate" : "\(range.label) · estimate"
        case .week: return current ? "This week so far · estimate" : "Week · estimate"
        case .month: return current ? "Month so far" : "Full month"
        case .year, .lifetime: return "Monthly bills added up"
        case .custom: return "Chosen days · estimate"
        }
    }

    private var content: some View {
        let s = store.billSummary(period, range)
        let b = s.bill
        let none = s.have == 0
        return VStack(alignment: .leading, spacing: 8) {
            Text(caption).font(.app(size: 13)).foregroundStyle(TeslaDark.rowLabel)
            box {
                row(period == .month && current ? "Current bill" : "Bill", none ? "–" : money(b.total, rm: true), strong: true)
                if let e = s.estimate {
                    line
                    row("Estimated full month", money(e, rm: true), strong: true)
                }
            }
            if s.missing > 0 && !none {
                Text("\(s.missing) day\(s.missing == 1 ? "" : "s") without data, not counted.")
                    .font(.app(size: 11.5)).foregroundStyle(TeslaDark.rowLabel)
            }
            if showBreakdown && !none {
                let items: [(String, Double)] = [
                    ("Energy (peak)", b.energyPeak), ("Energy (off-peak)", b.energyOff), ("AFA", b.afa),
                    ("Capacity", b.capacity), ("Network", b.network), ("Retail", b.retail),
                    ("Energy efficiency incentive", b.incentive), ("Service tax", b.serviceTax), ("KWTBB", b.kwtbb),
                    ("NEM credit", -b.credit)
                ].filter { abs($0.1) >= 0.005 }
                Text("Breakdown").font(.app(size: 13)).foregroundStyle(TeslaDark.rowLabel).padding(.top, 4)
                box {
                    ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                        if i > 0 { line }
                        row(item.0, money(item.1), tint: item.0 == "NEM credit" ? EnergyColor.solar : .white)
                    }
                }
            }
        }
        .padding(.top, 14)
    }

    private var line: some View { Rectangle().fill(border).frame(height: 1) }

    private func box<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 0, content: content)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(border, lineWidth: 1))
    }

    private func row(_ name: String, _ value: String, strong: Bool = false, tint: Color = .white) -> some View {
        HStack {
            Text(name).font(.app(size: strong ? 14 : 13.5, weight: strong ? .semibold : .regular))
                .foregroundStyle(strong ? .white : TeslaDark.rowLabel)
            Spacer()
            Text(value).font(.app(size: strong ? 14 : 13.5, weight: strong ? .semibold : .regular)).foregroundStyle(tint)
        }
        .padding(.horizontal, 12)
        .frame(height: strong ? 44 : 38)
    }

    private func money(_ v: Double, rm: Bool = false) -> String {
        let n = abs(v).formatted(.number.locale(Num.en).precision(.fractionLength(2)))
        return (v <= -0.005 ? "−" : "") + (rm ? "RM " : "") + n
    }
}
