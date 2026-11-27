import SwiftUI

enum ImpactPeriod: String, CaseIterable, Identifiable {
    case day = "Day", week = "Week", month = "Month", year = "Year", lifetime = "Lifetime", custom = "Custom"
    var id: String { rawValue }

    var component: Calendar.Component? {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        case .lifetime, .custom: return nil
        }
    }

    /// Whether there's a previous / next one to swipe to.
    var steps: Bool { component != nil }
}

/// Opened from the Impact row on My Home. Tesla-app style: period menu top right, cards below.
struct ImpactView: View {
    @ObservedObject var model: EnergyStore
    @ObservedObject var home: MyHomeModel
    @AppStorage("impact.period") private var periodRaw = ImpactPeriod.month.rawValue
    @State private var offset = 0
    @State private var showInfo = false
    @State private var showValueInfo = false
    @State private var showCarbonInfo = false
    @State private var showTouInfo = false
    @AppStorage("impact.touPeak") private var touPeak = true
    @State private var forward = false

    private var period: ImpactPeriod { ImpactPeriod(stored: periodRaw) ?? .month }

    static let solarColor = Color(red: 1, green: 0.8, blue: 0.2)
    static let gridColor = Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)

    var body: some View {
        let r = PeriodRange.make(period, offset: offset, firstDay: model.firstDay, stored: periodRaw)
        let t = model.total(from: r.start, to: r.end)
        let cover = model.coverage(r)
        let empty = cover.have == 0 && !model.loading
        ScrollView {
            VStack(spacing: 10) {
                if model.curves.isEmpty && model.loading {
                    VStack(spacing: 10) {
                        ProgressView().tint(.white)
                        Text("Loading energy history from Home Assistant…").font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    // Swipe the cards for the previous / next period; they slide in from that side.
                    if let note = cover.note(day: period == .day, loading: model.loading) {
                        Text(note).font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                    }
                    ZStack {
                        VStack(spacing: 10) {
                            selfPoweredCard(t)
                            if !empty { touCard(r) }
                            if !empty { valueCard(r) }
                            if !empty {   // nothing recorded: no zeros that look like readings
                                offsetCard(t)
                                carCard(t)
                                carbonCard(t)
                            }
                        }
                        .id("\(periodRaw)|\(offset)")
                        .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading),
                                                removal: .move(edge: forward ? .leading : .trailing)))
                    }
                    .clipped()
                    .contentShape(Rectangle())
                    .simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { d in
                        let w = d.translation.width
                        guard abs(w) > 50, abs(w) > abs(d.translation.height) * 1.4 else { return }
                        step(w < 0 ? 1 : -1, r)
                    })
                }
                NavigationLink { ForecastVsActualView(model: model) } label: { forecastCard }
                    .buttonStyle(.plain)
                if let msg = model.message {
                    Text(msg).font(.app(size: 11)).foregroundStyle(TeslaDark.importing)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
        .pinnedTop {
            // "Today" on the left, the Timescale box on the same line; stays put while the cards scroll.
            HStack {
                Text(r.label).font(.app(size: 17, weight: .semibold))
                Spacer()
                PeriodMenu(periodRaw: $periodRaw, offset: $offset, boxed: true, firstDay: model.firstDay)
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
        }
        .teslaPage("Impact")
        .task { await model.refresh() }
    }

    /// One swipe, one period; can't go past today or before the first recorded day.
    private func step(_ by: Int, _ r: PeriodRange) {
        guard period.steps else { return }
        if by < 0 { guard model.firstDay.map({ r.start > $0 }) ?? false else { return } }
        else { guard offset < 0 else { return } }
        forward = by > 0
        DispatchQueue.main.async { withAnimation(.easeInOut(duration: 0.28)) { offset += by } }
    }

    // MARK: Cards (Tesla app style: bold white title, big figure, thin dividers)

    static let green = ValueBarsView.green
    static let offsetBlue = Color(red: 66 / 255, green: 105 / 255, blue: 1)

    private func card<C: View>(_ title: String, info: (() -> Void)? = nil, trailing: String? = nil,
                               @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(title).font(.app(size: 14, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                if let info {
                    Button(action: info) { Image(systemName: "info.circle").font(.system(size: 16)) }
                        .buttonStyle(.plain).foregroundStyle(TeslaDark.labelGrey)
                } else if let trailing {
                    Image(systemName: trailing).font(.system(size: 13, weight: .semibold)).foregroundStyle(TeslaDark.dim)
                }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TeslaDark.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func divider() -> some View {
        Rectangle().fill(Color.white.opacity(0.09)).frame(height: 0.5)
    }

    private func bigNumber(_ value: String, _ unit: String, _ color: Color = .white) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value).font(.app(size: 38, weight: .medium)).foregroundStyle(color)
            Text(unit).font(.app(size: 13)).foregroundStyle(TeslaDark.rowLabel)
        }
    }

    private func legendDot(_ c: Color, _ value: String, _ name: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().fill(c).frame(width: 7, height: 7).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.app(size: 12, weight: .semibold))
                Text(name).font(.app(size: 10)).foregroundStyle(TeslaDark.rowLabel)
            }
        }
    }

    private func kwh(_ v: Double) -> String {
        Num.kwh(v, whole: period == .year || period == .lifetime) + " kWh"
    }

    private func pctNum(_ v: Double?) -> String { v.map { "\(Int(($0 * 100).rounded()))" } ?? "—" }

    /// "This Month", "Today"… for the current period; the period's own name otherwise.
    private func caption(_ r: PeriodRange) -> String {
        if period == .lifetime { return "Lifetime" }
        guard offset == 0, period != .custom else { return r.label }
        switch period {
        case .day: return "Today"
        case .week: return "This Week"
        case .month: return "This Month"
        default: return "This Year"
        }
    }

    // Self-Powered: legend left, ring right.
    private func selfPoweredCard(_ t: DaySummary) -> some View {
        let sp = t.selfPowered
        return card("Self-Powered", info: { withAnimation { showInfo.toggle() } }) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 12) {
                    row(Self.solarColor, sp, "Solar")
                    row(Color(white: 0.4), sp.map { 1 - $0 }, "Grid")
                }
                Spacer()
                ZStack {
                    Circle().stroke(Color(white: 0.4), lineWidth: 9)
                    Circle().trim(from: 0, to: sp ?? 0)
                        .stroke(Self.solarColor, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(pctNum(sp)).font(.app(size: 32, weight: .medium))
                        Text("%").font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                    }
                }
                .frame(width: 104, height: 104)
                .padding(.trailing, 8)
            }
            .padding(.top, 14)
            if showInfo {
                Text("Used = solar generated + bought from TNB − exported. Solar exported to TNB doesn't count here; it shows in Solar Offset and CO₂ Avoided.")
                    .font(.app(size: 11)).foregroundStyle(TeslaDark.dim)
                    .padding(.top, 12)
            }
        }
    }

    private func row(_ c: Color, _ v: Double?, _ name: String) -> some View {
        HStack(spacing: 10) {
            Circle().fill(c).frame(width: 7, height: 7)
            Text(v.map { "\(Int(($0 * 100).rounded()))%" } ?? "—").font(.app(size: 12, weight: .semibold))
                .frame(width: 38, alignment: .leading)
            Text(name).font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
        }
    }

    // Time-of-Use: sources of home use (house + car) at peak and off-peak.
    private func touCard(_ r: PeriodRange) -> some View {
        let split = model.touSplit(from: r.start, to: r.end)
        func used(_ f: EnergyFlow) -> (solar: Double, grid: Double) { (f.homeSolar + f.carSolar, f.homeGrid + f.carGrid) }
        let p = used(split.peak), o = used(split.off)
        let pTotal = p.solar + p.grid, oTotal = o.solar + o.grid
        let cur = touPeak ? p : o
        let curTotal = touPeak ? pTotal : oTotal
        func tab(_ name: String, _ total: Double, _ on: Bool, _ peak: Bool) -> some View {
            Button { withAnimation(.easeInOut(duration: 0.2)) { touPeak = peak } } label: {
                VStack(spacing: 3) {
                    Text(name).font(.app(size: 13, weight: .semibold)).foregroundStyle(on ? Color.white : TeslaDark.dim)
                    Text(kwh(total)).font(.app(size: 10)).foregroundStyle(on ? TeslaDark.rowLabel : TeslaDark.dim)
                    Rectangle().fill(on ? Color.white : Color.clear).frame(width: 56, height: 2).clipShape(Capsule()).padding(.top, 7)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        func bar(_ name: String, _ v: Double, _ color: Color) -> some View {
            let frac = curTotal > 0 ? v / curTotal : 0
            return VStack(spacing: 8) {
                HStack {
                    Text(name).font(.app(size: 13, weight: .semibold))
                    Spacer()
                    Text(kwh(v)).font(.app(size: 11)).foregroundStyle(TeslaDark.rowLabel).padding(.trailing, 8)
                    Text(curTotal > 0 ? "\(Int((frac * 100).rounded()))%" : "—").font(.app(size: 13, weight: .semibold))
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.17))
                        Capsule().fill(color).frame(width: g.size.width * frac)
                    }
                }
                .frame(height: 6)
            }
        }
        return card("Time-of-Use", info: { withAnimation { showTouInfo.toggle() } }) {
            HStack(spacing: 0) {
                tab("Peak", pTotal, touPeak, true)
                tab("Off-Peak", oTotal, !touPeak, false)
            }
            .padding(.top, 14)
            divider()
            if curTotal > 0 {
                VStack(spacing: 18) {
                    bar("Solar", cur.solar, Self.solarColor)
                    bar("Grid", cur.grid, Self.gridColor)
                }
                .padding(.top, 16)
            } else {
                Text(touPeak ? "No peak-time use in this period" : "No off-peak use in this period")
                    .font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                    .frame(maxWidth: .infinity).padding(.vertical, 22)
            }
            if showTouInfo {
                Text(touPeak
                     ? "Peak: Monday to Friday, 2pm to 10pm · RM\(String(format: "%.4f", Tariff.peak))/kWh. Home use includes the car."
                     : "Off-Peak: Monday to Friday 10pm to 2pm, and all day Saturday and Sunday · RM\(String(format: "%.4f", Tariff.offPeak))/kWh. Home use includes the car.")
                    .font(.app(size: 11)).foregroundStyle(TeslaDark.dim)
                    .padding(.top, 14)
            }
        }
    }

    // Energy Value: RM saved, bars per hour / day / month.
    private func valueCard(_ r: PeriodRange) -> some View {
        let bars = model.valueBars(period, r)
        let total = bars.values.reduce(0, +)
        return card("Energy Value", info: { withAnimation { showValueInfo.toggle() } }) {
            Text("Estimated Value").font(.app(size: 11)).foregroundStyle(TeslaDark.rowLabel).padding(.top, 2)
            ValueBarsView(values: bars.values, labels: bars.labels).padding(.top, 16)
            VStack(spacing: 2) {
                Text(RM.text(total)).font(.app(size: 22, weight: .semibold)).foregroundStyle(Self.green)
                Text(caption(r)).font(.app(size: 9)).foregroundStyle(TeslaDark.dim)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
            if showValueInfo {
                Text("Solar you used is valued at the TNB ToU rate for the time it was used. Exported solar is credited under NEM 3.0: off-peak import first at the off-peak rate, then peak import at the peak rate.")
                    .font(.app(size: 11)).foregroundStyle(TeslaDark.dim)
                    .padding(.top, 12)
            }
            divider().padding(.top, 16)
            NavigationLink { EnergyValueInfoView() } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Estimate based on")
                        Text("TNB Domestic ToU · NEM 3.0")
                    }
                    .font(.app(size: 10)).foregroundStyle(TeslaDark.labelGrey)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(TeslaDark.dim)
                }
                .contentShape(Rectangle())
                .padding(.top, 12)
            }
            .buttonStyle(.plain)
        }
    }

    // Solar Offset: all solar generated vs all used (home + car).
    private func offsetCard(_ t: DaySummary) -> some View {
        let solar = t.solar, used = t.used
        let pct = used > 0 ? solar / used : nil
        return card("Solar Offset") {
            GeometryReader { g in
                let mx = max(solar, used, 0.001)
                let H = g.size.height
                let hs = H * CGFloat(solar / mx), hu = H * CGFloat(used / mx)
                let bw: CGFloat = 54
                let xs = g.size.width * 0.25, xu = g.size.width * 0.75
                let low = min(hs, hu)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Self.solarColor)
                        .frame(width: bw, height: max(hs, 2)).position(x: xs, y: H - max(hs, 2) / 2)
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Self.offsetBlue)
                        .frame(width: bw, height: max(hu, 2)).position(x: xu, y: H - max(hu, 2) / 2)
                    Path { p in
                        p.move(to: CGPoint(x: xs + bw / 2 + 4, y: H - low))
                        p.addLine(to: CGPoint(x: xu - bw / 2 - 4, y: H - low))
                    }
                    .stroke(Color(white: 0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(pct.map { "\(Int(($0 * 100).rounded()))%" } ?? "—").font(.app(size: 11, weight: .semibold))
                        Text("Energy Offset").font(.app(size: 10)).foregroundStyle(TeslaDark.labelGrey)
                    }
                    .offset(x: xs + bw / 2 + 10, y: min(H - low + 6, H - 30))
                }
            }
            .frame(height: 190)
            .padding(.top, 22)
            HStack(spacing: 0) {
                label(kwh(solar), "Solar", Self.solarColor).frame(maxWidth: .infinity)
                label(kwh(used), "Used", Self.offsetBlue).frame(maxWidth: .infinity)
            }
            .padding(.top, 10)
        }
    }

    private func label(_ value: String, _ name: String, _ c: Color) -> some View {
        (Text(value + " ").foregroundStyle(.white) + Text(name).foregroundStyle(c))
            .font(.app(size: 11, weight: .semibold))
    }

    // Vehicle on Solar: the Model 3 fills yellow from the front by the solar share.
    private func carCard(_ t: DaySummary) -> some View {
        let share = t.carSolarShare
        return card("Vehicle on Solar") {
            HStack(alignment: .center, spacing: 8) {
                SolarCarView(fraction: share ?? 0)
                    .frame(maxWidth: .infinity)
                VStack(spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(t.car < 0.05 ? "—" : pctNum(share)).font(.app(size: 36, weight: .medium))
                        if t.car >= 0.05 { Text("%").font(.app(size: 13)).foregroundStyle(TeslaDark.rowLabel) }
                    }
                    Text(t.car < 0.05 ? "no home charging" : "of home charging")
                        .font(.app(size: 10)).foregroundStyle(TeslaDark.rowLabel)
                }
                .frame(width: 110)
            }
            .padding(.top, 14)
            divider().padding(.top, 16)
            let km: Double? = {
                guard let perKm = model.kWhPerKm, perKm > 0, t.carSolar > 0 else { return nil }
                return t.carSolar * ImpactStat.chargeEfficiency / perKm
            }()
            HStack(alignment: .top, spacing: 0) {
                statColumn(dot: Self.solarColor, kwh(t.carSolar), "Solar")
                statDivider()
                statColumn(dot: Color(white: 0.4), kwh(max(t.car - t.carSolar, 0)), "Grid")
                statDivider()
                statColumn(dot: nil, km.map { "\(Num.whole($0)) km" } ?? "—", "Driven on sunshine", valueColor: Self.solarColor)
            }
            .padding(.top, 14)
        }
    }

    private func statColumn(dot: Color?, _ value: String, _ name: String, valueColor: Color = .white) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
                Text(value).font(.app(size: 13, weight: .semibold)).foregroundStyle(valueColor)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Text(name).font(.app(size: 10)).foregroundStyle(TeslaDark.rowLabel)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private func statDivider() -> some View {
        Rectangle().fill(Color.white.opacity(0.09)).frame(width: 0.5, height: 30)
    }

    // CO₂ Avoided: tonnes, and the trees that would take it up.
    private func carbonCard(_ t: DaySummary) -> some View {
        let kg = t.solar * ImpactStat.gridKgPerKWh
        let trees = kg / ImpactStat.kgPerTree
        let n = Int(trees.rounded())
        let per = max(1, Int((Double(n) / 39).rounded(.up)))
        let icons = trees < 1 ? 1 : Int((Double(n) / Double(per)).rounded(.up))
        return card("CO₂ Avoided", info: { withAnimation { showCarbonInfo.toggle() } }) {
            bigNumber(kg >= 1000 ? String(format: "%.2f", kg / 1000) : String(format: "%.0f", kg),
                      kg >= 1000 ? "tonnes" : "kg", Self.green)
                .padding(.top, 4)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 13), spacing: 10) {
                ForEach(0..<icons, id: \.self) { _ in
                    Image(systemName: "tree.fill").font(.system(size: 15)).foregroundStyle(Self.green)
                        .opacity(trees < 1 ? 0.4 : 1)
                }
            }
            .padding(.top, 8)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(trees < 10 ? String(format: "%.1f trees", trees) : "\(n) trees").font(.app(size: 12, weight: .semibold))
                Text(per > 1 ? "absorb this in 10 years · 1 icon = \(per)" : "absorb this in 10 years")
                    .font(.app(size: 11)).foregroundStyle(TeslaDark.rowLabel)
            }
            .padding(.top, 8)
            if showCarbonInfo {
                Text("Solar generated × the Peninsular Malaysia grid emission factor (Energy Commission 2024). One tree grown for 10 years takes up about 60 kg CO₂ (US EPA).")
                    .font(.app(size: 11)).foregroundStyle(TeslaDark.dim)
                    .padding(.top, 12)
            }
            divider().padding(.top, 12)
            Text("\(kwh(t.solar)) solar × \(String(format: "%.3f", ImpactStat.gridKgPerKWh)) kg/kWh")
                .font(.app(size: 10)).foregroundStyle(TeslaDark.labelGrey)
                .padding(.top, 10)
        }
    }

    // Solar Forecast: today's curve (filled up to now), tomorrow faint behind it.
    private var forecastCard: some View {
        card("Solar Forecast", trailing: "chevron.right") {
            bigNumber(model.forecastToday.map { Num.one($0) } ?? "—", "kWh today", Self.solarColor)
                .padding(.top, 8)
            ForecastCurveView(today: model.forecastCurveToday, tomorrow: model.forecastCurveTomorrow,
                              todayKWh: model.forecastToday, tomorrowKWh: model.forecastTomorrow,
                              peakToday: model.peakToday, peakTomorrow: model.peakTomorrow)
                .frame(height: 150)
                .padding(.top, 14)
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Capsule().fill(Self.solarColor).frame(width: 14, height: 2)
                    Text("Today, hourly Solcast")
                }
                HStack(spacing: 6) {
                    HStack(spacing: 2) { ForEach(0..<3, id: \.self) { _ in Capsule().fill(Color(white: 0.45)).frame(width: 3, height: 1.5) } }
                    Text("Tomorrow forecast")
                }
            }
            .font(.app(size: 9)).foregroundStyle(TeslaDark.rowLabel)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            divider().padding(.top, 14)
            HStack {
                Text("Tomorrow").font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                Spacer()
                Text(model.forecastTomorrow.map { Num.one($0) + " kWh" } ?? "—").font(.app(size: 13, weight: .semibold))
            }
            .padding(.top, 12)
        }
    }
}

