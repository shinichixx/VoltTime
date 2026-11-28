import Foundation

// Car data straight from Tessie (api.tessie.com), not through Home Assistant.
// Reading uses Tessie's cached state, so opening the app never wakes the car; only commands do.

struct TessieClient {
    let token: String
    static let tokenKey = "tessieToken"          // Keychain
    static let vinKey = "car.vin"                // UserDefaults
    private static let base = "https://api.tessie.com"

    static func configured() -> TessieClient? {
        guard let t = Keychain.get(tokenKey)?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return TessieClient(token: t)
    }

    private func get(_ path: String, query: [String: String] = [:], timeout: TimeInterval = 30) async throws -> Data {
        var c = URLComponents(string: Self.base + path)!
        if !query.isEmpty { c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = c.url else { throw APIError(message: "Bad Tessie address") }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError(message: "No answer from Tessie") }
        if http.statusCode == 401 || http.statusCode == 403 { throw APIError(message: "Tessie rejected the token") }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8)?.prefix(140) ?? ""
            throw APIError(message: "Tessie error \(http.statusCode) \(msg)")
        }
        return data
    }

    private func post(_ path: String, body: [String: Any]) async throws -> Data {
        guard let url = URL(string: Self.base + path) else { throw APIError(message: "Bad Tessie address") }
        var req = URLRequest(url: url, timeoutInterval: 60)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8)?.prefix(140) ?? ""
            throw APIError(message: "Tessie error \(msg)")
        }
        return data
    }

    private func json(_ d: Data) -> [String: Any] { (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:] }

    // MARK: Reading

    func vehicles() async throws -> [TessieVehicle] {
        let obj = json(try await get("/vehicles", query: ["only_active": "true"]))
        let results = obj["results"] as? [[String: Any]] ?? []
        return results.compactMap { r in
            guard let vin = r["vin"] as? String else { return nil }
            let last = r["last_state"] as? [String: Any]
            let name = (last?["display_name"] as? String) ?? ((last?["vehicle_state"] as? [String: Any])?["vehicle_name"] as? String) ?? vin
            return TessieVehicle(vin: vin, name: name)
        }
    }

    /// Full state, as Tessie last saw it (doesn't wake the car).
    /// `live` asks the car itself (used just after a command, when the car is awake anyway).
    func state(_ vin: String, live: Bool = false) async throws -> [String: Any] {
        json(try await get("/\(vin)/state", query: ["use_cache": live ? "false" : "true"]))
    }

    func battery(_ vin: String) async throws -> [String: Any] { json(try await get("/\(vin)/battery")) }

    func location(_ vin: String) async throws -> [String: Any] { json(try await get("/\(vin)/location")) }

    func batteryHealth(_ vin: String) async throws -> [String: Any]? {
        let obj = json(try await get("/battery_health", query: ["distance_format": "km"]))
        let all = obj["results"] as? [[String: Any]] ?? []
        return all.first { ($0["vin"] as? String) == vin } ?? all.first
    }

    /// The car's past states over a timeframe (Tessie keeps them; Tesla doesn't). One state every `interval`
    /// seconds, km, in the phone's time zone. Returns one dictionary per state, whichever shape Tessie sends.
    func history(_ vin: String, from: Date, to: Date, interval: Int) async throws -> [[String: Any]] {
        let obj = json(try await get("/\(vin)/states", query: [
            "from": "\(Int(from.timeIntervalSince1970))",
            "to": "\(Int(to.timeIntervalSince1970))",
            "interval": "\(interval)",
            "condense": "false",
            "distance_format": "km",
            "timezone": TimeZone.current.identifier,
        ], timeout: 90))
        if let list = obj["results"] as? [[String: Any]] { return list }
        // Condensed form: parallel arrays with plural names (timestamps, battery_levels, …).
        guard let c = obj["results"] as? [String: Any], let ts = c["timestamps"] as? [Any] else { return [] }
        var out = Array(repeating: [String: Any](), count: ts.count)
        for (k, v) in c {
            guard let arr = v as? [Any], arr.count == ts.count else { continue }
            let single = k == "timestamps" ? "timestamp" : (k.hasSuffix("s") ? String(k.dropLast()) : k)
            for i in arr.indices where !(arr[i] is NSNull) { out[i][single] = arr[i] }
        }
        return out
    }

    // MARK: Commands

    /// GET /{vin}/command/{name}; waits until the car has done it.
    func command(_ vin: String, _ name: String, _ params: [String: String] = [:]) async throws {
        var q = params
        q["wait_for_completion"] = "true"
        let obj = json(try await get("/\(vin)/command/\(name)", query: q, timeout: 90))
        if let ok = obj["result"] as? Bool, !ok {
            throw APIError(message: (obj["reason"] as? String).map { "Vehicle said: \($0)" } ?? "The vehicle didn't do it")
        }
    }

    func wake(_ vin: String) async throws { _ = try await get("/\(vin)/wake", timeout: 90) }

    /// Nearest Supercharger to the car, through Tessie's Tesla Fleet API pass-through.
    func nearestSupercharger(_ vin: String) async throws -> (name: String, lat: Double, lon: Double) {
        let obj = json(try await get("/api/1/vehicles/\(vin)/nearby_charging_sites", timeout: 60))
        let resp = obj["response"] as? [String: Any] ?? [:]
        let sites = resp["superchargers"] as? [[String: Any]] ?? []
        guard let s = sites.first, let loc = s["location"] as? [String: Any],
              let lat = (loc["lat"] as? Double) ?? (loc["latitude"] as? Double),
              let lon = (loc["long"] as? Double) ?? (loc["longitude"] as? Double) else {
            throw APIError(message: "No Supercharger found near the vehicle")
        }
        return ((s["name"] as? String) ?? "Supercharger", lat, lon)
    }

    /// Sends a destination to the car's navigation; navigating to a Supercharger makes the car warm the battery.
    func navigate(_ vin: String, lat: Double, lon: Double) async throws {
        _ = try await post("/api/1/vehicles/\(vin)/command/navigation_gps_request", body: ["lat": lat, "lon": lon, "order": 1])
    }
}

