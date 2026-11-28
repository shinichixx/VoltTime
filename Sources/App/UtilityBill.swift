import SwiftUI

// Energy › Utility Bill: the TNB bill from the meter's import and export (maths in Core's `Bill`). Home and Vehicle
// show their share of it by the grid energy each took; Solar and All also show what solar saved.

/// kWh that matter to the bill.
struct BillUse {
    var peak = 0.0, off = 0.0, exp = 0.0
    var carPeak = 0.0, carOff = 0.0           // the part of the import that went into the car
    var homeGrid = 0.0, carGrid = 0.0         // grid use as in Energy Flow
    var homeSP = 0.0, homeSO = 0.0            // solar the home used directly, peak / off-peak
    var carSP = 0.0, carSO = 0.0              // the same for the car
    var imp: Double { peak + off }
    var carImp: Double { carPeak + carOff }
    var homeSolar: Double { homeSP + homeSO }
    var carSolar: Double { carSP + carSO }
    /// The same use had the solar energy come from the grid, with nothing exported.
    var withoutSolar: BillUse { BillUse(peak: peak + homeSP + carSP, off: off + homeSO + carSO) }

    private static let fields: [WritableKeyPath<BillUse, Double>] = [
        \.peak, \.off, \.exp, \.carPeak, \.carOff, \.homeGrid, \.carGrid, \.homeSP, \.homeSO, \.carSP, \.carSO]
    static func + (a: BillUse, b: BillUse) -> BillUse {
        var o = a
        for f in fields { o[keyPath: f] += b[keyPath: f] }
        return o
    }
    func times(_ k: Double) -> BillUse {
        var o = self
        for f in Self.fields { o[keyPath: f] *= k }
        return o
    }
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
    var car = Bill()                // the car's share of `bill`; the home has the rest
    var carEstimate: Double?
    var without = Bill()            // the bill had there been no solar
    var homeGrid = 0.0, carGrid = 0.0, homeSolar = 0.0, carSolar = 0.0, exported = 0.0   // kWh over the days counted
    private var homeWorth = 0.0, carWorth = 0.0

    mutating func add(_ b: Bill, _ use: BillUse, without w: Bill) {
        bill = bill + b
        car = car + b.carShare(use)
        without = without + w
        homeGrid += use.homeGrid
        carGrid += use.carGrid
        homeSolar += use.homeSolar
        carSolar += use.carSolar
        exported += use.exp
        // Peak solar is worth more than off-peak: weigh each by its energy, capacity and network rates.
        let r = Tariff.billRates
        let p = r.energyPeak + r.capacity + r.network, o = r.energyOff + r.capacity + r.network
        homeWorth += use.homeSP * p + use.homeSO * o
        carWorth += use.carSP * p + use.carSO * o
    }

    /// RM saved by using solar directly (the export credit is `bill.credit`).
    private var directSaved: Double { max(without.total - bill.total - bill.credit, 0) }
    var homeSaved: Double { homeWorth + carWorth > 0 ? directSaved * homeWorth / (homeWorth + carWorth) : 0 }
    var carSaved: Double { homeWorth + carWorth > 0 ? directSaved * carWorth / (homeWorth + carWorth) : 0 }
}

