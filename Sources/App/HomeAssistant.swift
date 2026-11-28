import Foundation
import Security

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Entity ids used by VoltTime (see homeassistant/volttime.yaml).
enum Entity {
    static let battery = "sensor.ultra_rouge_battery_level_tessie"
    static let limit = "number.ultra_rouge_charge_limit_tessie"
    static let plugged = "binary_sensor.tesla_wall_connector_vehicle_connected"
    static let charging = "switch.ultra_rouge_charge_2"
    static let readyTime = "input_datetime.volttime_ready_time"
    static let start = "input_datetime.volttime_start"
    static let buffer = "input_number.volttime_buffer"
    static let amps = "input_number.volttime_amps"
    static let voltage = "input_number.volttime_voltage"
    static let efficiency = "input_number.volttime_efficiency"
    static let capacity = "input_number.volttime_capacity"
    static let destination = "input_text.volttime_destination"
    static let active = "input_boolean.volttime_active"
    static let answered = "input_boolean.volttime_answered"
    static let notifyService = "mobile_app_ridhuans_iphone_15_pro"

    // My Home tab (was the "My Home" view of the Tesla dashboard in Home Assistant)
    static let chargingMode = "input_select.tesla_charging_mode"
    static let chargeCurrent = "number.ultra_rouge_charge_current_tessie"
    static let reminders = "input_text.volttime_reminders"          // "19:00,21:30"
    static let remindersOff = "input_boolean.volttime_reminders_off"
    static let solarPower = "sensor.inverter_active_power"
    static let gridPower = "sensor.grid_active_power"
    static let carPower = "sensor.tesla_wall_connector_tuya_meter_power"
    static let wallConnectorStatus = "sensor.tesla_wall_connector_status"
    static let wallConnectorAmps = "sensor.tesla_wall_connector_vehicle_current"
    static let scenario = "sensor.tesla_home_scenario"
    static let dailyYield = "sensor.inverter_daily_yield"
    static let selfPowered = "sensor.self_powered_today"
    static let importToday = "sensor.grid_import_today"
    static let exportToday = "sensor.grid_export_today"
    static let sun = "sun.sun"                          // sky on My Home: sun height
    static let weather = "weather.forecast_home"        // sky on My Home: rain / clouds (met.no)
}

enum Keychain {
    static let homeAssistant = "haToken"
    private static let service = "VoltTime"

    static func set(_ value: String, for key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var item = base
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
}

struct HAState {
    let state: String
    let attributes: [String: Any]
    var lastChanged: Date? = nil
    var number: Double? { Double(state) }
    var isOn: Bool { state == "on" }
    var isAvailable: Bool { state != "unavailable" && state != "unknown" }
}

struct HAClient {
    let baseURL: URL          // Tailscale (used away from home)
    var homeURL: URL? = nil   // home Wi-Fi, tried first
    let token: String

    static let urlKey = "haURL"

    static func configured() -> HAClient? {
        let d = UserDefaults.standard
        let away = d.string(forKey: urlKey) ?? ""
        let auto = d.object(forKey: HARoute.autoKey) as? Bool ?? true
        let home = d.string(forKey: HARoute.homeKey) ?? HARoute.defaultHome
        let token = Keychain.get(Keychain.homeAssistant) ?? ""
        // Nothing entered under Tailscale: not set up yet, unless a home address was typed in.
        if away.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let typed = d.string(forKey: HARoute.homeKey) else { return nil }
            return HAClient(urlString: typed, token: token)
        }
        return HAClient(urlString: away, token: token, home: auto ? home : nil)
    }

    static func url(from string: String) -> URL? {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if !s.contains("://") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        return URL(string: s)
    }

    init?(urlString: String, token: String, home: String? = nil) {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let u = HAClient.url(from: urlString) else { return nil }
        baseURL = u
        homeURL = home.flatMap { HAClient.url(from: $0) }
        self.token = t
    }

    /// "Home Wi-Fi" or "Tailscale", from the address that answered last; nil before any answer.
    static func routeName() async -> String? {
        guard let used = await HARoute.shared.lastUsed else { return nil }
        let home = url(from: UserDefaults.standard.string(forKey: HARoute.homeKey) ?? HARoute.defaultHome)
        return used == home ? "Home Wi-Fi" : "Tailscale"
    }

    /// The address to use right now.
    func currentBase() async -> URL {
        await HARoute.shared.base(home: homeURL, away: baseURL)
    }

    private func send(_ path: String, method: String = "GET", body: [String: Any]? = nil, timeout: TimeInterval = 20) async throws -> Data {
        let base = await currentBase()
        do {
            return try await send(path, to: base, method: method, body: body, timeout: timeout)
        } catch let error as URLError where error.code != .cancelled && homeURL != nil {
            await HARoute.shared.reset()
            // Reads may be repeated. A command is only repeated if it never reached Home Assistant,
            // so nothing (the autogate above all) can fire twice.
            let neverSent: [URLError.Code] = [.cannotConnectToHost, .cannotFindHost, .notConnectedToInternet]
            guard method == "GET" || neverSent.contains(error.code) else { throw error }
            var next = await currentBase()
            if next == base { next = base == baseURL ? (homeURL ?? baseURL) : baseURL }
            if next == homeURL, !(await HARoute.looksLikeHomeAssistant(next)) { throw error }
            guard next != base else { throw error }
            return try await send(path, to: next, method: method, body: body, timeout: timeout)
        }
    }

