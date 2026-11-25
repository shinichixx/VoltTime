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
    @Published var chargingMode: String?
    /// Reminder times (minutes after midnight), sent by Home Assistant only when the car is plugged in at home.
    @Published var reminderTimes: [Int] = [19 * 60]
    @Published var remindersOn = true
    @Published var remindersAvailable = false
    /// Short confirmation shown after answering in the app ("GPS · 73% · starts 1:23 AM").
    @Published var toast: Banner?
    @Published var lastSync: Date?
    @Published var message: String?
    @Published var busy = false
    @Published var settingLimit = false
    @Published var showLimitSheet = false
    /// Start time shown vs the one in the car: Ready by / buffer edits wait until a trip is tapped.
    enum StartSync { case live, pending, checking }
    @Published var startSync: StartSync = .live

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

    /// Picks up planner values put back by a restore.
    func reloadSettings() {
        let fresh = HomeModel.Saved()
        if readyMinutes != fresh.ready { readyMinutes = fresh.ready }
        if bufferMinutes != fresh.buffer { bufferMinutes = fresh.buffer }
        if startSoc != fresh.startSoc { startSoc = fresh.startSoc }
        if limit != fresh.limit { limit = fresh.limit }
        if amps != fresh.amps { amps = fresh.amps }
        if volts != fresh.volts { volts = fresh.volts }
        if efficiency != fresh.eff { efficiency = fresh.eff }
        if capacity != fresh.cap { capacity = fresh.cap }
        if tariff != fresh.tariff { tariff = fresh.tariff }
    }

    private struct Saved {
        let ready: Int, buffer: Int
        let startSoc: Double, limit: Double, amps: Double, volts: Double, eff: Double, cap: Double, tariff: Double
        init() {
            let d = UserDefaults.standard
            func num(_ k: String, _ def: Double) -> Double { d.object(forKey: k) == nil ? def : d.double(forKey: k) }
            ready = d.object(forKey: "home.ready") == nil ? 5 * 60 + 45 : d.integer(forKey: "home.ready")
            buffer = d.object(forKey: "home.buffer") == nil ? 15 : d.integer(forKey: "home.buffer")
            startSoc = num("home.startSoc", 20)
            limit = num("home.limit", 73)
            amps = num("home.amps", 32)
            volts = num("home.volts", 240)
            eff = num("home.eff", 93)
            cap = num("home.cap", 79)
            tariff = num("home.tariff", 0.4981)
        }
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
                                 Entity.destination, Entity.active, Entity.answered, Entity.chargingMode,
                                 Entity.reminders, Entity.remindersOff])
        if s.isEmpty {
            message = "Can't reach Home Assistant. Check the address and token in Menu › Connection (and Tailscale)."
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
        chargingMode = s[Entity.chargingMode].flatMap { $0.isAvailable ? $0.state : nil }
        remindersAvailable = s[Entity.reminders] != nil
        if !savingReminders {
            if let r = s[Entity.reminders] { reminderTimes = Self.parseReminders(r.state) }
            if let off = s[Entity.remindersOff] { remindersOn = !off.isOn }
        }
        lastSync = Date()
    }

    /// GPS / TSET / Others: set the charge limit now and (at night) re-plan the start time.
    func chooseTrip(_ name: String, limit newLimit: Double) async {
        limit = newLimit
        guard let ha = HAClient.configured() else { return }
        settingLimit = true
        defer { settingLimit = false }
        let sends = active && result.minutes > 0
        if sends {
            startSync = .checking
            toast = Banner(title: "Setting the charge start…",
                           detail: "\(name) \(Int(newLimit))% · starts \(Fmt.clock(plannedStart(), calendar: .current))",
                           icon: "", tint: CarColors.muted, spinning: true)
        }
        do {
            pushTask?.cancel()
            try await ha.setTime(Entity.readyTime, minutes: readyMinutes)
            try await ha.setNumber(Entity.buffer, Double(bufferMinutes))
            try await ha.setNumber(Entity.limit, newLimit)
            try? await ha.setText(Entity.destination, name)
            try? await ha.turnOn(Entity.answered)
            await ha.clearAskNotification()
            destination = name
            answered = true
            if active {
                try await ha.plan(limit: newLimit)
                if let st = try? await ha.state(Entity.start) { scheduledStart = HAClient.parseLocal(st.state) }
            }
            message = nil
        } catch {
            message = "Couldn't set the limit: \(error.localizedDescription)"
            if sends { startSync = .pending; toast = .failed(error) }
        }
        if sends && startSync == .checking { await verifyStart() }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await refresh()
    }

    /// Reads the car (through Tessie) until its scheduled start matches what was planned.
    private func verifyStart() async {
        guard let expected = scheduledStart else { startSync = .pending; return }
        let cal = Calendar.current
        let want = cal.component(.hour, from: expected) * 60 + cal.component(.minute, from: expected)
        let clock = Fmt.clock(expected, calendar: .current)
        guard let t = TessieClient.configured(),
              let vin = UserDefaults.standard.string(forKey: TessieClient.vinKey), !vin.isEmpty else {
            startSync = .live          // no Tessie: Home Assistant's own value is all there is to check
            toast = Banner(title: "Charge start set · \(clock)")
            await clearToastLater(); return
        }
        for attempt in 0..<5 {
            if attempt > 0 { try? await Task.sleep(nanoseconds: 6_000_000_000) }
            guard let j = try? await t.state(vin, live: true), let cs = j["charge_state"] as? [String: Any] else { continue }
            var got: Int?
            if let m = cs["scheduled_charging_start_time_app"] as? Int { got = m }
            else if let e = (cs["scheduled_charging_start_time"] as? Double) ?? (cs["scheduled_charging_start_time"] as? Int).map(Double.init) {
                let d = Date(timeIntervalSince1970: e)
                got = cal.component(.hour, from: d) * 60 + cal.component(.minute, from: d)
            }
            if let got, abs(got - want) <= 1 || abs(got - want) >= 1439 {
                startSync = .live
                toast = Banner(title: "Charge start set · \(clock)", detail: "Checked in the car")
                await clearToastLater(); return
            }
        }
        startSync = .pending
        toast = Banner(title: "The car shows a different start", detail: "Tap the trip again to resend", icon: "exclamationmark", tint: CarColors.amber)
        await clearToastLater()
    }

    private func clearToastLater() async {
        let id = toast?.id
        try? await Task.sleep(nanoseconds: 3_500_000_000)
        if toast?.id == id { toast = nil }
    }

    // MARK: Reminders (Home Assistant sends them)

    private var savingReminders = false
    private var reminderTask: Task<Void, Never>?

    static func parseReminders(_ s: String) -> [Int] {
        // Reminders end at 9:59 pm: the 10 pm default answers the question.
        let list = s.split(separator: ",").compactMap { HAClient.parseTimeOfDay(String($0).trimmingCharacters(in: .whitespaces)) }
            .map { min(max($0, 17 * 60), 21 * 60 + 59) }
        return list.isEmpty ? [19 * 60] : Array(Set(list)).sorted()
    }

    static func reminderString(_ times: [Int]) -> String {
        times.sorted().map { String(format: "%02d:%02d", $0 / 60, $0 % 60) }.joined(separator: ",")
    }

    func setReminder(at index: Int, minutes: Int) {
        guard reminderTimes.indices.contains(index) else { return }
        reminderTimes[index] = min(max(minutes, 17 * 60), 21 * 60 + 59)
        saveReminders()
    }

    func addReminder() {
        let last = reminderTimes.max() ?? 18 * 60 + 30
        var t = min(last + 60, 21 * 60 + 30)
        while reminderTimes.contains(t) && t > 17 * 60 { t -= 15 }
        reminderTimes.append(t)
        saveReminders()
    }

    func removeReminder(at index: Int) {
        guard reminderTimes.count > 1, reminderTimes.indices.contains(index) else { return }
        reminderTimes.remove(at: index)
        saveReminders()
    }

    func setRemindersOn(_ on: Bool) {
        remindersOn = on
        saveReminders()
    }

    private func saveReminders() {
        reminderTask?.cancel()
        savingReminders = true
        reminderTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled, let self else { return }
            defer { self.savingReminders = false }
            guard let ha = HAClient.configured() else { return }
            do {
                try await ha.setText(Entity.reminders, Self.reminderString(self.reminderTimes))
                try await ha.call("input_boolean", self.remindersOn ? "turn_off" : "turn_on", ["entity_id": Entity.remindersOff])
                self.message = nil
            } catch {
                self.message = "Couldn't save reminders to Home Assistant: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Tonight's question (centre card)

    @AppStorage("ask.dismissedNight") private var dismissedNight = ""

    /// Evening key for "tonight" (dismissing the card hides it until tomorrow evening).
    private var nightKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// Sat–Wed, 7–10 pm, Routine, plugged in, not answered, not dismissed tonight.
    var shouldAsk: Bool {
        let cal = Calendar.current
        let now = Date()
        let hour = cal.component(.hour, from: now)
        let weekday = cal.component(.weekday, from: now)   // 1 = Sunday … 7 = Saturday
        guard haConfigured, (19..<22).contains(hour), [7, 1, 2, 3, 4].contains(weekday) else { return false }
        guard (chargingMode ?? "Routine") == "Routine", plugged == true, !answered else { return false }
        return dismissedNight != nightKey
    }

    func dismissAsk() {
        objectWillChange.send()
        dismissedNight = nightKey
    }

    /// GPS / TSET from the centre card: set and plan, then show a one-line result.
    func answerFromCard(_ name: String, limit: Double) async {
        let sends = active && result.minutes > 0
        await chooseTrip(name, limit: limit)
        if sends { return }
        let r = result
        if r.minutes == 0 {
            toast = Banner(title: "\(name) · \(Int(limit))%", detail: "Already at \(Int((liveSoc ?? startSoc).rounded()))%, no charging needed",
                           icon: "checkmark", tint: TSurface.green)
        } else if let st = scheduledStart, active {
            toast = Banner(title: "\(name) · \(Int(limit))%", detail: "Charging starts \(Fmt.clock(st, calendar: .current))",
                           icon: "bolt.fill", tint: TSurface.green)
        } else {
            toast = Banner(title: "\(name) · \(Int(limit))% set", icon: "checkmark", tint: TSurface.green)
        }
        try? await Task.sleep(nanoseconds: 3_500_000_000)
        toast = nil
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
            // The new start is sent to the car only when a trip (GPS / TSET / Others) is tapped.
            if active && startSync != .checking { startSync = .pending }
        } catch {
            message = "Couldn't save to Home Assistant: \(error.localizedDescription)"
        }
    }
}