struct TessieVehicle: Identifiable, Hashable {
    let vin: String
    let name: String
    var id: String { vin }
}

// MARK: - What the page shows

struct CarSnapshot: Codable, Equatable {
    var name = "Ultra Rouge"
    var state = "unknown"            // online / asleep / offline
    var soc: Double?
    var rangeKm: Double?
    var limit: Double?
    var chargingState = ""           // Charging / Stopped / Complete / Disconnected / NoPower
    var chargeAmps: Double?
    var chargeAmpsMax: Double?
    var chargerPowerKW: Double?
    var chargerVoltage: Double?
    var energyAddedKWh: Double?
    var minutesToLimit: Double?
    var cableConnected = false
    var portOpen = false
    var insideC: Double?
    var outsideC: Double?
    var climateOn = false
    var setTempC: Double?
    var keeperMode = "off"
    var batteryHeater = false
    var locked: Bool?
    var sentry = false
    var valet = false
    var windowsOpen: [Bool] = [false, false, false, false]   // FL FR RL RR
    var doorsOpen = false
    var trunkOpen = false
    var frunkOpen = false
    var tyres: [Double?] = [nil, nil, nil, nil]               // bar, FL FR RL RR
    var odometerKm: Double?
    var gear = "P"
    var speedKmh: Double?
    var lat: Double?
    var lon: Double?
    var address: String?
    var savedLocation: String?
    var packTempC: Double?
    var lifetimeKWh: Double?
    var updated: Date?
    // Build 33: controls and tyres pages
    var seatCool: [Int]? = nil           // driver, passenger (0–3)
    var overheat: String? = nil          // Off / On / FanOnly
    var bioweapon: Bool? = nil
    var defrost: Bool? = nil
    var guest: Bool? = nil
    var tyresRead: Date? = nil
    // Build 34: bottom block
    var vin: String? = nil
    var carType: String? = nil       // model3, modely…
    var trim: String? = nil          // trim_badging, e.g. 74d
    var software: String? = nil      // 2026.44.1
    // Build 35: live battery
    var packVoltage: Double? = nil
    var packCurrent: Double? = nil
    var energyLeftKWh: Double? = nil
    // Build 36: each door, and which way the car points
    var doors: [Bool]? = nil             // FL FR RL RR (df, pf, dr, pr)
    var heading: Double? = nil           // degrees, 0 = north
    var located: Date? = nil             // last /location read
    // Build 37: power modes (from the car when Tessie reports them, otherwise the last one VoltTime sent)
    var lowPower: Bool? = nil
    var accessoryPower: Bool? = nil
    // Build 42: what the plugged-in charger allows
    var fastCharger: Bool? = nil         // DC fast charger (Supercharger, CCS DC)
    var pilotAmps: Double? = nil         // amps the AC charger offers the car

    /// Plugged into an AC charger (Wall Connector, destination, third-party Type 2, 3-pin portable).
    var onAC: Bool { cableConnected && fastCharger != true }

