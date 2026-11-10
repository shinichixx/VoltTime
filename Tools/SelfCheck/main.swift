import Foundation

// Runs in CI before the build. Numbers come from screenshots of the two web pages.
var failures = 0
func check(_ name: String, _ got: String, _ want: String) {
    if got == want { print("✓ \(name): \(got)") } else { print("::error::✗ \(name): got \(got), want \(want)"); failures += 1 }
}

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Asia/Kuala_Lumpur")!
func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
    cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}

// Home: 25% → 75%, 32A 240V 93% 79kWh, RM0.4981, ready 05:50 → 12:18 AM, 5h 32m, 39.5 kWh, 42.47 kWh, RM 21.16
let h = HomeMath.calculate(HomeInputs(startSoc: 25, endSoc: 75, amps: 32, volts: 240, efficiencyPct: 93, capacityKWh: 79, tariff: 0.4981))
check("home duration", Fmt.longDuration(h.minutes), "5h 32m")
check("home pack", String(format: "%.1f", h.packKWh), "39.5")
check("home wall", String(format: "%.2f", h.wallKWh), "42.47")
check("home cost", Fmt.rm(h.cost), "RM 21.16")
let now = date(2026, 11, 10, 15, 35)
let s = HomeMath.start(now: now, readyMinutes: 5 * 60 + 50, chargeMinutes: h.minutes, bufferMinutes: 0, clamp: true, calendar: cal)
check("home start", Fmt.clock(s, calendar: cal), "12:18 AM")

// Same cases as the Home Assistant template test
let tue = date(2026, 11, 10, 19, 30)
func plan(_ now: Date, _ soc: Double, _ lim: Double) -> String {
    let r = HomeMath.calculate(HomeInputs(startSoc: soc, endSoc: lim, amps: 32, volts: 240, efficiencyPct: 93, capacityKWh: 79, tariff: 0))
    let st = HomeMath.start(now: now, readyMinutes: 345, chargeMinutes: r.minutes, bufferMinutes: 15, clamp: true, calendar: cal)
    return "\(r.minutes) " + Fmt.clock(st, calendar: cal)
}
check("ha 20→73", plan(tue, 20, 73), "352 11:38 PM")
check("ha weekday peak guard", plan(tue, 10, 100), "597 10:00 PM")
check("ha saturday no guard", plan(date(2026, 11, 14, 19, 30), 10, 100), "597 7:33 PM")
check("ha after midnight", plan(date(2026, 11, 11, 2, 0), 40, 73), "219 2:02 AM")

// Public: 20% → 80%, 250 kW, RM 1.07/kWh → 25 mins, RM 56.35
if case let .ok(minutes, cost, _, _) = PublicMath.estimate(start: 20, end: 80, maxKW: 250, rate: 1.07, perMinute: false) {
    check("public time", Fmt.shortDuration(minutes), "25 mins")
    check("public cost", Fmt.rm(cost), "RM 56.35")
} else { print("::error::public estimate failed"); failures += 1 }
check("public error", "\(PublicMath.estimate(start: 80, end: 20, maxKW: 250, rate: 1, perMinute: false))",
      "\(PublicMath.Outcome.error("Required level must be greater than current level."))")

if failures > 0 { print("\(failures) check(s) failed"); exit(1) }
print("All checks passed")
