import SwiftUI
import CoreLocation

/// Everything one quick-control button can do. Pairs (lock / unlock) are one button that follows the car.
enum CarControl: String, CaseIterable, Identifiable {
    case lock, climate, charge, precondition, gate, flash, honk
    case frunk, trunk, windows, keyless, wake
    case setTemp, defrost, seatCool, seatCoolPassenger, overheat, bioweapon, dogMode, campMode, keepMode
    case chargePort, chargeLimit80, amps5, amps32
    case boombox, sentry, valet, guest, lowPower, accessoryPower

    var id: String { rawValue }

    static let defaults: [CarControl] = [.lock, .climate, .charge, .precondition, .gate, .flash]

    enum Group: String, CaseIterable { case access = "Access", climate = "Climate", charging = "Charging", alerts = "Alerts", modes = "Modes" }

    var group: Group {
        switch self {
        case .lock, .frunk, .trunk, .windows, .gate, .keyless, .wake: return .access
        case .climate, .setTemp, .defrost, .seatCool, .seatCoolPassenger, .overheat, .bioweapon, .dogMode, .campMode, .keepMode: return .climate
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
        case .precondition: return "Precondition battery"
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
        case .seatCool: return "Driver seat cooling"
        case .seatCoolPassenger: return "Passenger seat cooling"
        case .overheat: return "Cabin overheat protection"
        case .bioweapon: return "Bioweapon defence mode"
        case .dogMode: return "Pet mode"
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
        case .seatCool: return "Seat cool"
        case .seatCoolPassenger: return "Pass. cool"
        case .overheat: return "Overheat"
        case .bioweapon: return "Bioweapon"
        case .dogMode: return "Pet"
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
        case .climate: return s.climateOn ? "fanblades.fill" : "fanblades"
        case .charge: return s.charging ? "bolt.fill" : "bolt"
        case .precondition: return "heat.waves"
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
        case .seatCool: return "carseat.left.fan"
        case .seatCoolPassenger: return "carseat.right.fan"
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
        case .sentry: return s.sentry ? "record.circle.fill" : "record.circle"
        case .valet: return "person.badge.key"
        case .guest: return "person.2"
        case .lowPower: return s.lowPower == true ? "leaf.fill" : "leaf"
        case .accessoryPower: return s.accessoryPower == true ? "powerplug.fill" : "powerplug"
        }
    }

    /// Colour when the feature is on (or the car state is good).
    func tint(_ s: CarSnapshot) -> Color {
        switch self {
        case .lock: return s.locked == true ? TSurface.green : CarColors.amber
        case .climate: return s.climateOn ? CarColors.blue : .white
        case .charge: return s.charging ? TSurface.green : CarColors.red
        case .precondition: return s.preconditioning ? CarColors.red : .white
        case .sentry: return s.sentry ? CarColors.red : .white
        case .valet: return s.valet ? CarColors.amber : .white
        case .lowPower: return s.lowPower == true ? TSurface.green : .white
        case .accessoryPower: return s.accessoryPower == true ? TSurface.green : .white
        default: return .white
        }
    }

    /// Asks before doing it (on by default for these; can be changed per button in Settings).
    var riskyByDefault: Bool {
        switch self {
        case .lock, .frunk, .trunk, .windows, .keyless, .valet, .precondition: return true
        default: return false
        }
    }

