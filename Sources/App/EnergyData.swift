import SwiftUI

// Day curves for the Energy page: energy per 15-minute slot (kWh) for solar, grid import, grid export and the car.
// Past days are kept on the iPhone (Application Support/energy_days/YYYY-MM-DD.json, ~2–3 KB a day), so they open
// instantly and keep 15-minute detail even after Home Assistant has thrown its 5-minute statistics away (~10 days).
// Days older than that which were never saved come from HA's hourly statistics.

struct DayCurve: Codable {
    var minutes: Int          // slot length: 15, or 60 for days only available hourly
    var solar: [Float]
    var imp: [Float]
    var exp: [Float]
    var car: [Float]

    var count: Int { solar.count }

    init(minutes: Int) {
        self.minutes = minutes
        let n = 1440 / minutes
        solar = Array(repeating: 0, count: n)
        imp = solar
        exp = solar
        car = solar
    }

    var isEmpty: Bool { solar.allSatisfy { $0 == 0 } && imp.allSatisfy { $0 == 0 } && car.allSatisfy { $0 == 0 } }

    /// The same split as Impact: solar serves the house first, the car gets what's left, the rest is exported.
    func flow(_ i: Int) -> EnergyFlow {
        .step(solar: Double(solar[i]), imp: Double(imp[i]), exp: Double(exp[i]), car: Double(car[i]))
    }

    var total: EnergyFlow {
        (0..<count).reduce(EnergyFlow()) { $0 + flow($1) }
    }
}

/// Energy (kWh) over some span, and where it went. Every field adds up across slots and days.
struct EnergyFlow {
    var solar = 0.0      // generated
    var imp = 0.0        // from TNB
    var exp = 0.0        // to TNB
    var car = 0.0        // into the Model 3
    var carSolar = 0.0   // car energy covered by solar
    var homeSolar = 0.0  // house (excl. car) covered by solar
    var homeGrid = 0.0   // house (excl. car) from the grid

    var carGrid: Double { max(car - carSolar, 0) }
    var house: Double { homeSolar + homeGrid }

    static func + (a: EnergyFlow, b: EnergyFlow) -> EnergyFlow {
        EnergyFlow(solar: a.solar + b.solar, imp: a.imp + b.imp, exp: a.exp + b.exp, car: a.car + b.car,
                   carSolar: a.carSolar + b.carSolar, homeSolar: a.homeSolar + b.homeSolar, homeGrid: a.homeGrid + b.homeGrid)
    }

    /// One time step: solar serves the house first, the car gets what's left, the rest is exported.
    static func step(solar s: Double, imp i: Double, exp e: Double, car c: Double) -> EnergyFlow {
        let solarUsed = max(s - e, 0)
        let house = max(s + i - e - c, 0)
        let carSolar = min(c, max(solarUsed - house, 0))
        let homeSolar = min(house, max(solarUsed - carSolar, 0))
        return EnergyFlow(solar: s, imp: i, exp: e, car: c, carSolar: carSolar, homeSolar: homeSolar, homeGrid: max(house - homeSolar, 0))
    }

    /// From a saved daily summary (its car split was worked out in 5-minute / hourly steps).
    init(_ d: DaySummary) {
        let homeSolar = max(d.solarUsed - d.carSolar, 0)
        self.init(solar: d.solar, imp: d.imp, exp: d.exp, car: d.car, carSolar: d.carSolar,
                  homeSolar: homeSolar, homeGrid: max(d.used - d.car - homeSolar, 0))
    }

    init(solar: Double = 0, imp: Double = 0, exp: Double = 0, car: Double = 0,
         carSolar: Double = 0, homeSolar: Double = 0, homeGrid: Double = 0) {
        self.solar = solar; self.imp = imp; self.exp = exp; self.car = car
        self.carSolar = carSolar; self.homeSolar = homeSolar; self.homeGrid = homeGrid
    }
}

