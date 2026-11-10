import SwiftUI

/// State of the Home tab. Planner values are kept on the phone and, when Home Assistant is set up,
/// mirrored to the VoltTime helpers there (HA is what actually schedules the car).
@MainActor
final class HomeModel: ObservableObject {
    // Planner inputs (saved on the phone)
    @Published var readyMinutes: Int { didSet { save(); userEdited() } }
    @Published var bufferMinutes: Int { didSet { save(); userEdited() } }
    @Published var startSoc: Double { didSet { save() } }
    @Published var limit: Double { didSet { save() } }
    @Published var amps: Double { didSet { save(); userEdited() } }
    @Published var volts: Double { didSet { save(); userEdited() } }
    @Published var efficiency: Double { didSet { save(); userEdited() } }
    @Published var capacity: Double { didSet { save(); userEdited() } }
    @Published var tariff: Double { didSet { save() } }

    // Live from Home Assistant
    @Published var liveSoc: Double?
    @Published var liveLimit: Double?
    @Published var scheduledStart: Date?
    @Published var destination = ""
    @Published var active = false
    @Published var answered = false
    @Published var plugged: Bool?
    @Published var charging: Bool?
    @Published var lastSync: Date?
    @Published var message: String?
    @Published var busy = false
    @Published var settingLimit = false
    @Published var showLimitSheet = false

    var haConfigured: Bool { HAClient.configured() != nil }

    static let gpsLimit = 73.0
    static let tsetLimit = 63.0

    private var applying = false
    private var pushTask: Task<Void, Never>?
    private let d = UserDefaults.standard

    init() {
        let d = UserDefaults.standard
        func num(_ k: String, _ def: Double) -> Double { d.object(forKey: k) == nil ? def : d.double(forKey: k) }
        readyMinutes = d.object(forKey: "home.ready") == nil ? 5 * 60 + 45 : d.integer(forKey: "home.ready")
        bufferMinutes = d.object(forKey: "home.buffer") == nil ? 15 : d.integer(forKey: "home.buffer")
        startSoc = num("home.startSoc", 20)
        limit = num("home.limit", 73)
        amps = num("home.amps", 32)
        volts = num("home.volts", 240)
        efficiency = num("home.eff", 93)
        capacity = num("home.cap", 79)
        tariff = num("home.tariff", 0.4981)
    }

    private func save() {
        d.set(readyMinutes, forKey: "home.ready")
        d.set(bufferMinutes, forKey: "home.buffer")
        d.set(startSoc, forKey: "home.startSoc")
        d.set(limit, forKey: "home.limit")
        d.set(amps, forKey: "home.amps")
        d.set(volts, forKey: "home.volts")
        d.set(efficiency, forKey: "home.eff")
        d.set(capacity, forKey: "home.cap")
        d.set(tariff, forKey: "home.tariff")
    }

    func resetDefaults() {
        readyMinutes = 5 * 60 + 45
        bufferMinutes = 15
        amps = 32
        volts = 240
        efficiency = 93
        capacity = 79
        tariff = 0.4981
        if let liveSoc { startSoc = liveSoc }
    }

    // MARK: Calculation

    var inputs: HomeInputs {
        HomeInputs(startSoc: startSoc, endSoc: limit, amps: amps, volts: volts, efficiencyPct: efficiency, capacityKWh: capacity, tariff: tariff)
    }

    var result: HomeResult { HomeMath.calculate(inputs) }

    func plannedStart(now: Date = Date()) -> Date {
        HomeMath.start(now: now, readyMinutes: readyMinutes, chargeMinutes: result.minutes, bufferMinutes: bufferMinutes,
                       clamp: true, calendar: Calendar.current)
    }

    var socIsLive: Bool {
        guard let liveSoc else { return false }
        return abs(liveSoc - startSoc) < 0.5
    }

    // MARK: Home Assistant

    func refresh() async {
        guard let ha = HAClient.configured() else { return }
        busy = true
        defer { busy = false }
        let s = await ha.states([Entity.battery, Entity.limit, Entity.plugged, Entity.charging, Entity.readyTime, Entity.start,
                                 Entity.buffer, Entity.amps, Entity.voltage, Entity.efficiency, Entity.capacity,
                                 Entity.destination, Entity.active, Entity.answered])
        if s.isEmpty {
            message = "Can't reach Home Assistant. Check the URL and token in Settings (and Tailscale)."
            return
        }
        message = s[Entity.readyTime] == nil ? "VoltTime helpers not found in Home Assistant – install homeassistant/volttime.yaml." : nil

        applying = true
        if let v = s[Entity.battery]?.number { liveSoc = v; startSoc = v.rounded() }
        if let v = s[Entity.limit]?.number { liveLimit = v; if !settingLimit { limit = v } }
        if let v = s[Entity.readyTime].flatMap({ HAClient.parseTimeOfDay($0.state) }) { readyMinutes = v }
        if let v = s[Entity.buffer]?.number { bufferMinutes = Int(v) }
        if let v = s[Entity.amps]?.number { amps = v }
        if let v = s[Entity.voltage]?.number { volts = v }
        if let v = s[Entity.efficiency]?.number { efficiency = v }
        if let v = s[Entity.capacity]?.number { capacity = v }
        applying = false

        scheduledStart = s[Entity.start].flatMap { HAClient.parseLocal($0.state) }
        destination = s[Entity.destination]?.state ?? ""
        active = s[Entity.active]?.isOn ?? false
        answered = s[Entity.answered]?.isOn ?? false
        plugged = s[Entity.plugged].flatMap { $0.isAvailable ? $0.isOn : nil }
        charging = s[Entity.charging].flatMap { $0.isAvailable ? $0.isOn : nil }
        lastSync = Date()
    }

    /// GPS / TSET / Others: set the charge limit now and (at night) re-plan the start time.
    func chooseTrip(_ name: String, limit newLimit: Double) async {
        limit = newLimit
        guard let ha = HAClient.configured() else { return }
        settingLimit = true
        defer { settingLimit = false }
        do {
            try await ha.setNumber(Entity.limit, newLimit)
            try? await ha.setText(Entity.destination, name)
            try? await ha.turnOn(Entity.answered)
            await ha.clearAskNotification()
            destination = name
            answered = true
            if active {
                try await ha.plan(limit: newLimit)
            }
            message = nil
        } catch {
            message = "Couldn't set the limit: \(error.localizedDescription)"
        }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await refresh()
    }

    /// Push planner settings to HA a moment after the last edit, then re-plan tonight if active.
    private func userEdited() {
        guard !applying, HAClient.configured() != nil else { return }
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.pushSettings()
        }
    }

    private func pushSettings() async {
        guard let ha = HAClient.configured() else { return }
        do {
            try await ha.setTime(Entity.readyTime, minutes: readyMinutes)
            try await ha.setNumber(Entity.buffer, Double(bufferMinutes))
            try await ha.setNumber(Entity.amps, amps)
            try await ha.setNumber(Entity.voltage, volts)
            try await ha.setNumber(Entity.efficiency, efficiency)
            try await ha.setNumber(Entity.capacity, capacity)
            if active {
                try await ha.plan(limit: nil)
                if let st = try? await ha.state(Entity.start) { scheduledStart = HAClient.parseLocal(st.state) }
            }
        } catch {
            message = "Couldn't save to Home Assistant: \(error.localizedDescription)"
        }
    }
}