    /// The centred confirmation: a plain question, one line of what happens, and the button word.
    func question(_ s: CarSnapshot) -> (title: String, message: String, action: String) {
        switch self {
        case .gate: return ("Open or close the front gate?", "", "Yes")
        case .lock: return ("Unlock \(s.name)?", "", "Yes")   // only asked when unlocking
        case .climate: return ("Turn on the A/C?", "Low Power Mode will be turned off first.", "Yes")   // only asked when turning on
        case .frunk: return s.frunkOpen ? ("Close the frunk?", "Only cars with a powered frunk can close it remotely.", "Yes")
                                        : ("Open the frunk?", "It can only be closed by hand.", "Yes")
        case .trunk: return s.trunkOpen ? ("Close the rear trunk?", "Make sure nothing is in the way.", "Close")
                                        : ("Open the rear trunk?", "It opens straight away.", "Open")
        case .windows: return s.anyWindowOpen ? ("Close the windows?", "Make sure nothing is in the way.", "Yes")
                                              : ("Vent the windows?", "All 4 windows open a little.", "Yes")
        case .keyless: return ("Start keyless driving?", "You can drive without the phone key for the next 2 minutes.", "Start")
        case .sentry: return s.sentry ? ("Turn off Sentry mode?", "", "Yes")
                                      : ("Turn on Sentry mode?", "Low Power Mode will be turned off first.", "Yes")
        case .valet: return s.valet ? ("Turn off valet mode?", "The car goes back to your normal settings.", "Turn off")
                                    : ("Turn on valet mode?", "Speed is limited and the glovebox locks.", "Turn on")
        case .precondition: return s.preconditioning ? ("Stop preconditioning?", "The A/C turns off.", "Stop")
                                                     : ("Precondition the battery?", "A/C on, cabin set to 19°C.", "Start")
        case .chargePort: return s.portOpen ? ("Close the charge port?", "Unplug the cable first.", "Close")
                                            : ("Open the charge port?", "The port door opens and unlocks the cable.", "Open")
        default: return ("\(title)?", "", short)
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
        if c == .gate { return d.object(forKey: "car.gate.ask") == nil ? true : d.bool(forKey: "car.gate.ask") }
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
    @Published var toast: Banner?
    @Published var controls = CarControl.load()
    @Published var confirming: CarControl?
    /// Low Power Mode: Tesla doesn't report it, so TesLah shows what it last set (for 3 hours), else "Unknown".
    struct LowPowerNote: Codable, Equatable { var on: Bool; var at: Date }
    @Published var lowPowerNote: LowPowerNote? = {
        guard let d = UserDefaults.standard.data(forKey: "car.lowPowerNote") else { return nil }
        return try? JSONDecoder().decode(LowPowerNote.self, from: d)
    }()
    @Published var choosingLowPower = false
    var lowPowerKnown: Bool? {
        guard let n = lowPowerNote, Date().timeIntervalSince(n.at) < 3 * 3600 else { return nil }
        return n.on
    }
    func noteLowPower(_ on: Bool) {
        let n = LowPowerNote(on: on, at: Date())
        lowPowerNote = n
        if let d = try? JSONEncoder().encode(n) { UserDefaults.standard.set(d, forKey: "car.lowPowerNote") }
        var c = car; c.lowPower = on; car = c
    }
    func setLowPower(_ on: Bool) async {
        choosingLowPower = false
        guard let t = TessieClient.configured(), let vin else { show(.failed("Set up Tessie in My Car settings first")); return }
        busy = .lowPower
        defer { busy = nil }
        show(Banner(title: on ? "Turning on Low Power Mode…" : "Turning off Low Power Mode…", icon: "leaf", tint: CarColors.muted, spinning: true))
        do {
            try await t.command(vin, on ? "enable_low_power_mode" : "disable_low_power_mode")
            noteLowPower(on)
            show(Banner(title: on ? "Low Power Mode on" : "Low Power Mode off", icon: "leaf.fill", tint: on ? TSurface.green : CarColors.muted))
        } catch {
            show(.failed(error))
        }
    }
    @Published var pendingLimit: Double?
    @Published var gateSent = false      // top-row gate icon shows radio waves for a few seconds

    private var lastHealth: Date?
    private var liveUntil: Date?          // straight after a command: read the car itself, not Tessie's cache
    private var liveTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var limitTask: Task<Void, Never>?

    static let recommendedBar = 2.9
    static let warnKey = "car.tyre.warn"
    static let unitKey = "car.tyre.unit"

    /// Tyre pressure bands (bar, read to one decimal): 2.9–3.3 normal, 2.0–2.8 low, 1.9 and below very low, 3.4 and above high.
    enum TyreLevel { case ok, low, flat, high }
    static func tyreLevel(_ bar: Double?) -> TyreLevel {
        guard let b = bar else { return .ok }
        let v = (b * 10).rounded() / 10
        if v <= 1.9 { return .flat }
        if v <= 2.8 { return .low }
        if v <= 3.3 { return .ok }
        return .high
    }
    /// Colour for a reading; `normal` is what an OK tyre uses (grey on My Car, white on the Tyres page).
    static func tyreColor(_ bar: Double?, normal: Color) -> Color {
        switch tyreLevel(bar) {
        case .ok: return normal
        case .low, .high: return CarColors.orange
        case .flat: return CarColors.red
        }
    }

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

    /// How often the page reads the car: 15 s just after a command, 20 s while charging, else 60 s.
    var pollInterval: Double {
        if let u = liveUntil, u > Date() { return 15 }
        return car.charging ? 20 : 60
    }

    func refresh(live: Bool = false) async {
        if homeZone == nil { Task { _ = await loadZone() } }   // for "at home" (Home-Outer zone)
        let useLive = live || (liveUntil.map { $0 > Date() } ?? false)
        guard let t = TessieClient.configured(), let vin else {
            error = "Add your Tessie token: ☰ → Tessie"
            return
        }
        refreshing = true
        defer { refreshing = false }
        do {
            async let s = t.state(vin, live: useLive)
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
                BatteryHistory.shared.addHealth(health)   // one point a day for the health graph
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

    func show(_ text: String) { show(.ok(text)) }

    /// Shows a banner; it slides away after 2.5 s (a "sending…" one stays until the answer replaces it).
    func show(_ b: Banner) {
        toastTask?.cancel()
        toast = b
        guard !b.spinning else { return }
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(b.tint == CarColors.red ? 3.5 : 2.5))
            guard !Task.isCancelled else { return }
            toast = nil
        }
    }

    func dismissBanner() { toastTask?.cancel(); toast = nil }

    // MARK: Buttons

    func tap(_ c: CarControl) {
        if c == .gate { Task { await tapGate() }; return }
        // Unlock and A/C on always ask; lock and A/C off go straight away.
        if c == .lock { if car.locked == false { Task { await run(c) } } else { confirming = c }; return }
        if c == .climate { if car.climateOn { Task { await run(c) } } else { confirming = c }; return }
        if c == .frunk { confirming = c; return }   // always asks
        if CarControl.asks(c) { confirming = c } else { Task { await run(c) } }
    }

    /// The confirmation for a button; the gate's changes when the car is away from home.
    func question(_ c: CarControl) -> (title: String, message: String, action: String, destructive: Bool) {
        if c == .gate, let away = gateAway {
            if let m = away.meters {
                let dist = m < 1000 ? "\(Int((m / 10).rounded() * 10)) m" : String(format: "%.1f km", m / 1000)
                return ("You're not at home", "\(car.name) is \(dist) away.\nOpen the front gate anyway?", "Open Gate", true)
            }
            return ("Open the front gate?", "Couldn't check where the car is.", "Yes", false)
        }
        let q = c.question(car)
        return (q.title, q.message, q.action, false)
    }

    // MARK: Gate: check the car is inside the home zone first

    struct GateAway: Equatable { var meters: Double? }   // nil meters = couldn't tell
    @Published var gateAway: GateAway?

    static let zoneKey = "car.gate.zone"
    static var zoneEntity: String {
        UserDefaults.standard.string(forKey: zoneKey).flatMap { $0.isEmpty ? nil : $0 } ?? "zone.home_outer"
    }

    struct HomeZone: Equatable { var name: String; var lat: Double; var lon: Double; var radius: Double }
    @Published var homeZone: HomeZone?

    func loadZone() async -> HomeZone? {
        guard let ha = HAClient.configured(), let z = try? await ha.state(Self.zoneEntity) else { return homeZone }
        func n(_ k: String) -> Double? { (z.attributes[k] as? Double) ?? (z.attributes[k] as? Int).map(Double.init) }
        guard let la = n("latitude"), let lo = n("longitude") else { return homeZone }
        let zone = HomeZone(name: (z.attributes["friendly_name"] as? String) ?? "Home", lat: la, lon: lo, radius: n("radius") ?? 100)
        homeZone = zone
        return zone
    }

    private func tapGate() async {
        busy = .gate
        // A fresh position if the last one is more than 2 minutes old.
        let fresh = car.located.map { Date().timeIntervalSince($0) < 120 } ?? false
        if !fresh, let t = TessieClient.configured(), let vin, let l = try? await t.location(vin) {
            var c = car; c.apply(location: l); car = c
        }
        let zone = await loadZone()
        busy = nil
        if let zone, let la = car.lat, let lo = car.lon {
            let m = CLLocation(latitude: la, longitude: lo).distance(from: CLLocation(latitude: zone.lat, longitude: zone.lon))
            gateAway = m > zone.radius ? GateAway(meters: m) : nil
        } else {
            gateAway = GateAway(meters: nil)
        }
        if gateAway != nil || CarControl.asks(.gate) { confirming = .gate } else { await run(.gate) }
    }

    func run(_ c: CarControl) async {
        confirming = nil
        if c == .gate { gateAway = nil; await openGate(); return }
        guard let t = TessieClient.configured(), let vin else { show(.failed("Set up Tessie in My Car settings first")); return }
        busy = c
        defer { busy = nil }
        let s = car
        show(.sending(sendingText(c, s)))
        do {
            switch c {
            case .lock: try await t.command(vin, s.locked == false ? "lock" : "unlock")
            case .climate:
                if s.climateOn {
                    try await t.command(vin, "stop_climate")
                } else {
                    // Low Power Mode off first (always: Tessie doesn't say whether it's on), then the A/C.
                    show(Banner(title: "Turning off Low Power Mode…", icon: "leaf", tint: CarColors.muted, spinning: true))
                    try await t.command(vin, "disable_low_power_mode")
                    noteLowPower(false)
                    show(Banner(title: "Turning on the A/C…", icon: "fanblades", tint: CarColors.muted, spinning: true))
                    try await t.command(vin, "start_climate")
                }
            case .charge: try await t.command(vin, s.charging ? "stop_charging" : "start_charging")
            case .precondition:
                // Preconditioning, the Sexy Commander way: A/C on, cabin at 19°C. Again turns it off.
                if s.preconditioning {
                    try await t.command(vin, "stop_climate")
                } else {
                    try await t.command(vin, "start_climate")
                    try await t.command(vin, "set_temperatures", ["temperature": "19"])
                }
            case .flash: try await t.command(vin, "flash")
            case .honk: try await t.command(vin, "honk")
            case .frunk: try await t.command(vin, "activate_front_trunk")
            case .trunk: try await t.command(vin, "activate_rear_trunk")
            case .windows: try await t.command(vin, s.anyWindowOpen ? "close_windows" : "vent_windows")
            case .keyless: try await t.command(vin, "remote_start")
            case .wake: try await t.wake(vin)
            case .setTemp: try await t.command(vin, "set_temperatures", ["temperature": "22"])
            case .defrost: try await t.command(vin, s.defrost == true ? "stop_defrost" : "start_defrost")
            case .seatCool: try await t.command(vin, "set_seat_cool", ["seat": "driver", "level": (s.seatCool?[0] ?? 0) > 0 ? "0" : "3"])
            case .seatCoolPassenger: try await t.command(vin, "set_seat_cool", ["seat": "passenger", "level": (s.seatCool?[1] ?? 0) > 0 ? "0" : "3"])
            case .overheat: try await t.command(vin, "set_cabin_overheat_protection", ["on": "true", "fan_only": "false"])
            case .bioweapon: try await t.command(vin, "set_bioweapon_mode", ["on": "true"])
            case .dogMode: try await t.command(vin, "set_climate_keeper_mode", ["mode": s.keeperMode == "dog" ? "0" : "2"])
            case .campMode: try await t.command(vin, "set_climate_keeper_mode", ["mode": s.keeperMode == "camp" ? "0" : "3"])
            case .keepMode: try await t.command(vin, "set_climate_keeper_mode", ["mode": s.keeperMode == "on" ? "0" : "1"])
            case .chargePort: try await t.command(vin, s.portOpen ? "close_charge_port" : "open_charge_port")
            case .chargeLimit80: try await t.command(vin, "set_charge_limit", ["percent": "80"])
            case .amps5: try await t.command(vin, "set_charging_amps", ["amps": "5"])
            case .amps32: try await t.command(vin, "set_charging_amps", ["amps": "32"])
            case .boombox: try await t.command(vin, "remote_boombox")
            case .sentry:
                if s.sentry {
                    try await t.command(vin, "disable_sentry")
                } else {
                    // Low Power Mode off first, then Sentry (same as the A/C).
                    show(Banner(title: "Turning off Low Power Mode…", icon: "leaf", tint: CarColors.muted, spinning: true))
                    try await t.command(vin, "disable_low_power_mode")
                    noteLowPower(false)
                    show(Banner(title: "Turning Sentry on…", icon: "record.circle", tint: CarColors.muted, spinning: true))
                    try await t.command(vin, "enable_sentry")
                }
            case .valet: try await t.command(vin, s.valet ? "disable_valet" : "enable_valet")
            case .guest: try await t.command(vin, s.guest == true ? "disable_guest" : "enable_guest")
            case .lowPower: try await t.command(vin, lowPowerKnown == true ? "disable_low_power_mode" : "enable_low_power_mode")
            case .accessoryPower: try await t.command(vin, s.accessoryPower == true ? "disable_keep_accessory_power_mode" : "enable_keep_accessory_power_mode")
            case .gate: break
            }
            show(doneBanner(c, s))
            var n = car; Self.optimistic(c, s, &n); car = n
            save()
            followUp()
        } catch {
            show(.failed(error))
        }
    }

    /// After a command: read the car itself in 2 s, and keep reading it directly for 90 s.
    private func followUp() {
        liveUntil = Date().addingTimeInterval(90)
        liveTask?.cancel()
        liveTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await refresh(live: true)
        }
    }

    /// What the car will look like once the command is done, so the icons change straight away.
    static func optimistic(_ c: CarControl, _ s: CarSnapshot, _ n: inout CarSnapshot) {
        switch c {
        case .lock: n.locked = s.locked == false
        case .climate: n.climateOn = !s.climateOn; if s.climateOn { n.batteryHeater = false }
        case .charge: n.chargingState = s.charging ? "Stopped" : "Charging"
        case .precondition:
            if s.preconditioning { n.climateOn = false; n.batteryHeater = false } else { n.climateOn = true; n.setTempC = 19 }
        case .setTemp: n.setTempC = 22
        case .defrost: n.defrost = !(s.defrost == true)
        case .seatCool: var a = s.seatCool ?? [0, 0]; a[0] = a[0] > 0 ? 0 : 3; n.seatCool = a
        case .seatCoolPassenger: var a = s.seatCool ?? [0, 0]; a[1] = a[1] > 0 ? 0 : 3; n.seatCool = a
        case .dogMode: n.keeperMode = s.keeperMode == "dog" ? "off" : "dog"
        case .campMode: n.keeperMode = s.keeperMode == "camp" ? "off" : "camp"
        case .keepMode: n.keeperMode = s.keeperMode == "on" ? "off" : "on"
        case .chargePort: n.portOpen = !s.portOpen
        case .chargeLimit80: n.limit = 80
        case .amps5: n.chargeAmps = 5
        case .amps32: n.chargeAmps = 32
        case .sentry: n.sentry = !s.sentry
        case .valet: n.valet = !s.valet
        case .guest: n.guest = !(s.guest == true)
        case .lowPower: n.lowPower = !(s.lowPower == true)
        case .accessoryPower: n.accessoryPower = !(s.accessoryPower == true)
        case .frunk: n.frunkOpen = !s.frunkOpen
        case .trunk: n.trunkOpen = !s.trunkOpen
        case .windows: n.windowsOpen = Array(repeating: !s.anyWindowOpen, count: 4)
        default: break
        }
    }

    private func sendingText(_ c: CarControl, _ s: CarSnapshot) -> String {
        switch c {
        case .lock: return s.locked == false ? "Locking…" : "Unlocking…"
        case .climate: return s.climateOn ? "Turning climate off…" : "Turning climate on…"
        case .charge: return s.charging ? "Stopping charging…" : "Starting charging…"
        case .precondition: return s.preconditioning ? "Stopping preconditioning…" : "Starting preconditioning…"
        case .sentry: return s.sentry ? "Turning Sentry off…" : "Turning Sentry on…"
        case .valet: return s.valet ? "Turning valet off…" : "Turning valet on…"
        case .wake: return "Waking the car…"
        default: return "Sending to the car…"
        }
    }

    /// What actually happened, said plainly.
    private func doneBanner(_ c: CarControl, _ s: CarSnapshot) -> Banner {
        let grey = CarColors.muted
        switch c {
        case .lock:
            return s.locked == false ? Banner(title: "Locked", icon: "lock.fill", tint: grey)
                                     : Banner(title: "Unlocked", icon: "lock.open.fill", tint: CarColors.amber)
        case .climate:
            return s.climateOn ? Banner(title: "Climate off", icon: "fanblades", tint: grey)
                               : Banner(title: "Climate on", detail: s.setTempC.map { String(format: "Cooling to %.0f°C", $0) },
                                        icon: "fanblades.fill", tint: Color(red: 10 / 255, green: 132 / 255, blue: 1))
        case .charge:
            if s.charging {
                return Banner(title: "Charging stopped", detail: s.soc.map { "Stays at \(Int($0))%" }, icon: "bolt.fill", tint: grey)
            }
            let amps = s.chargeAmps.map { "\(Int($0)) A · " } ?? ""
            return Banner(title: "Charging started", detail: amps + "charging to \(Int(s.limit ?? 80))%", icon: "bolt.fill", tint: TSurface.green)
        case .precondition:
            return s.preconditioning ? Banner(title: "Preconditioning stopped", detail: "A/C off", icon: "heat.waves", tint: grey)
                                     : Banner(title: "Preconditioning", detail: "A/C on at 19°C", icon: "heat.waves", tint: CarColors.red)
        case .sentry:
            return Banner(title: s.sentry ? "Sentry off" : "Sentry on", icon: "record.circle", tint: s.sentry ? grey : CarColors.red)
        case .valet:
            return Banner(title: s.valet ? "Valet off" : "Valet on", icon: "person.badge.key.fill", tint: s.valet ? grey : CarColors.amber)
        case .flash: return Banner(title: "Lights flashed", icon: "lightbulb.fill", tint: CarColors.amber)
        case .honk: return Banner(title: "Horn sounded", icon: "speaker.wave.2.fill", tint: grey)
        case .frunk: return .ok(s.frunkOpen ? "Front trunk closing" : "Front trunk open")
        case .trunk: return .ok(s.trunkOpen ? "Rear trunk closing" : "Rear trunk open")
        case .windows: return .ok(s.anyWindowOpen ? "Windows closing" : "Windows vented")
        case .wake: return .ok("Car is awake")
        case .lowPower:
            return Banner(title: s.lowPower == true ? "Low Power Mode off" : "Low Power Mode on", icon: "leaf.fill",
                          tint: s.lowPower == true ? grey : TSurface.green)
        case .accessoryPower:
            return Banner(title: s.accessoryPower == true ? "Accessory Power off" : "Accessory Power on",
                          detail: s.accessoryPower == true ? nil : "USB and 12 V stay on after you leave",
                          icon: "powerplug.fill", tint: s.accessoryPower == true ? grey : TSurface.green)
        default: return .ok(c.title, "Done")
        }
    }

    private func openGate() async {
        guard let ha = HAClient.configured() else { show(.failed("Set up Home Assistant in My Home settings first")); return }
        let entity = UserDefaults.standard.string(forKey: "car.gate.entity").flatMap { $0.isEmpty ? nil : $0 }
            ?? "switch.porch_rf_controller_switch_1"
        busy = .gate
        defer { busy = nil }
        do {
            // Same pulse as the autogate script: on, 1 s, off.
            try await ha.call("switch", "turn_on", ["entity_id": entity])
            try? await Task.sleep(for: .seconds(1))
            try await ha.call("switch", "turn_off", ["entity_id": entity])
            show(Banner(title: "Gate signal sent", detail: "Opening or closing", icon: "checkmark", tint: TSurface.green))
            gateSent = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                gateSent = false
            }
        } catch {
            show(Banner(title: "Gate signal not sent", detail: error.localizedDescription, icon: "exclamationmark", tint: CarColors.red))
        }
    }

