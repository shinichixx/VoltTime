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
    var number: Double? { Double(state) }
    var isOn: Bool { state == "on" }
    var isAvailable: Bool { state != "unavailable" && state != "unknown" }
}

struct HAClient {
    let baseURL: URL
    let token: String

    static let urlKey = "haURL"

    static func configured() -> HAClient? {
        HAClient(urlString: UserDefaults.standard.string(forKey: urlKey) ?? "", token: Keychain.get(Keychain.homeAssistant) ?? "")
    }

    init?(urlString: String, token: String) {
        var s = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty || t.isEmpty { return nil }
        if !s.contains("://") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        guard let u = URL(string: s) else { return nil }
        baseURL = u
        self.token = t
    }

    private func send(_ path: String, method: String = "GET", body: [String: Any]? = nil, timeout: TimeInterval = 20) async throws -> Data {
        guard let url = URL(string: baseURL.absoluteString + path) else { throw APIError(message: "Bad Home Assistant URL") }
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
        return HAState(state: (obj["state"] as? String) ?? "unknown", attributes: (obj["attributes"] as? [String: Any]) ?? [:])
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
