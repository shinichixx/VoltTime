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
    /// From the car first showing 99 % to charge complete, four 100 % charges took 29, 31, 19 and 33 min
    /// (1 Oct, 15 Oct, 12 Nov night, 12 Nov afternoon) while every other 1 % takes ~6.6 min. Battery temperature
    /// did not explain the spread. Budget the typical ~31 min: 25 extra minutes per % above 99.
    static let topOffExtraMinutesPerPct = 25.0

    /// Thursday 7 pm – Friday 7 am and Friday 7 pm – Saturday 7 am: Routine has no night charge, only solar by day.
    static func isNoChargeNight(_ now: Date, calendar: Calendar) -> Bool {
        let hour = calendar.component(.hour, from: now)
        guard hour >= 19 || hour < 7 else { return false }
        let evening = calendar.date(byAdding: .hour, value: -7, to: now)!   // the day the night began
        return [5, 6].contains(calendar.component(.weekday, from: evening)) // 1 = Sunday … 7 = Saturday
    }

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

// MARK: - TNB Domestic ToU bill (NEM 3.0), rounded line by line like the real bill.

struct BillRates {
    var energyPeak = 0.2852, energyOff = 0.2443, capacity = 0.0455, network = 0.1285
    var servicePct = 8.0, kwtbbPct = 1.6
}

struct Bill {
    var energyPeak = 0.0, energyOff = 0.0, afa = 0.0, capacity = 0.0, network = 0.0
    var retail = 0.0, incentive = 0.0, serviceTax = 0.0, kwtbb = 0.0
    var credit = 0.0      // NEM, a positive figure taken off
    var total = 0.0

    static func + (a: Bill, b: Bill) -> Bill {
        Bill(energyPeak: a.energyPeak + b.energyPeak, energyOff: a.energyOff + b.energyOff, afa: a.afa + b.afa,
             capacity: a.capacity + b.capacity, network: a.network + b.network, retail: a.retail + b.retail,
             incentive: a.incentive + b.incentive, serviceTax: a.serviceTax + b.serviceTax, kwtbb: a.kwtbb + b.kwtbb,
             credit: a.credit + b.credit, total: a.total + b.total)
    }

    private static func sen(_ v: Double) -> Double { (v * 100 + (v < 0 ? -1e-7 : 1e-7)).rounded() / 100 }

    /// Energy efficiency incentive (RM/kWh, negative) by the month's total import.
    static func incentiveRate(_ kWh: Double) -> Double {
        let bands: [(Double, Double)] = [(200, -25), (250, -24.5), (300, -22.5), (350, -21), (400, -17), (450, -14.5), (500, -12),
                                         (550, -10.5), (600, -9), (650, -7.5), (700, -5.5), (750, -4.5), (800, -4), (850, -2.5),
                                         (900, -1), (1000, -0.5)]
        return (bands.first { kWh <= $0.0 }?.1 ?? 0) / 100
    }

    /// One month. At or below `threshold` kWh: no AFA, retail charge or service tax; above it, service tax is on the
    /// part over the threshold only. No credit is carried to the next month.
    static func month(peak: Double, off: Double, export: Double, afaSen: Double, threshold: Double,
                      rates r: BillRates = BillRates()) -> Bill {
        let total = peak + off
        guard total > 0 else { return Bill() }
        let high = total > 1500 ? 0.10 : 0.0
        let rp = r.energyPeak + high, ro = r.energyOff + high, afa = afaSen / 100, inc = incentiveRate(total)
        let a = min(peak, threshold), b = min(off, max(threshold - a, 0))   // the part free of service tax
        let low = a + b, rest = total - low, over = total > threshold
        var out = Bill()
        out.energyPeak = sen(rp * a) + sen(rp * (peak - a))
        out.energyOff = sen(ro * b) + sen(ro * (off - b))
        out.capacity = sen(r.capacity * low) + sen(r.capacity * rest)
        out.network = sen(r.network * low) + sen(r.network * rest)
        out.incentive = sen(inc * low) + sen(inc * rest)
        if over {
            out.afa = sen(afa * low) + sen(afa * rest)
            out.retail = 10
            let taxed = sen(rp * (peak - a)) + sen(ro * (off - b)) + sen(afa * rest) + sen(r.capacity * rest)
                + sen(r.network * rest) + sen(inc * rest) + out.retail
            out.serviceTax = sen(max(taxed, 0) * r.servicePct / 100)
        }
        if total > 300 {
            out.kwtbb = sen(max(out.energyPeak + out.energyOff + out.capacity + out.network + out.incentive, 0) * r.kwtbbPct / 100)
        }
        // NEM: peak import is offset first, then off-peak; never more than was imported.
        let xp = min(export, peak), xo = min(export - xp, off), x = xp + xo
        out.credit = sen(rp * xp) + sen(ro * xo) + sen(r.capacity * x) + sen(r.network * x) - sen(-inc * x)
        out.total = max(0, sen(out.energyPeak + out.energyOff + out.afa + out.capacity + out.network + out.retail
                               + out.incentive + out.serviceTax + out.kwtbb - out.credit))
        return out
    }
}