    /// One Tessie command from the Controls pages. `update` adjusts what the page shows once the car has done it.
    func send(_ name: String, _ params: [String: String] = [:], done: String, update: ((inout CarSnapshot) -> Void)? = nil) async {
        guard let t = TessieClient.configured(), let vin else { show(.failed("Set up Tessie in My Car settings first")); return }
        do {
            show(.sending("Sending to the car…"))
            try await t.command(vin, name, params)
            if let update { var c = car; update(&c); car = c; save() }
            show(.ok(done))
            followUp()
        } catch {
            show(.failed(error))
        }
    }

    // MARK: Charging

    /// Drag on the ring or slider: shows straight away, sends once you let go.
    func setLimit(_ pct: Double) {
        let p = min(max(pct.rounded(), 50), 100)
        limitTask?.cancel()
        if let now = car.limit, abs(p - now) < 0.5 {
            // Same as the car already has: nothing to send.
            pendingLimit = nil
            show(Banner(title: "Already at \(Int(p))%", detail: "Same as the car · nothing sent", icon: "equal", tint: CarColors.muted))
            return
        }
        pendingLimit = p
        limitTask = Task { @MainActor in
            guard let t = TessieClient.configured(), let vin else { return }
            do {
                try await t.command(vin, "set_charge_limit", ["percent": String(Int(p))])
                car.limit = p
                show("Charge limit set to \(Int(p))%")
            } catch {
                show(.failed(error))
            }
            pendingLimit = nil
        }
    }