@MainActor
final class EnergyModel: ObservableObject {
    @Published var loading = false
    @Published var message: String?
    private var memory: [String: DayCurve] = [:]
    private var todayFetched: Date?
    private var prefetched = false
    private let cal = Calendar.current

    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("energy_days", isDirectory: true)
    }

    private func key(_ d: Date) -> String { ImpactModel.keyFormatter.string(from: d) }

    private func loadSaved(_ k: String) -> DayCurve? {
        if let c = memory[k] { return c }
        guard let d = try? Data(contentsOf: Self.folder.appendingPathComponent("\(k).json")),
              let c = try? JSONDecoder().decode(DayCurve.self, from: d) else { return nil }
        memory[k] = c
        return c
    }

    private func save(_ c: DayCurve, _ k: String) {
        memory[k] = c
        guard let d = try? JSONEncoder().encode(c) else { return }
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        try? d.write(to: Self.folder.appendingPathComponent("\(k).json"), options: .atomic)
    }

    /// Saved curve for a past day, without touching the network (for an instant first draw).
    func cached(_ day: Date) -> DayCurve? {
        cal.isDateInToday(day) ? memory[key(day)] : loadSaved(key(day))
    }

    /// Curve for a day: saved copy for past days, otherwise fetched (and saved, unless it's today).
    func curve(_ day: Date) async -> DayCurve? {
        let start = cal.startOfDay(for: day)
        let k = key(start)
        let isToday = cal.isDateInToday(start)
        if !isToday, let c = loadSaved(k), c.minutes == 15 || start < recentLimit { return c }
        if isToday, let c = memory[k], let t = todayFetched, Date().timeIntervalSince(t) < 120 { return c }
        guard let ha = HAClient.configured() else { message = "Set up Home Assistant first."; return loadSaved(k) }
        loading = true
        defer { loading = false }
        do {
            let ws = try await HAWebSocket.connect(ha)
            defer { ws.close() }
            let end = isToday ? Date() : (cal.date(byAdding: .day, value: 1, to: start) ?? start)
            var curves = try await fetch(ws, start, end, period: "5minute")
            if curves[k] == nil || curves[k]!.isEmpty {
                curves = try await fetch(ws, start, end, period: "hour")
            }
            message = nil
            guard let c = curves[k] else { return loadSaved(k) }
            if isToday { memory[k] = c; todayFetched = Date() } else { save(c, k) }
            return c
        } catch {
            message = "Couldn't load this day: \(error.localizedDescription)"
            return loadSaved(k)
        }
    }

    /// HA keeps 5-minute statistics for ~10 days; anything older only exists hourly.
    private var recentLimit: Date { cal.date(byAdding: .day, value: -9, to: cal.startOfDay(for: Date())) ?? Date() }

    /// At launch: save the last 9 finished days in 15-minute detail before HA drops its 5-minute data.
    func prefetchRecent() async {
        guard !prefetched, let ha = HAClient.configured() else { return }
        prefetched = true
        let today = cal.startOfDay(for: Date())
        let missing = (1...9).compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
            .filter { loadSaved(key($0))?.minutes != 15 }
        guard let first = missing.min() else { return }
        do {
            let ws = try await HAWebSocket.connect(ha)
            defer { ws.close() }
            let curves = try await fetch(ws, first, today, period: "5minute")
            for d in missing {
                let k = key(d)
                if let c = curves[k], !c.isEmpty { save(c, k) }
            }
        } catch {
            prefetched = false   // try again next launch
        }
    }

    /// Statistics rows -> per-day curves in 15-minute (or hourly) slots.
    private func fetch(_ ws: HAWebSocket, _ start: Date, _ end: Date, period: String) async throws -> [String: DayCurve] {
        let rows = try await ws.statistics(ImpactStat.all, start: start, end: end, period: period)
        let minutes = period == "hour" ? 60 : 15
        var out: [String: DayCurve] = [:]
        func add(_ id: String, _ kp: WritableKeyPath<DayCurve, [Float]>) {
            for r in rows[id] ?? [] {
                let dayStart = cal.startOfDay(for: r.start)
                let slot = Int(r.start.timeIntervalSince(dayStart) / 60) / minutes
                let k = key(dayStart)
                var c = out[k] ?? DayCurve(minutes: minutes)
                guard slot >= 0 && slot < c.count else { continue }
                c[keyPath: kp][slot] += Float(max(r.change, 0))
                out[k] = c
            }
        }
        add(ImpactStat.solar, \.solar)
        add(ImpactStat.imp, \.imp)
        add(ImpactStat.exp, \.exp)
        add(ImpactStat.car, \.car)
        return out
    }
}
