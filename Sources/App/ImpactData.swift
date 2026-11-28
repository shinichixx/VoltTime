import SwiftUI

// Energy data shared by Impact and Energy: one curve per day (EnergyData.swift), all kept in ONE small file on the
// iPhone (Application Support/energy.plist, ~280 KB a year). Daily totals are added up in memory, never saved twice.
// Recent days are kept in 5-minute steps (HA only keeps its 5-minute data ~10 days); older days come hourly.
// A day already saved in more detail is never replaced by a coarser copy.

/// Totals over a span, in the shape the Impact cards use.
struct DaySummary {
    var solar = 0.0
    var imp = 0.0
    var exp = 0.0
    var car = 0.0
    var carSolar = 0.0

    init(_ f: EnergyFlow) {
        solar = f.solar; imp = f.imp; exp = f.exp; car = f.car; carSolar = f.carSolar
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

    // Solar forecast sensors: Solcast's when present (found by name, since setups name them differently),
    // else Forecast.Solar's. Resolved once per launch by SolarSensors.resolve.
    static var forecastTomorrow: String { SolarSensors.current.tomorrow }
    static var forecastToday: String { SolarSensors.current.today }
    static var peakToday: String { SolarSensors.current.peakToday }
    static var peakTomorrow: String { SolarSensors.current.peakTomorrow }
    static let odometer = "sensor.ultra_rouge_odometer_2"
    static let lifetimeEnergy = "sensor.ultra_rouge_lifetime_energy_used"

    /// Energy Commission, Grid Emission Factor 2024 (provisional), Peninsular Malaysia, kg CO2e per kWh.
    static let gridKgPerKWh = 0.740
    /// US EPA equivalency: one tree seedling grown for 10 years takes up about 60 kg CO2.
    static let kgPerTree = 60.0
    /// Wall to battery (same as the Home planner default).
    static let chargeEfficiency = 0.93
}

struct Coverage {
    let have: Int
    let days: Int
    /// "No data for this date", "Data for 26 of 31 days", or nothing when complete (or still loading).
    func note(day: Bool, loading: Bool) -> String? {
        if loading || have >= days { return nil }
        if have == 0 { return day ? "No data for this date" : "No data for this period" }
        return "Data for \(have) of \(days) days"
    }
}

struct StoreFile: Codable {
    var first: String?
    var days: [String: Data]

    /// Reads an energy.plist (the app's own file, or one inside a backup).
    static func curves(from data: Data) -> [String: DayCurve]? {
        guard let f = try? PropertyListDecoder().decode(StoreFile.self, from: data) else { return nil }
        var c: [String: DayCurve] = [:]
        for (k, v) in f.days { if let curve = DayCurve(packed: v) { c[k] = curve } }
        return c
    }
}

@MainActor
final class EnergyStore: ObservableObject {
    /// Past days (saved) plus today (memory only, refreshed).
    @Published private(set) var curves: [String: DayCurve] = [:] {
        didSet { numberCache = [:]; forecastCache = [:]; liveDays = [:]; liveMonths = [:] }
    }
    // Worked-out figures, kept only until the saved energy changes.
    var numberCache: [String: ImpactNumbers] = [:]
    var forecastCache: [String: ForecastNumbers] = [:]
    var liveDays: [String: DayValue] = [:]       // today
    var liveMonths: [String: Double] = [:]       // this month's RM per exported kWh
    @Published private(set) var firstDay: Date?
    @Published var loading = false
    @Published var message: String?
    @Published var forecastTomorrow: Double?
    @Published var peakTomorrow: Date?
    @Published var forecastToday: Double?
    @Published var peakToday: Date?
    @Published var forecastReadAt: Date?      // when Solcast last changed today's forecast
    @Published var forecastNextRead: Date?    // estimate: 5 reads spread evenly from sunrise to sunset
    @Published var kWhPerKm: Double?
    /// Solcast's half-hourly forecast (kW) for today and tomorrow, when the sensor carries it.
    @Published var forecastCurveToday: [ForecastPoint] = []
    @Published var forecastCurveTomorrow: [ForecastPoint] = []

    private let cal = Calendar.current
    private var lastRefresh: Date?
    private var flowCache: [String: EnergyFlow] = [:]

    static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    nonisolated private static var supportDir: URL { AppData.support }
    nonisolated static var fileURL: URL { AppData.energy }

    init() {
        // Build 10 kept Impact's daily totals in their own file; everything now lives in energy.plist.
        try? FileManager.default.removeItem(at: Self.supportDir.appendingPathComponent("impact_days.json"))
        if let d = try? Data(contentsOf: Self.fileURL), let f = try? PropertyListDecoder().decode(StoreFile.self, from: d) {
            var c: [String: DayCurve] = [:]
            for (k, v) in f.days { if let curve = DayCurve(packed: v) { c[k] = curve } }
            curves = c
            firstDay = f.first.flatMap { Self.keyFormatter.date(from: $0) }
        }
    }

