import SwiftUI

// Impact data: Home Assistant long-term statistics, boiled down to one small summary per day and kept on the iPhone
// (Application Support/impact_days.json, ~20 KB a year). Each refresh only re-reads from the day before the last
// saved day, so the page opens instantly and stays fast.

/// One day's energy, all in kWh.
struct DaySummary: Codable, Equatable {
    var solar = 0.0      // generated (inverter)
    var imp = 0.0        // bought from TNB
    var exp = 0.0        // exported to TNB
    var car = 0.0        // into the Model 3 (Wall Connector meter)
    var carSolar = 0.0   // part of `car` covered by solar (solar serves the house first)

    static func + (a: DaySummary, b: DaySummary) -> DaySummary {
        DaySummary(solar: a.solar + b.solar, imp: a.imp + b.imp, exp: a.exp + b.exp, car: a.car + b.car, carSolar: a.carSolar + b.carSolar)
    }

    /// Home + car consumption.
    var used: Double { max(solar + imp - exp, 0) }
    var solarUsed: Double { max(solar - exp, 0) }
    /// Same formula as the HA "Self Powered Today" sensor.
    var selfPowered: Double? { used > 0 ? min(1, max(0, 1 - imp / used)) : nil }
    var carSolarShare: Double? { car > 0.05 ? min(1, carSolar / car) : nil }
}

/// Statistic ids, the same sensors as the Home Assistant Energy dashboard.
enum ImpactStat {
    static let solar = "sensor.inverter_daily_yield"
    static let imp = "sensor.power_meter_consumption"
    static let exp = "sensor.power_meter_exported"
    static let car = "sensor.tesla_wall_connector_tuya_meter_energy"
    static let all = [solar, imp, exp, car]

    static let forecastTomorrow = "sensor.energy_production_tomorrow"
    static let peakTomorrow = "sensor.power_highest_peak_time_tomorrow"
    static let odometer = "sensor.ultra_rouge_odometer_2"
    static let lifetimeEnergy = "sensor.ultra_rouge_lifetime_energy_used"

    /// Energy Commission, Grid Emission Factor 2024 (provisional), Peninsular Malaysia, kg CO2e per kWh.
    static let gridKgPerKWh = 0.740
    /// US EPA equivalency: one tree seedling grown for 10 years takes up about 60 kg CO2.
    static let kgPerTree = 60.0
    /// Wall to battery (same as the Home planner default).
    static let chargeEfficiency = 0.93
}

private struct ImpactCache: Codable {
    var firstDay: String?
    var days: [String: DaySummary]
}

@MainActor
final class ImpactModel: ObservableObject {
    @Published private(set) var days: [String: DaySummary] = [:]
    @Published private(set) var firstDay: Date?
    @Published var loading = false
    @Published var message: String?
    @Published var forecastTomorrow: Double?
    @Published var peakTomorrow: Date?
    @Published var kWhPerKm: Double?

    private let cal = Calendar.current
    private var lastRefresh: Date?

    static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("impact_days.json")
    }

    init() {
        if let d = try? Data(contentsOf: Self.fileURL), let c = try? JSONDecoder().decode(ImpactCache.self, from: d) {
            days = c.days
            firstDay = c.firstDay.flatMap { Self.keyFormatter.date(from: $0) }
        }
    }

    private func save() {
        let c = ImpactCache(firstDay: firstDay.map { Self.keyFormatter.string(from: $0) }, days: days)
        guard let d = try? JSONEncoder().encode(c) else { return }
        try? FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? d.write(to: Self.fileURL, options: .atomic)
    }

    // MARK: Totals

    func total(from start: Date, to end: Date) -> DaySummary {
        var t = DaySummary()
        var d = cal.startOfDay(for: start)
        while d < end {
            if let s = days[Self.keyFormatter.string(from: d)] { t = t + s }
            guard let n = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = n
        }
        return t
    }

    // MARK: Refresh

    func refresh(force: Bool = false) async {
        guard let ha = HAClient.configured() else {
            message = "Set up Home Assistant first: My Home → Settings → Connection."
            return
        }
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < 60 { return }
        guard !loading else { return }
        loading = true
        defer { loading = false }

        await refreshLive(ha)

        do {
            let ws = try await HAWebSocket.connect(ha)
            defer { ws.close() }

            if firstDay == nil {
                let monthly = try await ws.statistics([ImpactStat.solar, ImpactStat.imp], start: date(2024, 1, 1), end: Date(), period: "month")
                let starts = monthly.values.flatMap { $0.map(\.start) }
                guard let first = starts.min() else {
                    message = "No energy history in Home Assistant yet."
                    return
                }
                firstDay = cal.startOfDay(for: first)
            }
            guard let firstDay else { return }

            // Re-read from the day before the newest saved day (it may have been partial), or from the beginning.
            let today = cal.startOfDay(for: Date())
            let yesterday = cal.date(byAdding: .day, value: -1, to: today) ?? today
            var from = firstDay
            if let lastKey = days.keys.max(), let last = Self.keyFormatter.date(from: lastKey) {
                from = max(firstDay, cal.date(byAdding: .day, value: -1, to: last) ?? last)
            }

            var fresh: [String: DaySummary] = [:]
            // Hourly up to yesterday, a month at a time.
            var chunk = from
            while chunk < yesterday {
                let next = min(cal.date(byAdding: .month, value: 1, to: chunk) ?? yesterday, yesterday)
                let rows = try await ws.statistics(ImpactStat.all, start: chunk, end: next, period: "hour")
                merge(rows, into: &fresh)
                chunk = next
            }
            // Yesterday and today in 5-minute steps (finer car / solar split, and today's latest numbers).
            let rows = try await ws.statistics(ImpactStat.all, start: max(from, yesterday), end: Date(), period: "5minute")
            merge(rows, into: &fresh)

            for (k, v) in fresh { days[k] = v }
            lastRefresh = Date()
            message = nil
            save()
        } catch {
            message = days.isEmpty
                ? "Couldn't load energy history: \(error.localizedDescription)"
                : "Showing saved data. Couldn't update: \(error.localizedDescription)"
        }
    }

    /// Adds statistic rows (one per hour or 5 minutes) to per-day summaries, splitting the car's energy into solar
    /// and grid per step: solar covers the house first, the car gets whatever solar is left.
    private func merge(_ rows: [String: [HAWebSocket.Row]], into out: inout [String: DaySummary]) {
        var steps: [Date: DaySummary] = [:]
        func add(_ id: String, _ kp: WritableKeyPath<DaySummary, Double>) {
            for r in rows[id] ?? [] { steps[r.start, default: DaySummary()][keyPath: kp] += max(r.change, 0) }
        }
        add(ImpactStat.solar, \.solar)
        add(ImpactStat.imp, \.imp)
        add(ImpactStat.exp, \.exp)
        add(ImpactStat.car, \.car)
        for (start, step) in steps {
            var s = step
            let house = max(s.solar + s.imp - s.exp - s.car, 0)
            s.carSolar = min(s.car, max(s.solarUsed - house, 0))
            let key = Self.keyFormatter.string(from: start)
            out[key] = (out[key] ?? DaySummary()) + s
        }
    }

    private func refreshLive(_ ha: HAClient) async {
        let s = await ha.states([ImpactStat.forecastTomorrow, ImpactStat.peakTomorrow, ImpactStat.odometer, ImpactStat.lifetimeEnergy])
        forecastTomorrow = s[ImpactStat.forecastTomorrow]?.number
        peakTomorrow = s[ImpactStat.peakTomorrow].flatMap { HAClient.parseISO($0.state) }
        if let km = s[ImpactStat.odometer]?.number, let kwh = s[ImpactStat.lifetimeEnergy]?.number, km > 100, kwh > 10 {
            kWhPerKm = kwh / km
        }
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d)) ?? Date()
    }
}

