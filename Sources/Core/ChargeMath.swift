import Foundation

// Pure maths shared by the app and Tools/SelfCheck. Ported 1:1 from the two web pages
// (tesla-home-charge-planner and Tesla-M3-Charger-Calculator) and the Home Assistant package.

// MARK: - Home (AC wall charging)

struct HomeInputs {
    var startSoc: Double
    var endSoc: Double
    var amps: Double
    var volts: Double
    var efficiencyPct: Double
    var capacityKWh: Double
    var tariff: Double
}

struct HomeResult {
    let deltaPct: Double
    let grossKW: Double
    let netKW: Double
    let packKWh: Double
    let wallKWh: Double
    let cost: Double
    /// Charging duration rounded to whole minutes, including the slow top-off to 100 %.
    let minutes: Int
    /// Extra minutes for the 99 → 100 % top-off (part of `minutes`).
    let taperMinutes: Int
    /// Seconds per 1 % of battery.
    let secondsPerPct: Int
}

enum HomeMath {
    /// Measured 12 Nov 2026 (41 → 100 %, 32 A): 99 → 100 % took 17 min while every other 1 % took ~6.6 min,
    /// because the car ramps the current down (30 → 5 A) for the last percent. Extra minutes per % above 99.
    static let topOffExtraMinutesPerPct = 10.0

    static func calculate(_ i: HomeInputs) -> HomeResult {
        let amps = max(1, i.amps)
        let volts = max(1, i.volts)
        let eff = min(100, max(1, i.efficiencyPct))
        let cap = max(1, i.capacityKWh)
        let tariff = i.tariff.isFinite ? max(0, i.tariff) : 0
        let delta = max(0, i.endSoc - i.startSoc)

        let gross = volts * amps / 1000
        let net = gross * eff / 100
        let pack = delta / 100 * cap
        let wall = pack / (eff / 100)
        let hours = net > 0 ? pack / net : 0
        let taperPct = max(0, min(i.endSoc, 100) - max(i.startSoc, 99))
        let taper = taperPct * topOffExtraMinutesPerPct
        let minutes = Int((hours * 60 + taper).rounded())
        let pace = delta > 0 ? Int((hours * 3600 / delta).rounded()) : 0
        return HomeResult(deltaPct: delta, grossKW: gross, netKW: net, packKWh: pack, wallKWh: wall,
                          cost: wall * tariff, minutes: minutes, taperMinutes: Int(taper.rounded()), secondsPerPct: pace)
    }

    /// Next ready time (hour:minute) after `now`.
    static func nextReady(now: Date, readyMinutes: Int, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: now)
        let today = calendar.date(byAdding: .minute, value: readyMinutes, to: day)!
        return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today)!
    }

    /// Same rules as the Home Assistant script:
    /// start = ready − duration − buffer; never in the past (now + 2 min);
    /// on Mon–Fri never between 2pm and 10pm (TNB peak) → moved to 10pm.
    static func start(now: Date, readyMinutes: Int, chargeMinutes: Int, bufferMinutes: Int,
                      clamp: Bool, calendar: Calendar) -> Date {
        let ready = nextReady(now: now, readyMinutes: readyMinutes, calendar: calendar)
        var s = ready.addingTimeInterval(-Double(chargeMinutes + bufferMinutes) * 60)
        guard clamp else { return s }
        let earliest = now.addingTimeInterval(120)
        if s < earliest { s = earliest }
        let weekday = calendar.component(.weekday, from: s)      // 1 = Sunday … 7 = Saturday
        let hour = calendar.component(.hour, from: s)
        if (2...6).contains(weekday) && hour >= 14 && hour < 22 {
            s = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: s)!
        }
        let secs = calendar.component(.second, from: s)
        return s.addingTimeInterval(-Double(secs))
    }

    /// Simulation only (nothing is scheduled): the clock time charging has to start so that it ends
    /// `bufferMinutes` before `leaveMinutes`. `daysBefore` is 1 when the start falls on the previous day.
    static func simulatedStart(leaveMinutes: Int, chargeMinutes: Int, bufferMinutes: Int) -> (minutes: Int, daysBefore: Int) {
        let total = leaveMinutes - chargeMinutes - bufferMinutes
        let daysBefore = total >= 0 ? 0 : (-total + 1439) / 1440
        return (((total % 1440) + 1440) % 1440, daysBefore)
    }
}

// MARK: - Public (DC fast charging)

enum PublicMath {
    static let batteryKWh = 79.0
    static let efficiency = 0.90

    /// Model 3 LR RWD charging curve: (SoC %, max kW).
    static let curve: [(soc: Double, kw: Double)] = [
        (0, 250), (10, 250), (20, 250), (30, 195), (40, 150), (50, 120),
        (60, 100), (70, 78), (80, 56), (90, 33), (100, 10)
    ]

    static func maxPower(atSoc soc: Double) -> Double {
        if soc <= curve[0].soc { return curve[0].kw }
        if soc >= curve[curve.count - 1].soc { return curve[curve.count - 1].kw }
        for i in 0..<(curve.count - 1) {
            let p1 = curve[i], p2 = curve[i + 1]
            if soc >= p1.soc && soc <= p2.soc {
                let r = (soc - p1.soc) / (p2.soc - p1.soc)
                return p1.kw + r * (p2.kw - p1.kw)
            }
        }
        return 250
    }

    enum Outcome: Equatable {
        case ok(minutes: Double, cost: Double, deliveredKWh: Double, drawnKWh: Double)
        case incomplete
        case error(String)
    }

    static func estimate(start: Double?, end: Double?, maxKW: Double?, rate: Double?, perMinute: Bool) -> Outcome {
        guard let start, let end, let maxKW, let rate else { return .incomplete }
        if start < 0 || start > 100 || end < 0 || end > 100 { return .error("Battery level must be between 0% and 100%.") }
        if start >= end { return .error("Required level must be greater than current level.") }
        if maxKW <= 0 || rate < 0 { return .error("Please check your speed and rate metrics.") }

        var minutes = 0.0
        var delivered = 0.0
        var soc = start
        let step = 0.1
        while soc < end {
            let next = min(soc + step, end)
            let mid = (soc + next) / 2
            let kw = min(maxKW, maxPower(atSoc: mid))
            let kwh = (next - soc) / 100 * batteryKWh
            delivered += kwh
            minutes += kwh / kw * 60
            soc = next
        }
        let drawn = delivered / efficiency
        let cost = perMinute ? minutes * rate : drawn * rate
        return .ok(minutes: minutes, cost: cost, deliveredKWh: delivered, drawnKWh: drawn)
    }
}

// MARK: - Formatting

enum Fmt {
    /// "25 mins" / "1h 5m" (Public page style).
    static func shortDuration(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m) mins"
    }

    /// "5h 32m" / "0h 07m" (Home page style).
    static func longDuration(_ minutes: Int) -> String {
        "\(minutes / 60)h " + String(format: "%02dm", minutes % 60)
    }

    static func rm(_ v: Double) -> String { "RM " + String(format: "%.2f", v) }

    static func clock(_ d: Date, calendar: Calendar) -> String {
        let h = calendar.component(.hour, from: d), m = calendar.component(.minute, from: d)
        let h12 = h % 12 == 0 ? 12 : h % 12
        return "\(h12):" + String(format: "%02d", m) + (h >= 12 ? " PM" : " AM")
    }

    static func clock(minutes: Int) -> String {
        let h = (minutes / 60) % 24, m = minutes % 60
        let h12 = h % 12 == 0 ? 12 : h % 12
        return "\(h12):" + String(format: "%02d", m) + (h >= 12 ? " PM" : " AM")
    }
}