    /// Highest amps VoltTime offers: what the charger offers (or the car's own maximum, if lower).
    /// A charger offering 13 A or less is the 3-pin portable charger: stop at 10 A to go easy on the socket.
    var ampsCap: Int {
        // The charger's offer only counts when it is below what's requested (it really is limiting); some chargers
        // report an offer that just follows the current setting, which would stop the right arrow early.
        let req = chargeAmps ?? 0
        let pilot = pilotAmps.flatMap { $0 < req - 0.5 ? $0 : nil }
        let offered = [pilot, chargeAmpsMax].compactMap { $0 }.filter { $0 >= 5 }.min() ?? 32
        let cap = offered <= 13 ? min(offered, 10) : offered
        return max(5, Int(cap))
    }

    var modelName: String {
        switch carType?.lowercased() {
        case "model3": return "MODEL 3"
        case "modely": return "MODEL Y"
        case "models", "models2": return "MODEL S"
        case "modelx": return "MODEL X"
        case "cybertruck": return "CYBERTRUCK"
        default: return "MODEL 3"
        }
    }
    var trimName: String? {
        guard let t = trim?.lowercased(), !t.isEmpty else { return nil }
        if t.hasPrefix("p") { return "Performance" }
        if let n = Int(t.filter(\.isNumber)), n >= 70 { return "Long Range" }
        return "Standard Range"
    }

    var asleep: Bool { state != "online" }
    var charging: Bool { chargingState == "Charging" }
    var atHome: Bool { (savedLocation ?? "").localizedCaseInsensitiveContains("home") }
    var anyWindowOpen: Bool { windowsOpen.contains(true) }
    /// Door i (FL FR RL RR) open; falls back to "a door is open" on older saved data.
    func doorOpen(_ i: Int) -> Bool { doors?[i] ?? false }
    /// Battery preconditioning as VoltTime does it: A/C on and set to 19°C (or the car warming the pack).
    var preconditioning: Bool { batteryHeater || (climateOn && abs((setTempC ?? 0) - 19) < 0.3) }
    var kmPerPercent: Double? {
        guard let s = soc, s > 0, let r = rangeKm else { return nil }
        return r / s
    }

    mutating func apply(state j: [String: Any]) {
        func d(_ o: [String: Any]?, _ k: String) -> Double? {
            if let v = o?[k] as? Double { return v }
            if let v = o?[k] as? Int { return Double(v) }
            return nil
        }
        let cs = j["charge_state"] as? [String: Any]
        let cl = j["climate_state"] as? [String: Any]
        let vs = j["vehicle_state"] as? [String: Any]
        let ds = j["drive_state"] as? [String: Any]
        if let n = j["display_name"] as? String, !n.isEmpty { name = n }
        state = (j["state"] as? String) ?? state
        soc = d(cs, "battery_level") ?? soc
        if let mi = d(cs, "battery_range") { rangeKm = mi * 1.609344 }
        limit = d(cs, "charge_limit_soc") ?? limit
        chargingState = (cs?["charging_state"] as? String) ?? chargingState
        chargeAmps = d(cs, "charge_current_request") ?? d(cs, "charge_amps") ?? chargeAmps
        chargeAmpsMax = d(cs, "charge_current_request_max") ?? chargeAmpsMax
        chargerPowerKW = d(cs, "charger_power")
        chargerVoltage = d(cs, "charger_voltage")
        energyAddedKWh = d(cs, "charge_energy_added")
        minutesToLimit = d(cs, "minutes_to_full_charge")
        if let cable = cs?["conn_charge_cable"] as? String { cableConnected = cable != "<invalid>" && !cable.isEmpty }
        portOpen = (cs?["charge_port_door_open"] as? Bool) ?? portOpen
        if cs != nil {
            fastCharger = (cs?["fast_charger_present"] as? Bool) ?? fastCharger
            pilotAmps = d(cs, "charger_pilot_current").flatMap { $0 > 0 ? $0 : nil } ?? (cableConnected ? pilotAmps : nil)
        }
        insideC = d(cl, "inside_temp") ?? insideC
        outsideC = d(cl, "outside_temp") ?? outsideC
        climateOn = (cl?["is_climate_on"] as? Bool) ?? climateOn
        setTempC = d(cl, "driver_temp_setting") ?? setTempC
        keeperMode = (cl?["climate_keeper_mode"] as? String) ?? keeperMode
        batteryHeater = (cl?["battery_heater"] as? Bool) ?? batteryHeater
        if let l = vs?["locked"] as? Bool { locked = l }
        sentry = (vs?["sentry_mode"] as? Bool) ?? sentry
        valet = (vs?["valet_mode"] as? Bool) ?? valet
        let w = ["fd_window", "fp_window", "rd_window", "rp_window"].map { (d(vs, $0) ?? 0) > 0 }
        if vs != nil { windowsOpen = w }
        if vs != nil {
            let dd = ["df", "pf", "dr", "pr"].map { (d(vs, $0) ?? 0) > 0 }
            doors = dd
            doorsOpen = dd.contains(true)
            trunkOpen = (d(vs, "rt") ?? 0) > 0
            frunkOpen = (d(vs, "ft") ?? 0) > 0
            let t = ["tpms_pressure_fl", "tpms_pressure_fr", "tpms_pressure_rl", "tpms_pressure_rr"].map { d(vs, $0) }
            if t.contains(where: { $0 != nil }) { tyres = t }
        }
        if let mi = d(vs, "odometer") { odometerKm = mi * 1.609344 }
        if cl != nil {
            seatCool = [Int(d(cl, "seat_fan_front_left") ?? 0), Int(d(cl, "seat_fan_front_right") ?? 0)]
            overheat = (cl?["cabin_overheat_protection"] as? String) ?? overheat
            bioweapon = (cl?["bioweapon_mode"] as? Bool) ?? bioweapon
            defrost = (cl?["is_front_defroster_on"] as? Bool) ?? defrost
        }
        if let g = vs?["guest_mode_enabled"] as? Bool { guest = g }
        for o in [vs, cs, j] {
            if let v = (o?["low_power_mode"] as? Bool) ?? (o?["low_power_mode_enabled"] as? Bool) { lowPower = v }
            if let v = (o?["keep_accessory_power_mode"] as? Bool) ?? (o?["accessory_power"] as? Bool) { accessoryPower = v }
        }
        let seen = ["tpms_last_seen_pressure_time_fl", "tpms_last_seen_pressure_time_fr",
                    "tpms_last_seen_pressure_time_rl", "tpms_last_seen_pressure_time_rr"].compactMap { d(vs, $0) }
        if let last = seen.max(), last > 0 { tyresRead = Date(timeIntervalSince1970: last) }
        let vc = j["vehicle_config"] as? [String: Any]
        if let v = j["vin"] as? String { vin = v }
        if let t = vc?["car_type"] as? String { carType = t }
        if let t = vc?["trim_badging"] as? String { trim = t }
        if let v = vs?["car_version"] as? String, let first = v.split(separator: " ").first { software = String(first) }
        gear = (ds?["shift_state"] as? String) ?? "P"
        speedKmh = d(ds, "speed").map { $0 * 1.609344 }
        lat = d(ds, "latitude") ?? lat
        lon = d(ds, "longitude") ?? lon
        heading = d(ds, "heading") ?? heading
        updated = Date()
    }

