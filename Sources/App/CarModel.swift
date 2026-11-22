import SwiftUI

/// Everything one quick-control button can do. Pairs (lock / unlock) are one button that follows the car.
enum CarControl: String, CaseIterable, Identifiable {
    case lock, climate, charge, precondition, gate, flash, honk
    case frunk, trunk, windows, keyless, wake
    case setTemp, defrost, seatHeat, seatCool, wheelHeat, overheat, bioweapon, dogMode, campMode, keepMode
    case chargePort, chargeLimit80, amps5, amps32
    case boombox, sentry, valet, guest, lowPower, accessoryPower

    var id: String { rawValue }

    static let defaults: [CarControl] = [.lock, .climate, .charge, .precondition, .gate, .flash]

    enum Group: String, CaseIterable { case access = "Access", climate = "Climate", charging = "Charging", alerts = "Alerts", modes = "Modes" }

    var group: Group {
        switch self {
        case .lock, .frunk, .trunk, .windows, .gate, .keyless, .wake: return .access
        case .climate, .setTemp, .defrost, .seatHeat, .seatCool, .wheelHeat, .overheat, .bioweapon, .dogMode, .campMode, .keepMode: return .climate
        case .charge, .chargePort, .chargeLimit80, .amps5, .amps32, .precondition: return .charging
        case .flash, .honk, .boombox: return .alerts
        case .sentry, .valet, .guest, .lowPower, .accessoryPower: return .modes
        }
    }

    var title: String {
        switch self {
        case .lock: return "Lock / unlock"
        case .climate: return "Climate on / off"
        case .charge: return "Start / stop charging"
        case .precondition: return "Precondition (Supercharger)"
        case .gate: return "Autogate (Home Assistant)"
        case .flash: return "Flash lights"
        case .honk: return "Honk"
        case .frunk: return "Front trunk"
        case .trunk: return "Rear trunk"
        case .windows: return "Vent / close windows"
        case .keyless: return "Keyless driving"
        case .wake: return "Wake car"
        case .setTemp: return "Set cabin to 22°C"
        case .defrost: return "Defrost on / off"
        case .seatHeat: return "Driver seat heat"
        case .seatCool: return "Driver seat cooling"
        case .wheelHeat: return "Steering wheel heater"
        case .overheat: return "Cabin overheat protection"
        case .bioweapon: return "Bioweapon defence mode"
        case .dogMode: return "Dog mode"
        case .campMode: return "Camp mode"
        case .keepMode: return "Keep climate on"
        case .chargePort: return "Open / close charge port"
        case .chargeLimit80: return "Charge limit 80%"
        case .amps5: return "Charge at 5 A"
        case .amps32: return "Charge at 32 A"
        case .boombox: return "Boombox"
        case .sentry: return "Sentry on / off"
        case .valet: return "Valet on / off"
        case .guest: return "Guest mode on / off"
        case .lowPower: return "Low power mode"
        case .accessoryPower: return "Keep accessory power"
        }
    }

    var short: String {
        switch self {
        case .lock: return "Lock"
        case .climate: return "Climate"
        case .charge: return "Charge"
        case .precondition: return "Precondition"
        case .gate: return "Gate"
        case .flash: return "Flash"
        case .honk: return "Honk"
        case .frunk: return "Frunk"
        case .trunk: return "Trunk"
        case .windows: return "Windows"
        case .keyless: return "Keyless"
        case .wake: return "Wake"
        case .setTemp: return "22°C"
        case .defrost: return "Defrost"
        case .seatHeat: return "Seat heat"
        case .seatCool: return "Seat cool"
        case .wheelHeat: return "Wheel heat"
        case .overheat: return "Overheat"
        case .bioweapon: return "Bioweapon"
        case .dogMode: return "Dog"
        case .campMode: return "Camp"
        case .keepMode: return "Keep"
        case .chargePort: return "Port"
        case .chargeLimit80: return "80%"
        case .amps5: return "5 A"
        case .amps32: return "32 A"
        case .boombox: return "Boombox"
        case .sentry: return "Sentry"
        case .valet: return "Valet"
        case .guest: return "Guest"
        case .lowPower: return "Low power"
        case .accessoryPower: return "Accessory"
        }
    }

