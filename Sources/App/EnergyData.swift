import SwiftUI

// One day of energy per 5-minute slot (older days: 15-minute or hourly), kWh: solar, grid import, grid export, car.
// This is the only energy data kept on the phone; Impact, Energy bars and Energy day graphs all read it (EnergyStore).

struct DayCurve {
    var minutes: Int          // slot length: 5, 15 (saved before build 25), or 60 for days only available hourly
    var solar: [Float]
    var imp: [Float]
    var exp: [Float]
    var car: [Float]

    var count: Int { solar.count }

    init(minutes: Int) {
        self.minutes = minutes
        let n = 1440 / minutes
        solar = Array(repeating: 0, count: n)
        imp = solar
        exp = solar
        car = solar
    }

    /// Compact form for saving: 1 byte slot length, then 4 × slots whole watt-hours as UInt16 (≈770 bytes for a
    /// 15-minute day, ≈190 bytes for an hourly one).
    func packed() -> Data {
        var d = Data([UInt8(minutes)])
        d.reserveCapacity(1 + count * 8)
        for series in [solar, imp, exp, car] {
            for v in series {
                let wh = UInt16(clamping: Int((Double(v) * 1000).rounded()))
                d.append(UInt8(wh & 0xFF))
                d.append(UInt8(wh >> 8))
            }
        }
        return d
    }

    init?(packed d: Data) {
        let bytes = [UInt8](d)
        guard let m = bytes.first, m > 0, 1440 % Int(m) == 0 else { return nil }
        let n = 1440 / Int(m)
        guard bytes.count == 1 + n * 8 else { return nil }
        self.init(minutes: Int(m))
        var idx = 1
        func next() -> Float {
            let v = UInt16(bytes[idx]) | (UInt16(bytes[idx + 1]) << 8)
            idx += 2
            return Float(v) / 1000
        }
        for i in 0..<n { solar[i] = next() }
        for i in 0..<n { imp[i] = next() }
        for i in 0..<n { exp[i] = next() }
        for i in 0..<n { car[i] = next() }
    }

    /// Same energy in longer slots (sums), e.g. 5-minute -> 15-minute for a smoother Day graph.
    func coarsened(to m: Int) -> DayCurve {
        guard m > minutes, m % minutes == 0, 1440 % m == 0 else { return self }
        var c = DayCurve(minutes: m)
        let k = m / minutes
        for i in 0..<count {
            c.solar[i / k] += solar[i]
            c.imp[i / k] += imp[i]
            c.exp[i / k] += exp[i]
            c.car[i / k] += car[i]
        }
        return c
    }

    var isEmpty: Bool { solar.allSatisfy { $0 == 0 } && imp.allSatisfy { $0 == 0 } && car.allSatisfy { $0 == 0 } }

    /// The same split as Impact: solar serves the house first, the car gets what's left, the rest is exported.
    func flow(_ i: Int) -> EnergyFlow {
        .step(solar: Double(solar[i]), imp: Double(imp[i]), exp: Double(exp[i]), car: Double(car[i]))
    }

    var total: EnergyFlow {
        (0..<count).reduce(EnergyFlow()) { $0 + flow($1) }
    }
}

/// Energy (kWh) over some span, and where it went. Every field adds up across slots and days.
struct EnergyFlow {
    var solar = 0.0      // generated
    var imp = 0.0        // from TNB
    var exp = 0.0        // to TNB
    var car = 0.0        // into the Model 3
    var carSolar = 0.0   // car energy covered by solar
    var homeSolar = 0.0  // house (excl. car) covered by solar
    var homeGrid = 0.0   // house (excl. car) from the grid

    var carGrid: Double { max(car - carSolar, 0) }
    var house: Double { homeSolar + homeGrid }

    static func + (a: EnergyFlow, b: EnergyFlow) -> EnergyFlow {
        EnergyFlow(solar: a.solar + b.solar, imp: a.imp + b.imp, exp: a.exp + b.exp, car: a.car + b.car,
                   carSolar: a.carSolar + b.carSolar, homeSolar: a.homeSolar + b.homeSolar, homeGrid: a.homeGrid + b.homeGrid)
    }

    /// One time step: solar serves the house first, the car gets what's left, the rest is exported.
    static func step(solar s: Double, imp i: Double, exp e: Double, car c: Double) -> EnergyFlow {
        let solarUsed = max(s - e, 0)
        let house = max(s + i - e - c, 0)
        let carSolar = min(c, max(solarUsed - house, 0))
        let homeSolar = min(house, max(solarUsed - carSolar, 0))
        return EnergyFlow(solar: s, imp: i, exp: e, car: c, carSolar: carSolar, homeSolar: homeSolar, homeGrid: max(house - homeSolar, 0))
    }

    init(solar: Double = 0, imp: Double = 0, exp: Double = 0, car: Double = 0,
         carSolar: Double = 0, homeSolar: Double = 0, homeGrid: Double = 0) {
        self.solar = solar; self.imp = imp; self.exp = exp; self.car = car
        self.carSolar = carSolar; self.homeSolar = homeSolar; self.homeGrid = homeGrid
    }
}