/// The Model 3 side photo, painted yellow from the front by `fraction`.
struct SolarCarView: View {
    let fraction: Double
    private static let base = UIImage(named: "impact_car.png")
    private static let paint = UIImage(named: "impact_car_paint.png")

    var body: some View {
        ZStack {
            if let b = Self.base { Image(uiImage: b).resizable().scaledToFit() }
            if let p = Self.paint {
                Image(uiImage: p).resizable().scaledToFit()
                    .mask {
                        GeometryReader { g in
                            Rectangle().frame(width: g.size.width * CGFloat(min(max(fraction, 0), 1)))
                        }
                    }
            }
        }
        .aspectRatio(1100 / 359, contentMode: .fit)
    }
}

/// Forecast curve from Solcast's half-hourly points, or a smooth bell from the day total and peak time.
struct ForecastCurveView: View {
    let today: [ForecastPoint]
    let tomorrow: [ForecastPoint]
    let todayKWh: Double?
    let tomorrowKWh: Double?
    let peakToday: Date?
    let peakTomorrow: Date?

    private let cal = Calendar.current
    private let h0 = 6.0, h1 = 19.0
    private static let yellow = Color(red: 1, green: 0.8, blue: 0.2)

    /// kW at a clock hour (6.0…19.0).
    private func series(_ pts: [ForecastPoint], _ total: Double?, _ peak: Date?, _ dayStart: Date) -> (Double) -> Double {
        let p = pts.filter { cal.isDate($0.time, inSameDayAs: dayStart) }
        if p.count > 3 {
            let xs = p.map { $0.time.timeIntervalSince(dayStart) / 3600 }, ys = p.map(\.kw)
            return { h in
                guard let j = xs.firstIndex(where: { $0 >= h }) else { return 0 }
                if j == 0 { return xs[0] - h > 0.5 ? 0 : ys[0] }
                let q = (h - xs[j - 1]) / max(xs[j] - xs[j - 1], 0.01)
                return ys[j - 1] + (ys[j] - ys[j - 1]) * q
            }
        }
        guard let total, total > 0 else { return { _ in 0 } }
        let mu = peak.map { $0.timeIntervalSince(cal.startOfDay(for: $0)) / 3600 } ?? 12.5
        let sigma = 2.3
        let a = total / (sigma * (2 * Double.pi).squareRoot())
        return { h in a * exp(-pow(h - mu, 2) / (2 * sigma * sigma)) }
    }