    func icon(_ s: CarSnapshot) -> String {
        switch self {
        case .lock: return s.locked == false ? "lock.open" : "lock"
        case .climate: return "fanblades"
        case .charge: return "bolt"
        case .precondition: return "flame"
        case .gate: return "door.garage.open"
        case .flash: return "lightbulb"
        case .honk: return "speaker.wave.2"
        case .frunk: return "car.side.front.open"
        case .trunk: return "car.side.rear.open"
        case .windows: return "window.vertical.open"
        case .keyless: return "key"
        case .wake: return "sun.max"
        case .setTemp: return "thermometer.medium"
        case .defrost: return "windshield.front.and.heat.waves"
        case .seatHeat: return "carseat.left.and.heat.waves"
        case .seatCool: return "carseat.left.fan"
        case .wheelHeat: return "steeringwheel.and.heat.waves"
        case .overheat: return "sun.max.trianglebadge.exclamationmark"
        case .bioweapon: return "aqi.medium"
        case .dogMode: return "pawprint"
        case .campMode: return "tent"
        case .keepMode: return "snowflake"
        case .chargePort: return "ev.plug.dc.ccs2"
        case .chargeLimit80: return "battery.75percent"
        case .amps5: return "gauge.with.dots.needle.0percent"
        case .amps32: return "gauge.with.dots.needle.100percent"
        case .boombox: return "music.note"
        case .sentry: return "eye"
        case .valet: return "person.badge.key"
        case .guest: return "person.2"
        case .lowPower: return "leaf"
        case .accessoryPower: return "powerplug"
        }
    }

    /// Colour when the feature is on (or the car state is good).
    func tint(_ s: CarSnapshot) -> Color {
        switch self {
        case .lock: return s.locked == true ? TSurface.green : CarColors.amber
        case .climate: return s.climateOn ? CarColors.blue : .white
        case .charge: return s.charging ? TSurface.green : CarColors.red
        case .precondition: return s.batteryHeater ? CarColors.orange : CarColors.orange.opacity(0.9)
        case .sentry: return s.sentry ? CarColors.red : .white
        case .valet: return s.valet ? CarColors.amber : .white
        default: return .white
        }
    }

    /// Asks before doing it (on by default for these; can be changed per button in Settings).
    var riskyByDefault: Bool {
        switch self {
        case .lock, .frunk, .trunk, .windows, .keyless, .valet: return true
        default: return false
        }
    }

    static func load() -> [CarControl] {
        let s = UserDefaults.standard.string(forKey: "car.controls") ?? ""
        let list = s.split(separator: ",").compactMap { CarControl(rawValue: String($0)) }
        return list.count == 6 ? list : defaults
    }

    static func save(_ list: [CarControl]) {
        UserDefaults.standard.set(list.map(\.rawValue).joined(separator: ","), forKey: "car.controls")
    }

    static func asks(_ c: CarControl) -> Bool {
        let d = UserDefaults.standard
        let key = "car.confirm." + c.rawValue
        if c == .gate { return d.bool(forKey: "car.gate.ask") }
        return d.object(forKey: key) == nil ? c.riskyByDefault : d.bool(forKey: key)
    }
}

enum CarColors {
    static let amber = Color(red: 1, green: 179 / 255, blue: 64 / 255)       // #FFB340
    static let red = Color(red: 1, green: 69 / 255, blue: 58 / 255)          // #FF453A
    static let orange = Color(red: 1, green: 159 / 255, blue: 10 / 255)      // #FF9F0A
    static let blue = Color(red: 127 / 255, green: 184 / 255, blue: 1)       // #7FB8FF
    static let line = Color(red: 42 / 255, green: 42 / 255, blue: 46 / 255)  // #2A2A2E
    static let ink = Color(red: 0.95, green: 0.95, blue: 0.96)
    static let muted = Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)
    static let faint = Color(red: 99 / 255, green: 99 / 255, blue: 102 / 255)
    static let healthLost = Color(red: 90 / 255, green: 26 / 255, blue: 29 / 255)
}

@MainActor
final class CarModel: ObservableObject {
    @Published var car = CarSnapshot()
    @Published var health = BatteryHealth()
    @Published var loaded = false
    @Published var refreshing = false
    @Published var error: String?
    @Published var busy: CarControl?
    @Published var toast: String?
    @Published var controls = CarControl.load()
    @Published var confirming: CarControl?
    @Published var pendingLimit: Double?

    private var lastHealth: Date?
    private var toastTask: Task<Void, Never>?
    private var limitTask: Task<Void, Never>?

    static let recommendedBar = 2.9
    static let lowBar = 2.7