// MARK: - Home Assistant websocket (long-term statistics are only available there)

final class HAWebSocket {
    struct Row {
        let start: Date
        let change: Double
    }

    private let task: URLSessionWebSocketTask
    private var nextID = 1

    private init(task: URLSessionWebSocketTask) { self.task = task }

    static func connect(_ ha: HAClient) async throws -> HAWebSocket {
        guard var c = URLComponents(url: ha.baseURL, resolvingAgainstBaseURL: false) else { throw APIError(message: "Bad Home Assistant URL") }
        c.scheme = (c.scheme == "https") ? "wss" : "ws"
        c.path = (c.path.hasSuffix("/") ? String(c.path.dropLast()) : c.path) + "/api/websocket"
        guard let url = c.url else { throw APIError(message: "Bad Home Assistant URL") }
        let task = URLSession.shared.webSocketTask(with: url)
        task.maximumMessageSize = 64 * 1024 * 1024
        task.resume()
        let ws = HAWebSocket(task: task)
        _ = try await ws.receive()   // auth_required
        try await ws.send(["type": "auth", "access_token": ha.token])
        let auth = try await ws.receive()
        guard auth["type"] as? String == "auth_ok" else {
            task.cancel(with: .goingAway, reason: nil)
            throw APIError(message: "Home Assistant rejected the token")
        }
        return ws
    }

    func close() { task.cancel(with: .goingAway, reason: nil) }

    private func send(_ obj: [String: Any]) async throws {
        let d = try JSONSerialization.data(withJSONObject: obj)
        try await task.send(.string(String(decoding: d, as: UTF8.self)))
    }

    private func receive() async throws -> [String: Any] {
        let msg = try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
            group.addTask { try await self.task.receive() }
            group.addTask {
                try await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                throw APIError(message: "Home Assistant took too long to answer")
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
        let data: Data
        switch msg {
        case .string(let s): data = Data(s.utf8)
        case .data(let d): data = d
        @unknown default: data = Data()
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// recorder/statistics_during_period, "change" per period. Returns statistic id -> rows.
    func statistics(_ ids: [String], start: Date, end: Date, period: String) async throws -> [String: [Row]] {
        let id = nextID
        nextID += 1
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        try await send([
            "id": id,
            "type": "recorder/statistics_during_period",
            "start_time": f.string(from: start),
            "end_time": f.string(from: end),
            "statistic_ids": ids,
            "period": period,
            "types": ["change"],
        ])
        while true {
            let r = try await receive()
            guard (r["id"] as? Int) == id else { continue }
            guard r["success"] as? Bool == true, let result = r["result"] as? [String: Any] else {
                let err = (r["error"] as? [String: Any])?["message"] as? String ?? "statistics request failed"
                throw APIError(message: "Home Assistant: \(err)")
            }
            var out: [String: [Row]] = [:]
            for (sid, value) in result {
                guard let list = value as? [[String: Any]] else { continue }
                out[sid] = list.compactMap { item in
                    let start: Date?
                    if let ms = item["start"] as? Double { start = Date(timeIntervalSince1970: ms / 1000) }
                    else if let ms = item["start"] as? Int { start = Date(timeIntervalSince1970: Double(ms) / 1000) }
                    else if let s = item["start"] as? String { start = HAClient.parseISO(s) }
                    else { start = nil }
                    guard let start, let change = (item["change"] as? Double) ?? (item["change"] as? Int).map(Double.init) else { return nil }
                    return Row(start: start, change: change)
                }
            }
            return out
        }
    }
}
