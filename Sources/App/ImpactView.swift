import SwiftUI

enum ImpactPeriod: String, CaseIterable, Identifiable {
    case day = "Day", week = "Week", month = "Month", year = "Year", lifetime = "Lifetime"
    var id: String { rawValue }

    var component: Calendar.Component? {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        case .lifetime: return nil
        }
    }
}

/// Opened from the Impact row on My Home. Tesla-app style: period menu top right, cards below.
struct ImpactView: View {
    @ObservedObject var model: EnergyStore
    @ObservedObject var home: MyHomeModel
    @AppStorage("impact.period") private var periodRaw = ImpactPeriod.month.rawValue
    @State private var offset = 0
    @State private var showInfo = false

    private var period: ImpactPeriod { ImpactPeriod(rawValue: periodRaw) ?? .month }

    static let solarColor = Color(red: 1, green: 0.8, blue: 0.2)
    static let gridColor = Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)

    var body: some View {
        let r = PeriodRange.make(period, offset: offset, firstDay: model.firstDay)
        let t = model.total(from: r.start, to: r.end)
        ScrollView {
            VStack(spacing: 10) {
                PeriodBar(range: r, period: period, firstDay: model.firstDay, offset: $offset)
                if model.curves.isEmpty && model.loading {
                    VStack(spacing: 10) {
                        ProgressView().tint(.white)
                        Text("Loading energy history from Home Assistant…").font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    selfPoweredCard(t)
                    carCard(t)
                    carbonCard(t)
                }
                forecastCard
                if let msg = model.message {
                    Text(msg).font(.app(size: 11)).foregroundStyle(TeslaDark.importing)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
        .teslaPage("Impact")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { PeriodMenu(periodRaw: $periodRaw, offset: $offset) }
        }
        .task { await model.refresh() }
    }

    // MARK: Cards

    private func card<C: View>(_ title: String, _ icon: String, action: (() -> Void)? = nil, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.app(size: 14)).foregroundStyle(TeslaDark.labelGrey)
                Spacer()
                if let action {
                    Button(action: action) { Image(systemName: icon) }.buttonStyle(.plain)
                } else {
                    Image(systemName: icon)
                }
            }
            .font(.system(size: 15))
            .foregroundStyle(TeslaDark.dim)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TeslaDark.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func big(_ text: String) -> some View {
        Text(text).font(.app(size: 38, weight: .semibold)).padding(.top, 4)
    }

    private func split(_ a: Double, _ b: Double, _ aLabel: String, _ bLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { g in
                let total = a + b
                HStack(spacing: 0) {
                    Rectangle().fill(Self.solarColor).frame(width: total > 0 ? g.size.width * a / total : 0)
                    Rectangle().fill(Self.gridColor)
                }
                .clipShape(Capsule())
                .background(Capsule().fill(Color(white: 0.23)))
            }
            .frame(height: 8)
            HStack(spacing: 16) {
                legend(Self.solarColor, "\(aLabel) \(kwh(a))")
                legend(Self.gridColor, "\(bLabel) \(kwh(b))")
            }
        }
        .padding(.top, 12)
    }

    private func legend(_ c: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(c).frame(width: 8, height: 8)
            Text(text).font(.app(size: 12)).foregroundStyle(TeslaDark.labelGrey)
        }
    }

    private func kwh(_ v: Double) -> String {
        v >= 100 ? String(format: "%.0f kWh", v) : String(format: "%.1f kWh", v)
    }

    private func pct(_ v: Double?) -> String { v.map { "\(Int(($0 * 100).rounded()))%" } ?? "—" }

    private func selfPoweredCard(_ t: DaySummary) -> some View {
        card("Self-Powered", "info.circle", action: { withAnimation { showInfo.toggle() } }) {
            big(pct(t.selfPowered))
            Text("of the energy your home and Model 3 used came from solar")
                .font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
            split(t.solarUsed, t.imp, "Solar", "Grid")
            if showInfo {
                Text("Used = solar generated + bought from TNB − exported. Solar exported to TNB doesn't count here; it shows in CO₂ avoided.")
                    .font(.app(size: 11)).foregroundStyle(TeslaDark.dim)
                    .padding(.top, 10)
            }
        }
    }

    private func carCard(_ t: DaySummary) -> some View {
        card("Model 3 on solar", "car.side") {
            if t.car < 0.05 {
                big("—")
                Text("No home charging in this period").font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
            } else {
                big(pct(t.carSolarShare))
                Text("of home charging came from solar").font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                split(t.carSolar, max(t.car - t.carSolar, 0), "Solar", "Grid")
                if let perKm = model.kWhPerKm, t.carSolar > 0 {
                    let km = t.carSolar * ImpactStat.chargeEfficiency / perKm
                    Text("≈ \(km.formatted(.number.precision(.fractionLength(0)))) km driven on sunshine")
                        .font(.app(size: 14)).padding(.top, 12)
                }
            }
        }
    }

    private func carbonCard(_ t: DaySummary) -> some View {
        let kg = t.solar * ImpactStat.gridKgPerKWh
        let trees = kg / ImpactStat.kgPerTree
        return card("CO₂ avoided", "leaf") {
            big(kg >= 1000 ? String(format: "%.2f t", kg / 1000) : String(format: "%.0f kg", kg))
            Text("\(kwh(t.solar)) solar × \(String(format: "%.3f", ImpactStat.gridKgPerKWh)) kg/kWh (Peninsular grid)")
                .font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
            HStack(spacing: 8) {
                Image(systemName: "tree.fill").foregroundStyle(TeslaDark.exporting).font(.system(size: 18))
                Text("Like planting \(trees < 10 ? String(format: "%.1f", trees) : String(format: "%.0f", trees)) trees")
                    .font(.app(size: 14))
            }
            .padding(.top, 12)
        }
    }

    private var forecastCard: some View {
        card("Solar forecast", "sun.max") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                big(model.forecastTomorrow.map { String(format: "%.1f kWh", $0) } ?? "—")
                Text("tomorrow").font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
            }
            Text([model.peakTomorrow.map { "Peak around \($0.formatted(date: .omitted, time: .shortened))" },
                  home.dailyYield.map { String(format: "today %.1f kWh", $0) }]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
        }
    }
}