extension EnergyStore {
    func billUse(_ day: Date) -> BillUse? {
        guard let c = curve(day) else { return nil }
        let today = Calendar.current.isDateInToday(day)
        let k = "\(Self.keyFormatter.string(from: day))|\(c.minutes)|\(Tariff.stamp)"
        if !today, let u = billCache[k] { return u }
        let offDay = Tariff.isWeekend(day)
        var u = BillUse()
        let flows = c.flows
        for i in 0..<c.count {
            let im = Double(c.imp[i])
            let f = flows[i]
            // The slot's import is split between car and home as their grid use in it.
            let grid = f.carGrid + f.homeGrid
            let car = grid > 0 ? im * f.carGrid / grid : 0
            u.homeGrid += f.homeGrid
            u.carGrid += f.carGrid
            if Tariff.isPeak(minute: i * c.minutes, weekend: offDay) {
                u.peak += im; u.carPeak += car; u.homeSP += f.homeSolar; u.carSP += f.carSolar
            } else {
                u.off += im; u.carOff += car; u.homeSO += f.homeSolar; u.carSO += f.carSolar
            }
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
        return use.times(k)
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
                out.add(u.use.bill(m), u.use, without: u.use.withoutSolar.bill(m))
                out.have = u.have; out.missing = u.missing
                if current, u.have > 0 {
                    let p = projected(u.use, iv, missing: u.missing)
                    let b = p.bill(m)
                    out.estimate = b.total
                    out.carEstimate = b.carShare(p).total
                }
            case .year, .lifetime:
                // Months before the first record don't count as missing.
                if u.have > 0 { out.add(u.use.bill(m), u.use, without: u.use.withoutSolar.bill(m)); out.have += u.have; out.missing += u.missing }
            default:
                // Day / Week / Custom: each day's share of its month's bill (the expected one while the month runs).
                let ref = current ? projected(u.use, iv, missing: u.missing) : u.use
                let b = ref.bill(m)
                let refNo = ref.withoutSolar
                let bNo = refNo.bill(m)
                let days = Double(cal.range(of: .day, in: .month, for: m)?.count ?? 30)
                var d = max(iv.start, r.start)
                while d < min(iv.end, r.end), d <= Date() {
                    if let x = billUse(d) {
                        let n = x.withoutSolar
                        out.add(b.share(peak: part(x.peak, ref.peak), off: part(x.off, ref.off),
                                        imp: part(x.imp, ref.imp), exp: part(x.exp, ref.exp), day: 1 / days), x,
                                without: bNo.share(peak: part(n.peak, refNo.peak), off: part(n.off, refNo.off),
                                                   imp: part(n.imp, refNo.imp), exp: 0, day: 1 / days))
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

    /// The car's part: energy by its peak and off-peak import, everything else by its share of all import.
    func carShare(_ u: BillUse) -> Bill {
        func f(_ v: Double, _ of: Double) -> Double { of > 0 ? v / of : 0 }
        let k = f(u.carImp, u.imp)
        return scaled(peak: f(u.carPeak, u.peak), off: f(u.carOff, u.off), rest: k)
    }

    private func scaled(peak: Double, off: Double, rest k: Double) -> Bill {
        var s = Bill(energyPeak: energyPeak * peak, energyOff: energyOff * off, afa: afa * k, capacity: capacity * k,
                     network: network * k, retail: retail * k, incentive: incentive * k, serviceTax: serviceTax * k,
                     kwtbb: kwtbb * k, credit: credit * k)
        s.total = s.energyPeak + s.energyOff + s.afa + s.capacity + s.network + s.retail + s.incentive
            + s.serviceTax + s.kwtbb - s.credit
        return s
    }

    /// What's left after taking `other` out (the home's share = bill − car).
    func minus(_ o: Bill) -> Bill {
        Bill(energyPeak: energyPeak - o.energyPeak, energyOff: energyOff - o.energyOff, afa: afa - o.afa,
             capacity: capacity - o.capacity, network: network - o.network, retail: retail - o.retail,
             incentive: incentive - o.incentive, serviceTax: serviceTax - o.serviceTax, kwtbb: kwtbb - o.kwtbb,
             credit: credit - o.credit, total: total - o.total)
    }
}

struct UtilityBillSection: View {
    @ObservedObject var store: EnergyStore
    let period: ImpactPeriod
    let range: PeriodRange
    @Binding var showBreakdown: Bool
    @Binding var folded: Bool
    var share: EnergyComponent = .grid   // which Energy view this is

    private let border = Color(white: 0.24)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
                .padding(.horizontal, -20).padding(.top, 23)   // edge to edge, same gap above and below
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
            .padding(.top, 15)
            if !folded { content.transition(.opacity) }
        }
    }

    private var current: Bool { range.start <= Date() && Date() < range.end }

    private var caption: String {
        switch period {
        case .day: return "Estimate"
        case .week: return current ? "This week so far · estimate" : "Week · estimate"
        case .month: return current ? "Month so far" : "Full month"
        case .year, .lifetime: return "Monthly bills added up"
        case .custom: return "Chosen days · estimate"
        }
    }

    /// Captions of the All, Home and Vehicle boxes.
    private func titled(_ name: String) -> String {
        switch period {
        case .day, .week, .custom: return "\(name) · estimate"
        case .month: return current ? "\(name) · month so far" : name
        case .year, .lifetime: return name
        }
    }

    private var content: some View {
        let s = store.billSummary(period, range)
        let none = s.have == 0
        let b = share == .vehicle ? s.car : share == .home ? s.bill.minus(s.car) : s.bill
        return VStack(alignment: .leading, spacing: 8) {
            if share == .all {
                importBox(s, none: none)
                VStack(alignment: .leading, spacing: 8) { savingsBox(s, none: none) }
                    .padding(.top, 6)
            } else if share == .grid {
                billBox(s, b, none: none)
            } else {
                shareBox(s, b, none: none)
            }
            if s.missing > 0 && !none {
                Text("\(s.missing) day\(s.missing == 1 ? "" : "s") without data, not counted.")
                    .font(.app(size: 11.5)).foregroundStyle(TeslaDark.rowLabel)
            }
            if showBreakdown && !none {
                let items = breakdown(b)
                heading("Breakdown").padding(.top, 4)
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

    private func breakdown(_ b: Bill) -> [(String, Double)] {
        let all: [(String, Double)] = [
            ("Energy (peak)", b.energyPeak), ("Energy (off-peak)", b.energyOff), ("AFA", b.afa),
            ("Capacity", b.capacity), ("Network", b.network), ("Retail", b.retail),
            ("Energy efficiency incentive", b.incentive), ("Service tax", b.serviceTax), ("KWTBB", b.kwtbb),
            ("NEM credit", -b.credit)]
        return all.filter { abs($0.1) >= 0.005 }
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(.app(size: 13)).foregroundStyle(TeslaDark.rowLabel)
    }

    /// Grid: import charges, NEM credit and the bill.
    @ViewBuilder private func billBox(_ s: BillSummary, _ b: Bill, none: Bool) -> some View {
        heading(caption)
        box {
            iconRow(glyph(.grid, EnergyColor.grid), "Import charges", none ? "–" : money(b.total + b.credit, rm: true))
            line
            iconRow(glyph(.solar, EnergyColor.solar), "NEM credit", none ? "–" : money(-b.credit, rm: true),
                    green: !none && b.credit >= 0.005)
            line
            iconRow(symbol("doc.text"), period == .month && current ? "Current bill" : "Bill",
                    none ? "–" : money(b.total, rm: true))
            if let e = s.estimate {
                line
                iconRow(symbol("calendar"), "Estimated full month", money(e, rm: true))
            }
        }
    }

    private func glyph(_ kind: FlowGlyph.Kind, _ color: Color) -> AnyView {
        AnyView(FlowGlyph(kind: kind, color: color, height: 15, maxWidth: 18))
    }

    private func symbol(_ name: String) -> AnyView {
        AnyView(Image(systemName: name).font(.system(size: 15)).foregroundStyle(.white))
    }

    /// Icon, name, value (no percentage).
    private func iconRow(_ icon: AnyView, _ name: String, _ value: String, green: Bool = false) -> some View {
        HStack(spacing: 0) {
            icon.frame(width: 34)
            Text(name).font(.app(size: 13.5)).foregroundStyle(TeslaDark.rowLabel).lineLimit(1)
            Spacer(minLength: 8)
            Text(value).font(.app(size: 13.5, weight: green ? .semibold : .regular))
                .foregroundStyle(green ? Color.green : Color.white)
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
    }

    /// Estimated full month, in the share-row style; the percentage is how much of the month has passed.
    private func estimateRow(_ rm: Double) -> some View {
        let month = Calendar.current.dateInterval(of: .month, for: range.start)
        let passed = month.map { min(1, max(0, Date().timeIntervalSince($0.start) / $0.duration)) } ?? 0
        return HStack(spacing: 0) {
            symbol("calendar").frame(width: 34)
            Text("\(Int((passed * 100).rounded()))%").font(.app(size: 14, weight: .semibold))
                .frame(width: 48, alignment: .leading)
            Text("Estimated full month").font(.app(size: 13.5)).foregroundStyle(TeslaDark.rowLabel).lineLimit(1)
            Spacer(minLength: 8)
            Text(money(rm, rm: true)).font(.app(size: 13.5))
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
    }

    /// Home and Vehicle: its share of the grid import and what that costs.
    @ViewBuilder private func shareBox(_ s: BillSummary, _ b: Bill, none: Bool) -> some View {
        let car = share == .vehicle
        heading(titled("Share of grid import"))
        box {
            shareRow(car ? .car : .home, car ? EnergyColor.vehicle : EnergyColor.home,
                     none ? "–" : percent(car ? s.carGrid : s.homeGrid, s.homeGrid + s.carGrid),
                     car ? "Vehicle" : "Home", Text(none ? "–" : money(b.total, rm: true)))
            if let e = s.estimate, let c = s.carEstimate {
                line
                estimateRow(car ? c : e - c)
            }
        }
    }

    /// All: what the grid import costs, by who took it.
    @ViewBuilder private func importBox(_ s: BillSummary, none: Bool) -> some View {
        let grid = s.homeGrid + s.carGrid
        heading(titled("Import from grid"))
        box {
            shareRow(.home, EnergyColor.home, none ? "–" : percent(s.homeGrid, grid), "Home",
                     Text(none ? "–" : money(s.bill.minus(s.car).total, rm: true)))
            line
            shareRow(.car, EnergyColor.vehicle, none ? "–" : percent(s.carGrid, grid), "Vehicle",
                     Text(none ? "–" : money(s.car.total, rm: true)))
            if let e = s.estimate {
                line
                estimateRow(e)
            }
        }
    }

    /// All: where the solar energy went and what each part saved.
    @ViewBuilder private func savingsBox(_ s: BillSummary, none: Bool) -> some View {
        let total = s.homeSolar + s.carSolar + s.exported
        heading(titled("Savings from solar"))
        box {
            shareRow(.home, EnergyColor.home, none ? "–" : percent(s.homeSolar, total), "Home",
                     none ? Text("–") : savingText(s.homeSolar, s.homeSaved))
            line
            shareRow(.car, EnergyColor.vehicle, none ? "–" : percent(s.carSolar, total), "Vehicle",
                     none ? Text("–") : savingText(s.carSolar, s.carSaved))
            line
            shareRow(.grid, EnergyColor.grid, none ? "–" : percent(s.exported, total), "Grid",
                     none ? Text("–") : savingText(s.exported, s.bill.credit, exported: true))
        }
    }

    private func percent(_ part: Double, _ of: Double) -> String { of > 0 ? "\(Int((part / of * 100).rounded()))%" : "–" }

    private func savingText(_ kWh: Double, _ rm: Double, exported: Bool = false) -> Text {
        Text((exported && kWh >= 0.05 ? "- " : "") + Num.kwh(kWh, whole: period == .year || period == .lifetime) + " kWh · ")
            + Text("(" + money(abs(rm), rm: true) + ")")
                .font(.app(size: 13.5, weight: .semibold)).foregroundColor(.green)
    }

    /// Same row as the Energy Flow tables: icon, percentage, name, value.
    private func shareRow(_ glyph: FlowGlyph.Kind, _ color: Color, _ share: String, _ name: String, _ value: Text) -> some View {
        HStack(spacing: 0) {
            FlowGlyph(kind: glyph, color: color, height: 15, maxWidth: 18).frame(width: 34, alignment: .center)
            Text(share).font(.app(size: 14, weight: .semibold)).frame(width: 48, alignment: .leading)
            Text(name).font(.app(size: 13.5)).foregroundStyle(TeslaDark.rowLabel).lineLimit(1)
            Spacer(minLength: 8)
            value.font(.app(size: 13.5)).lineLimit(1).minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
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
