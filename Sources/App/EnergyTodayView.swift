import SwiftUI
import Charts

/// Opened from the Energy row on My Home: today's power curves and totals, from Home Assistant history.
struct EnergyTodayView: View {
    @ObservedObject var model: MyHomeModel

    @State private var points: [PowerPoint] = []
    @State private var carKWh: Double?
    @State private var loading = false
    @State private var error: String?

    static let solarColor = Color(red: 1, green: 0.80, blue: 0.20)
    static let homeColor = TeslaDark.selfPowered
    static let carColor = Color(red: 0.90, green: 0.22, blue: 0.23)
    static let gridColor = Color(white: 0.62)

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.system(size: 13)).foregroundStyle(TeslaDark.rowLabel)
                        .padding(.horizontal, 4)
                    chartCard
                    tiles
                    Text("Home excludes the car. Grid below zero is export. From Home Assistant history; refreshed when you open this page or pull down.")
                        .font(.system(size: 11))
                        .foregroundStyle(TeslaDark.dim)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 30)
            }
            .refreshable { await load() }
        }
        .teslaPage("Energy")
        .task { await load() }
    }

    // MARK: Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Power today").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                if loading { ProgressView().tint(.white).scaleEffect(0.8) }
            }
            if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(TeslaDark.importing)
                    .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
            } else if points.isEmpty {
                Color.clear.frame(height: 220)
            } else {
                chart.frame(height: 220)
            }
        }
        .padding(14)
        .background(TeslaDark.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var chart: some View {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? Date()
        let solar = points.filter { $0.series == "Solar" }
        return Chart {
            ForEach(solar) { p in
                AreaMark(x: .value("Time", p.time), y: .value("kW", p.kw))
                    .foregroundStyle(Self.solarColor.opacity(0.18))
                    .interpolationMethod(.monotone)
            }
            ForEach(points) { p in
                LineMark(x: .value("Time", p.time), y: .value("kW", p.kw), series: .value("Series", p.series))
                    .foregroundStyle(by: .value("Series", p.series))
                    .lineStyle(StrokeStyle(lineWidth: 1.6))
                    .interpolationMethod(.monotone)
            }
        }
        .chartForegroundStyleScale([
            "Solar": Self.solarColor,
            "Home": Self.homeColor,
            "Model 3": Self.carColor,
            "Grid": Self.gridColor,
        ])
        .chartXScale(domain: start...end)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                AxisValueLabel()
            }
        }
        .chartLegend(position: .bottom, alignment: .leading, spacing: 10)
    }

    // MARK: Totals

    private var tiles: some View {
        let generated = model.dailyYield
        let houseAll: Double? = {
            guard let y = model.dailyYield, let i = model.importToday, let e = model.exportToday else { return nil }
            return max(y + i - e, 0)
        }()
        let home: Double? = houseAll.map { max($0 - (carKWh ?? 0), 0) }
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            tile("sun.max.fill", "Solar", kwh(generated), "generated", Self.solarColor)
            tile("house.fill", "Home", kwh(home), "used, excl. car", Self.homeColor)
            tile("car.side.fill", "Model 3", kwh(carKWh), "charged at home", Self.carColor)
            tile("leaf.fill", "Self-powered", model.selfPowered.map { "\(Int($0.rounded()))%" } ?? "—", "of home + car", TeslaDark.exporting)
            tile("arrow.down.circle.fill", "Grid import", kwh(model.importToday), "from TNB", Self.gridColor)
            tile("arrow.up.circle.fill", "Grid export", kwh(model.exportToday), "to TNB", Self.gridColor)
        }
    }

    private func kwh(_ v: Double?) -> String {
        v.map { String(format: "%.1f kWh", $0) } ?? "—"
    }

    private func tile(_ icon: String, _ title: String, _ value: String, _ caption: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(color)
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(TeslaDark.labelGrey)
            }
            Text(value).font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(caption).font(.system(size: 10.5)).foregroundStyle(TeslaDark.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(TeslaDark.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Loading

    private func load() async {
        guard let ha = HAClient.configured() else {
            error = "Set up Home Assistant first: Home tab → gear."
            return
        }
        loading = true
        defer { loading = false }
        await model.refresh()
        let start = Calendar.current.startOfDay(for: Date())
        do {
            let h = try await ha.history([Entity.solarPower, Entity.gridPower, Entity.carPower, Entity.carEnergy], since: start)
            points = PowerPoint.buckets(history: h, start: start, end: Date())
            if let e = h[Entity.carEnergy], let first = e.first?.1, let last = e.last?.1 {
                carKWh = max(last - first, 0)
            }
            error = nil
        } catch {
            self.error = "Couldn't load today's history: \(error.localizedDescription)"
        }
    }
}

/// One 5-minute average of one series, in kW.
struct PowerPoint: Identifiable {
    let series: String
    let time: Date
    let kw: Double
    var id: String { "\(series)-\(time.timeIntervalSince1970)" }

    static func buckets(history h: [String: [(Date, Double)]], start: Date, end: Date, step: TimeInterval = 300) -> [PowerPoint] {
        let count = max(1, Int(end.timeIntervalSince(start) / step))
        func series(_ entity: String) -> [Double?] {
            let pts = (h[entity] ?? []).sorted { $0.0 < $1.0 }
            var sums = [Double](repeating: 0, count: count)
            var counts = [Int](repeating: 0, count: count)
            var lastBefore: [Double?] = Array(repeating: nil, count: count)
            var last: Double?
            var i = 0
            for b in 0..<count {
                let bEnd = start.addingTimeInterval(Double(b + 1) * step)
                lastBefore[b] = last
                while i < pts.count, pts[i].0 < bEnd {
                    let k = Int(pts[i].0.timeIntervalSince(start) / step)
                    if k >= 0 && k < count { sums[k] += pts[i].1; counts[k] += 1 }
                    last = pts[i].1
                    i += 1
                }
            }
            // Mean of the readings in the bucket, otherwise carry the previous reading forward.
            var out: [Double?] = []
            var carry: Double?
            for b in 0..<count {
                if counts[b] > 0 { carry = sums[b] / Double(counts[b]) }
                else if carry == nil { carry = lastBefore[b] }
                out.append(carry)
            }
            return out
        }
        let solar = series(Entity.solarPower)
        let grid = series(Entity.gridPower)
        let car = series(Entity.carPower)
        var out: [PowerPoint] = []
        out.reserveCapacity(count * 4)
        for b in 0..<count {
            let t = start.addingTimeInterval(Double(b) * step + step / 2)
            let s = max(solar[b] ?? 0, 0) / 1000
            let g = (grid[b] ?? 0) / 1000
            let c = max(car[b] ?? 0, 0) / 1000
            out.append(PowerPoint(series: "Solar", time: t, kw: s))
            out.append(PowerPoint(series: "Home", time: t, kw: max(s + g - c, 0)))
            out.append(PowerPoint(series: "Model 3", time: t, kw: c))
            out.append(PowerPoint(series: "Grid", time: t, kw: g))
        }
        return out
    }
}