    private static var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("car-state.json")
    }

    init() {
        if let d = try? Data(contentsOf: Self.cacheURL),
           let c = try? JSONDecoder().decode(Cached.self, from: d) {
            car = c.car
            health = c.health
            loaded = true
        }
    }

    private struct Cached: Codable { var car: CarSnapshot; var health: BatteryHealth }

    var configured: Bool { TessieClient.configured() != nil && vin != nil }
    var vin: String? { UserDefaults.standard.string(forKey: TessieClient.vinKey).flatMap { $0.isEmpty ? nil : $0 } }

    func reloadControls() { controls = CarControl.load() }

    func refresh() async {
        guard let t = TessieClient.configured(), let vin else {
            error = "Add your Tessie token in Settings → Car → Tessie"
            return
        }
        refreshing = true
        defer { refreshing = false }
        do {
            async let s = t.state(vin)
            async let b = try? t.battery(vin)
            async let l = try? t.location(vin)
            var c = car
            c.apply(state: try await s)
            if let b = await b { c.apply(battery: b) }
            if let l = await l { c.apply(location: l) }
            car = c
            error = nil
            loaded = true
            if lastHealth == nil || Date().timeIntervalSince(lastHealth!) > 3600, let h = try? await t.batteryHealth(vin) {
                health = BatteryHealth(h)
                lastHealth = Date()
            }
            save()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(Cached(car: car, health: health)) {
            try? d.write(to: Self.cacheURL, options: .atomic)
        }
    }

    func show(_ text: String) {
        toastTask?.cancel()
        withAnimation { toast = text }
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            withAnimation { toast = nil }
        }
    }

    // MARK: Buttons

    func tap(_ c: CarControl) {
        if CarControl.asks(c) { confirming = c } else { Task { await run(c) } }
    }

    func run(_ c: CarControl) async {
        confirming = nil
        if c == .gate { await openGate(); return }
        guard let t = TessieClient.configured(), let vin else { show("Set up Tessie in Settings first"); return }
        busy = c
        defer { busy = nil }
        let s = car
        do {
            switch c {
            case .lock: try await t.command(vin, s.locked == false ? "lock" : "unlock")
            case .climate: try await t.command(vin, s.climateOn ? "stop_climate" : "start_climate")
            case .charge: try await t.command(vin, s.charging ? "stop_charging" : "start_charging")
            case .precondition:
                let sc = try await t.nearestSupercharger(vin)
                try await t.navigate(vin, lat: sc.lat, lon: sc.lon)
                show("Navigating to \(sc.name) · battery warms on the way")
                await refresh(); return
            case .flash: try await t.command(vin, "flash")
            case .honk: try await t.command(vin, "honk")
            case .frunk: try await t.command(vin, "activate_front_trunk")
            case .trunk: try await t.command(vin, "activate_rear_trunk")
            case .windows: try await t.command(vin, s.anyWindowOpen ? "close_windows" : "vent_windows")
            case .keyless: try await t.command(vin, "remote_start")
            case .wake: try await t.wake(vin)
            case .setTemp: try await t.command(vin, "set_temperatures", ["temperature": "22"])
            case .defrost: try await t.command(vin, "start_defrost")
            case .seatHeat: try await t.command(vin, "set_seat_heat", ["seat": "driver", "level": "3"])
            case .seatCool: try await t.command(vin, "set_seat_cool", ["seat": "driver", "level": "3"])
            case .wheelHeat: try await t.command(vin, "start_steering_wheel_heater")
            case .overheat: try await t.command(vin, "set_cabin_overheat_protection", ["on": "true", "fan_only": "false"])
            case .bioweapon: try await t.command(vin, "set_bioweapon_mode", ["on": "true"])
            case .dogMode: try await t.command(vin, "set_climate_keeper_mode", ["mode": s.keeperMode == "dog" ? "off" : "dog"])
            case .campMode: try await t.command(vin, "set_climate_keeper_mode", ["mode": s.keeperMode == "camp" ? "off" : "camp"])
            case .keepMode: try await t.command(vin, "set_climate_keeper_mode", ["mode": s.keeperMode == "on" ? "off" : "on"])
            case .chargePort: try await t.command(vin, s.portOpen ? "close_charge_port" : "open_charge_port")
            case .chargeLimit80: try await t.command(vin, "set_charge_limit", ["percent": "80"])
            case .amps5: try await t.command(vin, "set_charging_amps", ["amps": "5"])
            case .amps32: try await t.command(vin, "set_charging_amps", ["amps": "32"])
            case .boombox: try await t.command(vin, "remote_boombox")
            case .sentry: try await t.command(vin, s.sentry ? "disable_sentry" : "enable_sentry")
            case .valet: try await t.command(vin, s.valet ? "disable_valet" : "enable_valet")
            case .guest: try await t.command(vin, "enable_guest")
            case .lowPower: try await t.command(vin, "enable_low_power_mode")
            case .accessoryPower: try await t.command(vin, "enable_keep_accessory_power_mode")
            case .gate: break
            }
            show(c.short + " · done")
            await refresh()
        } catch {
            show(error.localizedDescription)
        }
    }

    private func openGate() async {
        guard let ha = HAClient.configured() else { show("Set up Home Assistant in Settings first"); return }
        let entity = UserDefaults.standard.string(forKey: "car.gate.entity").flatMap { $0.isEmpty ? nil : $0 }
            ?? "switch.porch_rf_controller_switch_1"
        busy = .gate
        defer { busy = nil }
        do {
            // Same pulse as the autogate script: on, 1 s, off.
            try await ha.call("switch", "turn_on", ["entity_id": entity])
            try? await Task.sleep(for: .seconds(1))
            try await ha.call("switch", "turn_off", ["entity_id": entity])
            show("Gate signal sent")
        } catch {
            show(error.localizedDescription)
        }
    }

    // MARK: Charging

    /// Drag on the ring or slider: shows straight away, sends once you let go.
    func setLimit(_ pct: Double) {
        let p = min(max(pct.rounded(), 50), 100)
        pendingLimit = p
        limitTask?.cancel()
        limitTask = Task { @MainActor in
            guard let t = TessieClient.configured(), let vin else { return }
            do {
                try await t.command(vin, "set_charge_limit", ["percent": String(Int(p))])
                car.limit = p
                show("Charge limit set to \(Int(p))%")
            } catch {
                show(error.localizedDescription)
            }
            pendingLimit = nil
        }
    }

    func setAmps(_ a: Int) async {
        guard let t = TessieClient.configured(), let vin else { return }
        let v = min(max(a, 5), 32)
        car.chargeAmps = Double(v)
        do { try await t.command(vin, "set_charging_amps", ["amps": String(v)]) } catch { show(error.localizedDescription) }
    }

    // MARK: Text

    var statusWord: String {
        if car.speedKmh ?? 0 > 0 || ["D", "R", "N"].contains(car.gear) { return "Driving" }
        switch car.state {
        case "online": return "Awake"
        case "asleep": return "Asleep"
        case "offline": return "Offline"
        default: return "—"
        }
    }

    var statusColor: Color {
        switch statusWord {
        case "Awake", "Driving": return TSurface.green
        case "Asleep": return CarColors.blue
        default: return CarColors.muted
        }
    }

    var placeWord: String {
        if let s = car.savedLocation, !s.isEmpty { return s }
        if let a = car.address, let first = a.split(separator: ",").first { return String(first) }
        return "Away"
    }

    var chargeWord: String {
        switch car.chargingState {
        case "Charging":
            var t = "Charging · \(Int(car.chargeAmps ?? 0)) A"
            if let m = car.minutesToLimit, m > 0 { t += " · " + Self.duration(m) + " left" }
            return t
        case "Complete": return "Complete"
        case "Stopped": return car.cableConnected ? "Plugged in" : "Not charging"
        case "Disconnected": return "Not charging"
        case "NoPower": return "No power"
        default: return car.cableConnected ? "Plugged in" : "Not charging"
        }
    }

    static func duration(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min"
    }

    func tyreLow(_ i: Int) -> Bool {
        guard let v = car.tyres[i] else { return false }
        return v < Self.lowBar
    }

    var tyreNote: String {
        let names = ["FL", "FR", "RL", "RR"]
        let low = (0..<4).filter { tyreLow($0) }.map { names[$0] }
        if car.tyres.allSatisfy({ $0 == nil }) { return "No reading yet" }
        return low.isEmpty ? "All OK" : low.joined(separator: ", ") + " low"
    }

    var updatedText: String {
        guard let u = car.updated else { return "Not updated yet" }
        return "Updated \(u.formatted(date: .omitted, time: .shortened)) via Tessie"
    }

    static var versionLine: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return "Version \(v) (\(b))"
    }

    static var releaseLine: String {
        let s = Bundle.main.object(forInfoDictionaryKey: "VTReleaseDate") as? String ?? ""
        return s.isEmpty ? "" : "Released \(s)"
    }
}