    mutating func apply(battery j: [String: Any]) {
        func d(_ k: String) -> Double? { (j[k] as? Double) ?? (j[k] as? Int).map(Double.init) }
        if let lo = d("module_temp_min"), let hi = d("module_temp_max") { packTempC = (lo + hi) / 2 }
        lifetimeKWh = d("lifetime_energy_used") ?? lifetimeKWh
        packVoltage = d("pack_voltage") ?? packVoltage
        packCurrent = d("pack_current") ?? packCurrent
        energyLeftKWh = d("energy_remaining") ?? energyLeftKWh
    }

    mutating func apply(location j: [String: Any]) {
        address = (j["address"] as? String) ?? address
        // Tessie only sends a saved place while the car is there: no name means it has left (don't keep the old "Home").
        let saved = (j["saved_location"] as? String)?.trimmingCharacters(in: .whitespaces)
        savedLocation = (saved?.isEmpty ?? true) ? nil : saved
        if let la = j["latitude"] as? Double { lat = la }
        if let lo = j["longitude"] as? Double { lon = lo }
        located = Date()
    }
}

struct BatteryHealth: Codable, Equatable {
    var healthPercent: Double?
    var degradationPercent: Double?
    var maxRangeKm: Double?
    var capacityKWh: Double?
    var originalCapacityKWh: Double?

    init() {}
    init(_ j: [String: Any]) {
        func d(_ k: String) -> Double? { (j[k] as? Double) ?? (j[k] as? Int).map(Double.init) }
        healthPercent = d("health_percent")
        degradationPercent = d("degradation_percent")
        maxRangeKm = d("max_range")
        capacityKWh = d("capacity")
        originalCapacityKWh = d("original_capacity")
    }

    /// Full-battery equivalents: lifetime energy ÷ usable capacity (Tesla doesn't report cycles).
    func cycles(lifetimeKWh: Double?) -> Double? {
        guard let e = lifetimeKWh, let c = capacityKWh ?? originalCapacityKWh, c > 0 else { return nil }
        return e / c
    }
}