    private func send(_ path: String, to base: URL, method: String, body: [String: Any]?, timeout: TimeInterval) async throws -> Data {
        guard let url = URL(string: base.absoluteString + path) else { throw APIError(message: "Bad Home Assistant URL") }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError(message: "No response from Home Assistant") }
        if http.statusCode == 401 { throw APIError(message: "Home Assistant rejected the token") }
        if http.statusCode == 404 { throw APIError(message: "Not found in Home Assistant: \(path)") }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8)?.prefix(160) ?? ""
            throw APIError(message: "Home Assistant error \(http.statusCode) \(msg)")
        }
        await HARoute.shared.used(base)
        return data
    }

    func ping() async throws -> String {
        let data = try await send("/api/")
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let m = obj["message"] as? String { return m }
        return "OK"
    }

    func state(_ entity: String) async throws -> HAState {
        let data = try await send("/api/states/\(entity)")
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw APIError(message: "Unreadable state for \(entity)") }
        return HAState(state: (obj["state"] as? String) ?? "unknown", attributes: (obj["attributes"] as? [String: Any]) ?? [:],
                       lastChanged: (obj["last_changed"] as? String).flatMap(HAClient.parseISO))
    }

    /// Every entity id Home Assistant has (one request).
    func entityIDs() async throws -> [String] {
        let data = try await send("/api/states", timeout: 30)
        guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return list.compactMap { $0["entity_id"] as? String }
    }

    /// Reads many entities in parallel; missing ones are simply left out.
    func states(_ entities: [String]) async -> [String: HAState] {
        await withTaskGroup(of: (String, HAState?).self) { group in
            for e in entities {
                group.addTask { (e, try? await self.state(e)) }
            }
            var out: [String: HAState] = [:]
            for await (e, s) in group { if let s { out[e] = s } }
            return out
        }
    }

    func call(_ domain: String, _ service: String, _ data: [String: Any], timeout: TimeInterval = 20) async throws {
        _ = try await send("/api/services/\(domain)/\(service)", method: "POST", body: data, timeout: timeout)
    }

    // Convenience
    func setNumber(_ entity: String, _ value: Double) async throws {
        let domain = entity.components(separatedBy: ".").first ?? "input_number"
        try await call(domain, "set_value", ["entity_id": entity, "value": value])
    }

    func setText(_ entity: String, _ value: String) async throws {
        try await call("input_text", "set_value", ["entity_id": entity, "value": value])
    }

    func turnOn(_ entity: String) async throws {
        try await call("input_boolean", "turn_on", ["entity_id": entity])
    }

    func setTime(_ entity: String, minutes: Int) async throws {
        let t = String(format: "%02d:%02d:00", minutes / 60, minutes % 60)
        try await call("input_datetime", "set_datetime", ["entity_id": entity, "time": t])
    }

    /// Runs the VoltTime planning script (it writes the Tesla schedule; can take a while).
    func plan(limit: Double?) async throws {
        var data: [String: Any] = [:]
        if let limit { data["limit"] = limit }
        try await call("script", "volttime_plan", data, timeout: 120)
    }

    /// Raw bytes of any path, e.g. "/local/tesla_home_scenario1.png" (files in /config/www).
    func data(_ path: String, timeout: TimeInterval = 60) async throws -> Data {
        try await send(path, timeout: timeout)
    }

    /// Numeric history since `start` for several entities: entity -> [(time, value)], oldest first.
    func history(_ entities: [String], since start: Date, until end: Date? = nil) async throws -> [String: [(Date, Double)]] {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        var path = "/api/history/period/\(f.string(from: start))?filter_entity_id=\(entities.joined(separator: ","))&minimal_response&no_attributes"
        if let end { path += "&end_time=" + (f.string(from: end).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "") }
        let data = try await send(path, timeout: 60)
        guard let lists = try JSONSerialization.jsonObject(with: data) as? [[[String: Any]]] else {
            throw APIError(message: "Unreadable history from Home Assistant")
        }
        var out: [String: [(Date, Double)]] = [:]
        for list in lists {
            guard let id = list.first?["entity_id"] as? String else { continue }
            var pts: [(Date, Double)] = []
            pts.reserveCapacity(list.count)
            for item in list {
                guard let s = item["state"] as? String, let v = Double(s),
                      let t = (item["last_changed"] as? String).flatMap(HAClient.parseISO) else { continue }
                pts.append((t, v))
            }
            out[id] = pts
        }
        return out
    }

    /// "2026-11-15T06:44:58.123456+00:00" (any number of fraction digits, or none).
    static func parseISO(_ s: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: s) { return d }
        if let r = s.range(of: #"\.\d+"#, options: .regularExpression) {
            var t = s
            t.removeSubrange(r)
            return plain.date(from: t)
        }
        return nil
    }

    func clearAskNotification() async {
        try? await call("notify", Entity.notifyService, ["message": "clear_notification", "data": ["tag": "volttime_ask"]])
    }

    /// "2026-11-11 00:33:00" (input_datetime state, local time).
    static func parseLocal(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.date(from: s)
    }

    /// "05:45:00" → 345
    static func parseTimeOfDay(_ s: String) -> Int? {
        let p = s.split(separator: ":").compactMap { Int($0) }
        guard p.count >= 2 else { return nil }
        return p[0] * 60 + p[1]
    }
}