    func setAmps(_ a: Int) async {
        guard let t = TessieClient.configured(), let vin else { return }
        let v = min(max(a, 5), max(car.ampsCap, Int(car.chargeAmps ?? 5)))
        car.chargeAmps = Double(v)
        do { try await t.command(vin, "set_charging_amps", ["amps": String(v)]) } catch { show(.failed(error)) }
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

    var driving: Bool { ["D", "R", "N"].contains(car.gear) }

    /// At home: inside the Home-Outer zone from Home Assistant when known, otherwise Tessie's saved place.
    var isHome: Bool {
        if let z = homeZone, let la = car.lat, let lo = car.lon {
            return CLLocation(latitude: la, longitude: lo).distance(from: CLLocation(latitude: z.lat, longitude: z.lon)) <= z.radius
        }
        return car.atHome
    }

    /// Town the car is in, from Tessie's address ("Kemaman, Terengganu, Malaysia" → "Kemaman").
    var townWord: String? {
        guard let a = car.address, let first = a.split(separator: ",").first else { return nil }
        let t = first.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }

    /// Home · Tessie's saved place while parked there · the town while driving (or when Tessie has no name).
    var placeWord: String {
        if isHome && !driving { return "Home" }
        if !driving, let s = car.savedLocation, !s.isEmpty, !s.localizedCaseInsensitiveContains("home") { return s }
        return townWord ?? "Away"
    }

    /// Line under the car name: "Parked at home", "Parked · PGB TSET", "Driving · Kemaman".
    var whereLine: String {
        if driving { return townWord.map { "Driving · " + $0 } ?? "Driving" }
        if isHome { return "Parked at home" }
        return "Parked · " + placeWord
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

    func tyreLow(_ i: Int) -> Bool { Self.tyreLevel(car.tyres[i]) != .ok }

    var tyreNote: String {
        let names = ["FL", "FR", "RL", "RR"]
        if car.tyres.allSatisfy({ $0 == nil }) { return "No reading yet" }
        let notes = (0..<4).compactMap { i -> String? in
            switch Self.tyreLevel(car.tyres[i]) {
            case .ok: return nil
            case .low: return names[i] + " low"
            case .flat: return names[i] + " very low"
            case .high: return names[i] + " high"
            }
        }
        return notes.isEmpty ? "All OK" : notes.joined(separator: " · ")
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