    var body: some View {
        Canvas { ctx, size in
            let start = cal.startOfDay(for: Date())
            let tStart = cal.date(byAdding: .day, value: 1, to: start) ?? start
            let ft = series(today, todayKWh, peakToday, start)
            let fm = series(tomorrow, tomorrowKWh, peakTomorrow, tStart)
            let N = 156
            let hs = (0...N).map { h0 + (h1 - h0) * Double($0) / Double(N) }
            let mx = max(hs.map(ft).max() ?? 0, hs.map(fm).max() ?? 0, 0.1) * 1.12
            let plotH = size.height - 18
            func pt(_ h: Double, _ v: Double) -> CGPoint {
                CGPoint(x: size.width * (h - h0) / (h1 - h0), y: plotH * (1 - v / mx))
            }
            // grid + labels
            for (h, l) in [(6.0, "6 AM"), (12.0, "12 PM"), (18.0, "6 PM")] {
                let x = pt(h, 0).x
                ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: plotH)) },
                           with: .color(Color(white: 0.2)), lineWidth: 0.7)
                ctx.draw(Text(l).font(.app(size: 9)).foregroundColor(TeslaDark.rowLabel),
                         at: CGPoint(x: min(max(x, 14), size.width - 14), y: plotH + 10))
            }
            ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: plotH)); $0.addLine(to: CGPoint(x: size.width, y: plotH)) },
                       with: .color(Color(white: 0.27)), lineWidth: 0.7)
            func path(_ f: (Double) -> Double, _ a: Double, _ b: Double) -> Path {
                Path { p in
                    let sub = hs.filter { $0 >= a && $0 <= b }
                    guard let first = sub.first else { return }
                    p.move(to: pt(first, f(first)))
                    for h in sub.dropFirst() { p.addLine(to: pt(h, f(h))) }
                }
            }
            // tomorrow: faint dashed
            ctx.stroke(path(fm, h0, h1), with: .color(Color(white: 0.38)), style: StrokeStyle(lineWidth: 1.2, dash: [3, 4]))
            // today: filled + solid up to now, dashed after
            let now = Date().timeIntervalSince(start) / 3600
            let cut = min(max(now, h0), h1)
            if cut > h0 {
                var fill = path(ft, h0, cut)
                fill.addLine(to: pt(cut, ft(cut))); fill.addLine(to: pt(cut, 0)); fill.addLine(to: pt(h0, 0)); fill.closeSubpath()
                ctx.fill(fill, with: .linearGradient(Gradient(colors: [Self.yellow.opacity(0.42), Self.yellow.opacity(0.12)]),
                                                     startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: plotH)))
                var line = path(ft, h0, cut); line.addLine(to: pt(cut, ft(cut)))
                ctx.stroke(line, with: .color(Self.yellow), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            if cut < h1 {
                var rest = Path(); rest.move(to: pt(cut, ft(cut)))
                for h in hs where h > cut { rest.addLine(to: pt(h, ft(h))) }
                ctx.stroke(rest, with: .color(Self.yellow.opacity(0.6)), style: StrokeStyle(lineWidth: 1.4, dash: [3, 4]))
            }
            // peak marker
            let peakH = hs.max { ft($0) < ft($1) } ?? 12.5
            if ft(peakH) > 0.05 {
                let p = pt(peakH, ft(peakH))
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)), with: .color(Self.yellow), lineWidth: 2)
                let clock = start.addingTimeInterval(peakH * 3600)
                let t = (peakToday ?? clock).formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                ctx.draw(Text("Peak \(t)").font(.app(size: 10)).foregroundColor(.white), at: CGPoint(x: p.x, y: max(p.y - 12, 6)))
            }
            // now
            if now > h0 && now < h1 {
                let x = pt(now, 0).x
                ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: plotH)) }, with: .color(.white), lineWidth: 1.2)
                let p = pt(now, ft(now))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)), with: .color(.white))
            }
        }
    }
}