    private func key(_ d: Date) -> String { Self.keyFormatter.string(from: d) }
    private var todayKey: String { key(Date()) }

    private func save() {
        let today = todayKey
        var days: [String: Data] = [:]
        for (k, c) in curves where k < today { days[k] = c.packed() }   // finished days only
        let enc = PropertyListEncoder()
        enc.outputFormat = .binary
        guard let d = try? enc.encode(StoreFile(first: firstDay.map { key($0) }, days: days)) else { return }
        try? FileManager.default.createDirectory(at: Self.supportDir, withIntermediateDirectories: true)
        try? d.write(to: Self.fileURL, options: .atomic)
    }

    // MARK: Reading

    func curve(_ day: Date) -> DayCurve? { curves[key(day)] }

    func flow(_ day: Date) -> EnergyFlow? {
        let k = key(day)
        if let f = flowCache[k] { return f }
        guard let c = curves[k] else { return nil }
        let f = c.total
        flowCache[k] = f
        return f
    }

    func flowTotal(from start: Date, to end: Date) -> EnergyFlow {
        var t = EnergyFlow()
        var d = cal.startOfDay(for: start)
        while d < end {
            if let f = flow(d) { t = t + f }
            guard let n = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = n
        }
        return t
    }

    func total(from start: Date, to end: Date) -> DaySummary { DaySummary(flowTotal(from: start, to: end)) }

    /// How many days of a period (up to today) have saved energy.
    func coverage(_ r: PeriodRange) -> Coverage {
        let end = min(r.end, cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? r.end)
        var have = 0, days = 0
        var d = cal.startOfDay(for: r.start)
        while d < end {
            days += 1
            if curve(d) != nil { have += 1 }
            guard let n = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = n
        }
        return Coverage(have: have, days: days)
    }

    // MARK: Restore

    /// Adds days from a backup. A day already on the phone is only replaced by a copy with more detail.
    func merge(_ incoming: [String: DayCurve]) -> (added: Int, improved: Int) {
        var added = 0, improved = 0
        for (k, c) in incoming {
            if let old = curves[k] {
                guard c.minutes < old.minutes else { continue }
                improved += 1
            } else {
                added += 1
            }
            curves[k] = c
            flowCache[k] = nil
        }
        if let earliest = incoming.keys.min().flatMap({ Self.keyFormatter.date(from: $0) }),
           firstDay == nil || earliest < firstDay! {
            firstDay = earliest
        }
        save()
        return (added, improved)
    }

    // MARK: Refresh

    /// Fetches only what isn't on the phone yet: today, yesterday (may have been partial), any missing days, and
    /// recent days saved coarser than 5-minute (upgraded while HA still has the detail).
    func refresh(minAge: TimeInterval = 60) async {
        guard let ha = HAClient.configured() else {
            message = "Set up Home Assistant first: My Home → Settings → Connection."
            return
        }
        if let lastRefresh, Date().timeIntervalSince(lastRefresh) < minAge { return }
        guard !loading else { return }
        loading = true
        defer { loading = false }

        await refreshLive(ha)

        do {
            let ws = try await HAWebSocket.connect(ha)
            defer { ws.close() }

            if firstDay == nil {
                let monthly = try await ws.statistics([ImpactStat.solar, ImpactStat.imp], start: date(2024, 1, 1), end: Date(), period: "month")
                guard let first = monthly.values.flatMap({ $0.map(\.start) }).min() else {
                    message = "No energy history in Home Assistant yet."
                    return
                }
                firstDay = cal.startOfDay(for: first)
            }
            guard let firstDay else { return }

            let today = cal.startOfDay(for: Date())
            let yesterday = cal.date(byAdding: .day, value: -1, to: today) ?? today
            let recent = max(firstDay, cal.date(byAdding: .day, value: -9, to: today) ?? today)

            // Earliest day that needs (re)fetching.
            var from = yesterday
            var d = firstDay
            while d < yesterday {
                let c = curves[key(d)]
                if c == nil || (d >= recent && c!.minutes > 5) { from = d; break }
                d = cal.date(byAdding: .day, value: 1, to: d) ?? yesterday
            }
            from = max(from, firstDay)

            var fresh: [String: DayCurve] = [:]
            var chunk = from
            while chunk < recent {   // older days: hourly, a month at a time
                let next = min(cal.date(byAdding: .month, value: 1, to: chunk) ?? recent, recent)
                for (k, c) in try await fetch(ws, chunk, next, period: "hour") { fresh[k] = c }
                chunk = next
            }
            for (k, c) in try await fetch(ws, max(from, recent), Date(), period: "5minute") { fresh[k] = c }

            var updated = curves   // changed in one go, so the pages redraw once
            for (k, c) in fresh {
                // Keep an existing day that has more detail than the new copy.
                if let old = updated[k], old.minutes < c.minutes { continue }
                updated[k] = c
                flowCache[k] = nil
            }
            curves = updated
            lastRefresh = Date()
            message = nil
            save()
        } catch {
            message = curves.isEmpty
                ? "Couldn't load energy history: \(error.localizedDescription)"
                : "Showing saved data. Couldn't update: \(error.localizedDescription)"
        }
    }

    /// Statistics rows -> per-day curves in 5-minute or hourly slots.
    private func fetch(_ ws: HAWebSocket, _ start: Date, _ end: Date, period: String) async throws -> [String: DayCurve] {
        guard start < end else { return [:] }
        let rows = try await ws.statistics(ImpactStat.all, start: start, end: end, period: period)
        let minutes = period == "hour" ? 60 : 5
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

    /// Tomorrow's solar forecast only moves a few % during the day, so it's read once a day (the first time the app
    /// opens that day) and kept just for that day. No history of it is saved.
    private func loadForecastIfToday() {
        let d = UserDefaults.standard
        guard d.string(forKey: "impact.forecastDay") == Self.keyFormatter.string(from: Date()) else {
            forecastTomorrow = nil   // a new day (or never fetched): read it again
            peakTomorrow = nil
            return
        }
        if d.object(forKey: "impact.forecastKWh") != nil { forecastTomorrow = d.double(forKey: "impact.forecastKWh") }
        if d.object(forKey: "impact.forecastPeak") != nil { peakTomorrow = Date(timeIntervalSince1970: d.double(forKey: "impact.forecastPeak")) }
    }

    private func refreshLive(_ ha: HAClient) async {
        await SolarSensors.resolve(ha)
        let needForecast = true   // Solcast refines tomorrow during the day: read it each time
        var ids = [ImpactStat.odometer, ImpactStat.lifetimeEnergy, ImpactStat.forecastToday, ImpactStat.peakToday]
        if needForecast { ids += [ImpactStat.forecastTomorrow, ImpactStat.peakTomorrow] }
        if SolarSensors.current.isSolcast { ids.append("sun.sun") }
        let s = await ha.states(ids.filter { !$0.isEmpty })
        let k = SolarSensors.current.scale
        if needForecast, let raw = s[ImpactStat.forecastTomorrow]?.number {
            let kwh = raw * k
            forecastTomorrow = kwh
            peakTomorrow = s[ImpactStat.peakTomorrow].flatMap { HAClient.parseISO($0.state) }
            let d = UserDefaults.standard
            d.set(Self.keyFormatter.string(from: Date()), forKey: "impact.forecastDay")
            d.set(kwh, forKey: "impact.forecastKWh")
            if let p = peakTomorrow { d.set(p.timeIntervalSince1970, forKey: "impact.forecastPeak") } else { d.removeObject(forKey: "impact.forecastPeak") }
        }
        forecastToday = s[ImpactStat.forecastToday]?.number.map { $0 * k } ?? forecastToday
        let ct = Self.detailed(s[ImpactStat.forecastToday]); if !ct.isEmpty { forecastCurveToday = ct }
        let cm = Self.detailed(s[ImpactStat.forecastTomorrow]); if !cm.isEmpty { forecastCurveTomorrow = cm }
        peakToday = s[ImpactStat.peakToday].flatMap { HAClient.parseISO($0.state) } ?? peakToday
        if SolarSensors.current.isSolcast {
            forecastReadAt = s[ImpactStat.forecastToday]?.lastChanged ?? forecastReadAt
            forecastNextRead = Self.nextSolcastRead(sun: s["sun.sun"])
        }
        await SolarForecastLog.shared.update(ha)
        if let v = forecastToday { SolarForecastLog.shared.noteToday(v) }
        if let km = s[ImpactStat.odometer]?.number, let kwh = s[ImpactStat.lifetimeEnergy]?.number, km > 100, kwh > 10 {
            kWhPerKm = kwh / km
        }
    }

    /// Solcast (auto update, 5 divisions) reads at sunrise and then every fifth of the daylight. Estimate only:
    /// it adds a few minutes of random offset.
    static func nextSolcastRead(sun: HAState?, now: Date = Date()) -> Date? {
        guard let a = sun?.attributes,
              let nr = (a["next_rising"] as? String).flatMap(HAClient.parseISO),
              let ns = (a["next_setting"] as? String).flatMap(HAClient.parseISO) else { return nil }
        let cal = Calendar.current
        let rise = cal.isDate(nr, inSameDayAs: now) ? nr : nr.addingTimeInterval(-86400)
        let set = cal.isDate(ns, inSameDayAs: now) ? ns : ns.addingTimeInterval(-86400)
        guard set > rise else { return nil }
        let step = set.timeIntervalSince(rise) / 5
        for i in 0..<5 {
            let t = rise.addingTimeInterval(Double(i) * step)
            if t > now { return t }
        }
        return cal.isDate(nr, inSameDayAs: now) ? nil : nr   // after the last read: tomorrow at sunrise
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
        let base = await ha.currentBase()
        guard var c = URLComponents(url: base, resolvingAgainstBaseURL: false) else { throw APIError(message: "Bad Home Assistant URL") }
        c.scheme = (c.scheme == "https") ? "wss" : "ws"
        c.path = (c.path.hasSuffix("/") ? String(c.path.dropLast()) : c.path) + "/api/websocket"
        guard let url = c.url else { throw APIError(message: "Bad Home Assistant URL") }
        let task = URLSession.shared.webSocketTask(with: url)
        task.maximumMessageSize = 64 * 1024 * 1024
        task.resume()
        let ws = HAWebSocket(task: task)
        let auth: [String: Any]
        do {
            _ = try await ws.receive()   // auth_required
            try await ws.send(["type": "auth", "access_token": ha.token])
            auth = try await ws.receive()
        } catch {
            await HARoute.shared.reset()   // pick the address again next time
            throw error
        }
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


/// Which entities hold the solar forecast.
struct ForecastPoint {
    let time: Date   // middle of the period
    let kw: Double
}

extension EnergyStore {
    /// Solcast's "detailedForecast" (half-hourly) or "detailedHourly" attribute, as kW points.
    static func detailed(_ st: HAState?) -> [ForecastPoint] {
        guard let a = st?.attributes else { return [] }
        let half = a["detailedForecast"] as? [[String: Any]]
        let list = half ?? (a["detailedHourly"] as? [[String: Any]]) ?? []
        let mid: TimeInterval = half != nil ? 900 : 1800
        var out: [ForecastPoint] = []
        for e in list {
            guard let t = (e["period_start"] as? String).flatMap({ HAClient.parseISO($0) }) else { continue }
            let raw = e["pv_estimate"]
            guard let v = (raw as? NSNumber)?.doubleValue ?? (raw as? String).flatMap(Double.init) else { continue }
            out.append(ForecastPoint(time: t.addingTimeInterval(mid), kw: v))
        }
        if let mx = out.map(\.kw).max(), mx > 50 { out = out.map { ForecastPoint(time: $0.time, kw: $0.kw / 1000) } }
        return out.sorted { $0.time < $1.time }
    }
}

struct SolarSensors {
    var today = "sensor.energy_production_today"
    var tomorrow = "sensor.energy_production_tomorrow"
    var peakToday = "sensor.power_highest_peak_time_today"
    var peakTomorrow = "sensor.power_highest_peak_time_tomorrow"
    var isSolcast = false
    /// Multiply a reading by this to get kWh (Solcast can report Wh).
    var scale = 1.0

    static var current = SolarSensors()
    private static var resolved = false

    /// The Solcast sensors set up in Home Assistant (roof site "Mezzanine").
    private static let mezzanine = SolarSensors(
        today: "sensor.mezzanine_solcast_pv_forecast_forecast_today",
        tomorrow: "sensor.mezzanine_solcast_pv_forecast_forecast_tomorrow",
        peakToday: "sensor.mezzanine_solcast_pv_forecast_peak_time_today",
        peakTomorrow: "sensor.mezzanine_solcast_pv_forecast_peak_time_tomorrow",
        isSolcast: true)

    @MainActor static func resolve(_ ha: HAClient) async {
        guard !resolved else { return }
        var pick: SolarSensors?
        if let st = try? await ha.state(mezzanine.today), st.isAvailable {
            pick = mezzanine
        } else if let ids = try? await ha.entityIDs() {
            let solcast = ids.filter { $0.hasPrefix("sensor.") && $0.contains("solcast") }
            func find(_ suf: String) -> String? { solcast.first { $0.hasSuffix(suf) } }
            if let t = find("_forecast_today"), let tm = find("_forecast_tomorrow") {
                pick = SolarSensors(today: t, tomorrow: tm, peakToday: find("_peak_time_today") ?? "",
                                    peakTomorrow: find("_peak_time_tomorrow") ?? "", isSolcast: true)
            }
        } else { return }   // Home Assistant not reachable: try again next refresh
        resolved = true
        guard var s = pick else { return }
        // Work out the unit from the sensor itself.
        if let st = try? await ha.state(s.today) {
            switch (st.attributes["unit_of_measurement"] as? String ?? "").lowercased() {
            case "wh": s.scale = 0.001
            case "mwh": s.scale = 1000
            case "kwh": s.scale = 1
            default: s.scale = (st.number ?? 0) > SolarForecastLog.maxDay ? 0.001 : 1
            }
        }
        current = s
        SolarForecastLog.shared.noteSolcast()
    }
}
