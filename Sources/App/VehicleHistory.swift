import SwiftUI

// Build 105: the Vehicle energy view's "Used" (below zero) and Charge Level graphs, from Tessie's state history.
// Charging (above zero) still comes from Home Assistant, split solar / grid like the other views.
//
// Per day, per 5-minute slot: battery % and the energy that left the battery, split into driving and standby
// (parked: climate, Sentry, sleep drain). Build 109: kept for good in Application Support (about 1.4 kB a day),
// in backups and snapshots. A finished day is read from Tessie once; only today and the charge limit are read
// each time the app opens.

struct VehicleDay {
    var minutes: Int          // 5 (Day graphs), 15 (fetched for Week / Month bars) or 60 (Year / Lifetime)
    var soc: [Float]          // %, -1 = no reading in that slot
    var drive: [Float]        // kWh used driving
    var idle: [Float]         // kWh used parked
    var complete: Bool        // the day was over when it was read (saved; today never is)

    var count: Int { soc.count }

    init(minutes: Int) {
        self.minutes = minutes
        let n = 1440 / minutes
        soc = Array(repeating: -1, count: n)
        drive = Array(repeating: 0, count: n)
        idle = drive
        complete = false
    }

    var driveTotal: Double { drive.reduce(0) { $0 + Double($1) } }
    var idleTotal: Double { idle.reduce(0) { $0 + Double($1) } }
    var hasSoc: Bool { soc.contains { $0 >= 0 } }

    /// 1 byte slot length, then per slot: battery % × 2 (255 = none), driving Wh, standby Wh (UInt16 each).
    func packed() -> Data {
        var d = Data([UInt8(minutes)])
        d.reserveCapacity(1 + count * 5)
        for i in 0..<count {
            d.append(soc[i] < 0 ? 255 : UInt8(clamping: Int((Double(soc[i]) * 2).rounded())))
            for v in [drive[i], idle[i]] {
                let wh = UInt16(clamping: Int((Double(v) * 1000).rounded()))
                d.append(UInt8(wh & 0xFF)); d.append(UInt8(wh >> 8))
            }
        }
        return d
    }

    init?(packed d: Data) {
        let b = [UInt8](d)
        guard let m = b.first, m > 0, 1440 % Int(m) == 0 else { return nil }
        let n = 1440 / Int(m)
        guard b.count == 1 + n * 5 else { return nil }
        self.init(minutes: Int(m))
        complete = true
        var i = 1
        for s in 0..<n {
            soc[s] = b[i] == 255 ? -1 : Float(b[i]) / 2
            drive[s] = Float(UInt16(b[i + 1]) | UInt16(b[i + 2]) << 8) / 1000
            idle[s] = Float(UInt16(b[i + 3]) | UInt16(b[i + 4]) << 8) / 1000
            i += 5
        }
    }
}

/// One reading from Tessie's history.
struct VehicleSample {
    let t: Date
    let soc: Double?
    let energy: Double?       // kWh left in the pack
    let odo: Double?          // km
    let charging: Bool
    let moving: Bool

    init?(_ s: [String: Any]) {
        func num(_ k: String) -> Double? {
            if let v = s[k] as? Double { return v }
            if let v = s[k] as? Int { return Double(v) }
            if let v = s[k] as? NSNumber { return v.doubleValue }
            if let v = s[k] as? String { return Double(v) }
            return nil
        }
        guard var ts = num("timestamp") ?? num("id") else { return nil }
        if ts > 1e12 { ts /= 1000 }   // milliseconds
        t = Date(timeIntervalSince1970: ts)
        soc = num("battery_level") ?? num("usable_battery_level")
        energy = num("energy_remaining")
        odo = num("odometer")
        let cs = (s["charging_state"] as? String ?? "").lowercased()
        charging = cs == "charging" || cs == "starting"
        let shift = (s["shift_state"] as? String ?? "").uppercased()
        moving = ["D", "R", "N"].contains(shift) || (num("speed") ?? 0) > 0.5
    }
}

@MainActor
final class VehicleHistory: ObservableObject {
    static let shared = VehicleHistory()

    @Published private(set) var days: [String: VehicleDay] = [:]
    @Published private(set) var loading = false
    @Published private(set) var message: String?
    /// The car's latest charge limit (drawn as the band behind the Charge Level curve).
    @Published private(set) var limit: Double? = UserDefaults.standard.object(forKey: "car.limitLatest") as? Double

    private let cal = Calendar.current
    private var todayRead: Date?
    private var inFlight: Set<String> = []

    nonisolated static var file: URL { AppData.support.appendingPathComponent("vehicle-history.plist") }

    private init() {
        // Builds 105-108 kept it in Caches: move it across so nothing has to be read again.
        let old = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("vehicle-history.plist")
        if !FileManager.default.fileExists(atPath: Self.file.path), FileManager.default.fileExists(atPath: old.path) {
            try? FileManager.default.moveItem(at: old, to: Self.file)
        }
        if let d = try? Data(contentsOf: Self.file), let saved = try? PropertyListDecoder().decode([String: Data].self, from: d) {
            var out: [String: VehicleDay] = [:]
            for (k, v) in saved { if let day = VehicleDay(packed: v) { out[k] = day } }
            days = out
        }
    }

    private func key(_ d: Date) -> String { EnergyStore.keyFormatter.string(from: d) }
    func day(_ d: Date) -> VehicleDay? { days[key(cal.startOfDay(for: d))] }

    private func save() {
        let keep = days.filter { $0.value.complete }.mapValues { $0.packed() }
        if let d = try? PropertyListEncoder().encode(keep) { try? d.write(to: Self.file, options: .atomic) }
    }

    /// Restore from a backup: adds the days this phone doesn't have (or has in less detail). Returns how many.
    func merge(_ data: Data) -> Int {
        guard let saved = try? PropertyListDecoder().decode([String: Data].self, from: data) else { return 0 }
        var n = 0
        for (k, v) in saved {
            guard let day = VehicleDay(packed: v) else { continue }
            if let have = days[k], have.complete, have.minutes <= day.minutes { continue }
            days[k] = day
            n += 1
        }
        if n > 0 { save() }
        return n
    }

    /// Each time the app opens: today's battery % and the latest charge limit (finished days stay as saved).
    func refreshToday() async {
        guard let t = TessieClient.configured(),
              let vin = UserDefaults.standard.string(forKey: TessieClient.vinKey), !vin.isEmpty else { return }
        await readLimit(t, vin)
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? today
        await fill(t, vin, minutes: 5, from: today, to: tomorrow)
    }

    // MARK: Reading what's saved

    /// Energy used between two times, (driving, standby) kWh; slots cut by the span count in proportion.
    func used(from a: Date, to b: Date) -> (drive: Double, idle: Double) {
        guard b > a else { return (0, 0) }
        var drive = 0.0, idle = 0.0
        var d = cal.startOfDay(for: a)
        while d < b {
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            if let day = days[key(d)] {
                let step = TimeInterval(day.minutes * 60)
                let lo = max(a, d), hi = min(b, next)
                if hi > lo {
                    if lo == d && hi == next {
                        drive += day.driveTotal; idle += day.idleTotal
                    } else {
                        let i0 = max(0, Int(lo.timeIntervalSince(d) / step)), i1 = min(day.count - 1, Int((hi.timeIntervalSince(d) - 0.001) / step))
                        if i0 <= i1 {
                            for i in i0...i1 {
                                let s0 = d.addingTimeInterval(Double(i) * step), s1 = s0.addingTimeInterval(step)
                                let part = max(0, min(hi, s1).timeIntervalSince(max(lo, s0))) / step
                                drive += Double(day.drive[i]) * part
                                idle += Double(day.idle[i]) * part
                            }
                        }
                    }
                }
            }
            d = next
        }
        return (drive, idle)
    }

    /// Battery % over a span, at most `maxPoints` points (a day at 5 minutes is 288).
    func soc(from a: Date, to b: Date, maxPoints: Int = 400) -> [(Date, Double)] {
        var raw: [(Date, Double)] = []
        var d = cal.startOfDay(for: a)
        let end = min(b, Date())
        while d < end {
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            if let day = days[key(d)] {
                let step = TimeInterval(day.minutes * 60)
                for i in 0..<day.count where day.soc[i] >= 0 {
                    let t = d.addingTimeInterval(Double(i) * step + step / 2)
                    if t >= a && t <= end { raw.append((t, Double(day.soc[i]))) }
                }
            }
            d = next
        }
        guard raw.count > maxPoints else { return raw }
        let every = Int(ceil(Double(raw.count) / Double(maxPoints)))
        return stride(from: 0, to: raw.count, by: every).map { raw[$0] }
    }

    /// Days in the span with any reading.
    func covered(from a: Date, to b: Date) -> Bool {
        var d = cal.startOfDay(for: a)
        while d < min(b, Date()) {
            if days[key(d)] != nil { return true }
            guard let n = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = n
        }
        return false
    }

    // MARK: Fetching from Tessie

    /// Makes sure the period on screen is read: Day at 5 minutes; Week / Month / Custom at 15; Year / Lifetime hourly.
    /// Saved days aren't read again; today is topped up at most once a minute.
    func ensure(_ period: ImpactPeriod, _ range: PeriodRange) async {
        guard let t = TessieClient.configured(),
              let vin = UserDefaults.standard.string(forKey: TessieClient.vinKey), !vin.isEmpty else {
            message = "Add your Tessie token in Settings to see the car's use."
            return
        }
        message = nil
        await readLimit(t, vin)
        let minutes = period == .day ? 5 : ((period == .year || period == .lifetime) ? 60 : 15)
        let today = cal.startOfDay(for: Date())
        let end = min(range.end, cal.date(byAdding: .day, value: 1, to: today) ?? range.end)
        await fill(t, vin, minutes: minutes, from: cal.startOfDay(for: range.start), to: end)
    }

    /// Reads whatever of [start, end) isn't saved yet: nothing for saved finished days, today at most once a minute.
    private func fill(_ t: TessieClient, _ vin: String, minutes: Int, from rangeStart: Date, to end: Date) async {
        let today = cal.startOfDay(for: Date())
        var start = rangeStart
        // Skip saved days at the front and back; read the stretch in between in one go.
        func needs(_ d: Date) -> Bool {
            if d >= today { return todayRead.map { Date().timeIntervalSince($0) > 60 } ?? true || (days[key(d)]?.minutes ?? 99) > minutes }
            guard let have = days[key(d)] else { return true }
            return !have.complete || have.minutes > minutes   // a day read before it was over is read again once
        }
        while start < end, !needs(start) { start = cal.date(byAdding: .day, value: 1, to: start) ?? end }
        var last = cal.date(byAdding: .day, value: -1, to: end) ?? start
        while last > start, !needs(last) { last = cal.date(byAdding: .day, value: -1, to: last) ?? start }
        guard start < end, needs(start) else { return }
        let stop = cal.date(byAdding: .day, value: 1, to: last) ?? end
        let tag = "\(key(start))|\(key(stop))|\(minutes)"
        guard !inFlight.contains(tag) else { return }
        inFlight.insert(tag)
        loading = true
        defer { loading = false; inFlight.remove(tag) }

        // Up to ~2,500 readings per request.
        let chunk = TimeInterval(minutes * 60 * 2500)
        var from = start
        do {
            while from < stop {
                let to = min(stop, from.addingTimeInterval(chunk))
                // A little either side, so the first and last slots have a reading to compare with.
                let states = try await t.history(vin, from: from.addingTimeInterval(-Double(minutes) * 60 * 3),
                                                 to: min(Date(), to.addingTimeInterval(Double(minutes) * 60 * 3)),
                                                 interval: minutes * 60)
                let samples = states.compactMap(VehicleSample.init).sorted { $0.t < $1.t }
                build(samples, from: from, to: to, minutes: minutes)
                from = to
            }
            if stop > today { todayRead = Date() }
            save()
        } catch {
            message = error.localizedDescription
        }
    }

    /// Latest charge limit, from Tessie's cached state (doesn't wake the car); once every 10 minutes.
    private var limitRead: Date?
    private func readLimit(_ t: TessieClient, _ vin: String) async {
        if let r = limitRead, Date().timeIntervalSince(r) < 600 { return }
        guard let s = try? await t.state(vin) else { return }
        limitRead = Date()
        let cs = s["charge_state"] as? [String: Any]
        let v = (cs?["charge_limit_soc"] as? Double) ?? (cs?["charge_limit_soc"] as? Int).map(Double.init)
        if let v { limit = v; UserDefaults.standard.set(v, forKey: "car.limitLatest") }
    }

    /// Turns readings into days of slots. Energy that left the pack between two readings is spread over the time
    /// between them: driving if the car moved, else standby. Nothing is counted while it charges.
    private func build(_ s: [VehicleSample], from: Date, to: Date, minutes: Int) {
        guard !s.isEmpty else { return }
        let step = TimeInterval(minutes * 60)
        var built: [String: VehicleDay] = [:]
        func slot(_ t: Date) -> (String, Date, Int)? {
            guard t >= from, t < to else { return nil }
            let d = cal.startOfDay(for: t)
            return (key(d), d, min(1440 / minutes - 1, Int(t.timeIntervalSince(d) / step)))
        }
        // Battery %: the last reading in each slot.
        for x in s {
            guard let soc = x.soc, let sl = slot(x.t) else { continue }
            if built[sl.0] == nil { built[sl.0] = VehicleDay(minutes: minutes) }
            built[sl.0]!.soc[sl.2] = Float(soc)
        }
        // Capacity for packs that don't report energy_remaining: from any reading that has both.
        let cap = s.first { ($0.energy ?? 0) > 1 && ($0.soc ?? 0) > 5 }.map { $0.energy! / ($0.soc! / 100) } ?? 75
        func energy(_ x: VehicleSample) -> Double? { x.energy ?? x.soc.map { $0 / 100 * cap } }
        for (a, b) in zip(s, s.dropFirst()) {
            guard !a.charging, !b.charging, let ea = energy(a), let eb = energy(b) else { continue }
            let used = ea - eb
            let span = b.t.timeIntervalSince(a.t)
            guard used > 0.005, span > 0, span < 36 * 3600, used < 100 else { continue }
            let drove = a.moving || b.moving || ((b.odo ?? 0) - (a.odo ?? 0)) > 0.2
            // Spread across the slots it covers.
            var t0 = a.t
            while t0 < b.t {
                let d = cal.startOfDay(for: t0)
                let i = Int(t0.timeIntervalSince(d) / step)
                let slotEnd = d.addingTimeInterval(Double(i + 1) * step)
                let t1 = min(b.t, slotEnd)
                if let sl = slot(t0) {
                    if built[sl.0] == nil { built[sl.0] = VehicleDay(minutes: minutes) }
                    let part = Float(used * t1.timeIntervalSince(t0) / span)
                    if drove { built[sl.0]!.drive[sl.2] += part } else { built[sl.0]!.idle[sl.2] += part }
                }
                t0 = t1
            }
        }
        let today = cal.startOfDay(for: Date())
        var d = cal.startOfDay(for: from)
        while d < to {
            let k = key(d)
            var day = built[k] ?? VehicleDay(minutes: minutes)
            day.complete = d < today && (cal.date(byAdding: .day, value: 1, to: d).map { Date().timeIntervalSince($0) > 600 } ?? false)
            // A finer day already saved stays (a Week read never replaces a Day read).
            if let have = days[k], have.minutes < minutes, d < today { } else { days[k] = day }
            guard let n = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = n
        }
    }
}

// MARK: - Charge Level graph (Tesla app: battery % in front of the charge limit, edge to edge)

struct ChargeLevelGraph: View {
    @ObservedObject var vehicle: VehicleHistory
    let period: ImpactPeriod
    let range: PeriodRange
    /// Changes with the period on screen: the graph slides out and the next one slides in (as the graph above).
    var slideID = ""
    var forward = false
    var swipe: (Int) -> Void = { _ in }
    var onHold: (Bool) -> Void = { _ in }
    @State private var folded = false
    /// Tap and hold: the time being read.
    @State private var hold: Date?
    @State private var holding = false

    private static let back = Color(red: 0.13, green: 0.36, blue: 0.24)        // the limit band
    private static let front = Color(red: 0.19, green: 0.62, blue: 0.39)       // battery % fill
    private static let line = Color(red: 0.29, green: 0.88, blue: 0.56)        // battery % edge

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Charge Level").font(.app(size: 14, weight: .semibold))
                Spacer()
                Button { withAnimation(.easeInOut(duration: 0.3)) { folded.toggle() } } label: {
                    Image(systemName: "chevron.up").font(.system(size: 14, weight: .medium))
                        .rotationEffect(.degrees(folded ? 180 : 0))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.top, 18)
            if !folded {
                ZStack {
                    VStack(spacing: 0) {
                        graph
                            .frame(height: 112)
                            .padding(.top, 10)
                        labels.padding(.top, 6)
                    }
                    .id(slideID)
                    .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading),
                                            removal: .move(edge: forward ? .leading : .trailing)))
                }
                .clipped()
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .clipped()
        .onChange(of: slideID) { _, _ in endHold() }
    }

    private func endHold() {
        hold = nil
        if holding { holding = false; onHold(false) }
    }

    /// Touch on the graph: tap and hold (then move) reads the charge, a sideways swipe turns the page; a vertical
    /// drag isn't taken, so the page scrolls from here too.
    private func touched(_ x: CGFloat?, width: CGFloat) {
        guard let x else { endHold(); return }
        let f = min(max(x / max(width, 1), 0), 1)
        hold = range.start.addingTimeInterval(range.end.timeIntervalSince(range.start) * Double(f))
        if !holding { holding = true; onHold(true) }
    }

    /// Battery % at a time, as the curve draws it: carried from the first reading to the left edge and from the
    /// last to the right edge (to now on today); nothing past now.
    private func socAt(_ t: Date, _ p: [(Date, Double)]) -> Double? {
        guard let first = p.first, let last = p.last else { return nil }
        if range.end > Date() && t > Date() { return nil }
        if t <= first.0 { return first.1 }
        if t >= last.0 { return last.1 }
        guard let i = p.firstIndex(where: { $0.0 >= t }), i > 0 else { return last.1 }
        let a = p[i - 1], b = p[i]
        let span = b.0.timeIntervalSince(a.0)
        guard span > 0 else { return b.1 }
        return a.1 + (b.1 - a.1) * t.timeIntervalSince(a.0) / span
    }

    private func timeLabel(_ t: Date) -> String {
        let hm = t.formatted(.dateTime.hour().minute())
        return period == .day ? hm : "\(t.formatted(.dateTime.day().month(.abbreviated))), \(hm)"
    }

    /// The reading line, a dot on the battery curve and the box (beside the finger, flipped near the right edge).
    @ViewBuilder private func holdLayer(_ size: CGSize, _ p: [(Date, Double)]) -> some View {
        if let t = hold {
            let span = max(range.end.timeIntervalSince(range.start), 1)
            let px = size.width * CGFloat(t.timeIntervalSince(range.start) / span)
            let soc = socAt(t, p)
            let top: CGFloat = 4
            let dotY = soc.map { top + (size.height - top) * (1 - CGFloat(min(max($0, 0), 100)) / 100) }
            let boxW: CGFloat = 132
            let right = px + 10 + boxW <= size.width - 4
            ZStack(alignment: .topLeading) {
                Path { l in l.move(to: CGPoint(x: px, y: 0)); l.addLine(to: CGPoint(x: px, y: size.height)) }
                    .stroke(Color.white.opacity(0.85), lineWidth: 1)
                if let dotY {
                    Circle().fill(Self.line).frame(width: 8, height: 8)
                        .overlay(Circle().stroke(TeslaDark.bg, lineWidth: 1.5))
                        .position(x: px, y: dotY)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(timeLabel(t)).font(.app(size: 11)).foregroundStyle(TeslaDark.rowLabel)
                    holdRow(Self.line, "Charge", soc.map { "\(Int($0.rounded()))%" } ?? "–")
                    holdRow(Self.front, "Limit", vehicle.limit.map { "\(Int($0.rounded()))%" } ?? "–")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(width: boxW, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(white: 0.21)))
                .offset(x: right ? px + 10 : max(4, px - 10 - boxW), y: 6)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .allowsHitTesting(false)
        }
    }

    private func holdRow(_ c: Color, _ name: String, _ value: String) -> some View {
        HStack(spacing: 7) {
            Circle().fill(c).frame(width: 7, height: 7)
            Text(name).font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
            Spacer(minLength: 6)
            Text(value).font(.app(size: 12.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(value == "–" ? TeslaDark.rowLabel : Color.white)
        }
        .lineLimit(1)
    }

    private var pts: [(Date, Double)] { vehicle.soc(from: range.start, to: range.end) }

    private var graph: some View {
        let p = pts
        let limit = vehicle.limit
        let t0 = range.start.timeIntervalSince1970
        let span = max(range.end.timeIntervalSince1970 - t0, 1)
        return Canvas { ctx, size in
            let w = size.width, h = size.height
            let top: CGFloat = 4           // room for the 100% line
            let plotH = h - top
            func y(_ pct: Double) -> CGFloat { top + plotH * (1 - CGFloat(min(max(pct, 0), 100)) / 100) }
            func x(_ d: Date) -> CGFloat { w * CGFloat((d.timeIntervalSince1970 - t0) / span) }
            // 100% line, faint.
            var hundred = Path(); hundred.move(to: CGPoint(x: 0, y: y(100))); hundred.addLine(to: CGPoint(x: w, y: y(100)))
            ctx.stroke(hundred, with: .color(Color.white.opacity(0.12)), style: StrokeStyle(lineWidth: 0.6, dash: [1.5, 3]))
            // Back: the charge limit, the whole width.
            if let limit {
                ctx.fill(Path(CGRect(x: 0, y: y(limit), width: w, height: h - y(limit))), with: .color(Self.back.opacity(0.55)))
            }
            // Dotted time lines (Day: 6 AM, 12 PM, 6 PM).
            if period == .day {
                for hr in [6.0, 12, 18] {
                    let px = x(range.start.addingTimeInterval(hr * 3600))
                    var l = Path(); l.move(to: CGPoint(x: px, y: top)); l.addLine(to: CGPoint(x: px, y: h))
                    ctx.stroke(l, with: .color(Color.white.opacity(0.12)), style: StrokeStyle(lineWidth: 0.6, dash: [1.5, 4]))
                }
            }
            // Front: battery %, carried to the left edge from the first reading (and to the right on a past day).
            guard let first = p.first, let lastPt = p.last else { return }
            var curve: [CGPoint] = [CGPoint(x: 0, y: y(first.1))]
            curve += p.map { CGPoint(x: x($0.0), y: y($0.1)) }
            let endX = range.end <= Date() ? w : min(w, x(Date()))
            curve.append(CGPoint(x: endX, y: y(lastPt.1)))
            var edge = Path()
            edge.move(to: curve[0])
            for q in curve.dropFirst() { edge.addLine(to: q) }
            var fill = edge
            fill.addLine(to: CGPoint(x: endX, y: h)); fill.addLine(to: CGPoint(x: 0, y: h)); fill.closeSubpath()
            ctx.fill(fill, with: .linearGradient(Gradient(colors: [Self.front.opacity(0.85), Color.black.opacity(0)]),
                                                 startPoint: CGPoint(x: 0, y: y(100)), endPoint: CGPoint(x: 0, y: h)))
            ctx.stroke(edge, with: .color(Self.line), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
            // Baseline dots: brighter at the labelled times.
            if period == .day {
                for hr in 0...24 {
                    let px = x(range.start.addingTimeInterval(Double(hr) * 3600))
                    let big = [6, 12, 18].contains(hr)
                    let r: CGFloat = big ? 1.6 : 1
                    ctx.fill(Path(ellipseIn: CGRect(x: px - r, y: h - r, width: r * 2, height: r * 2)),
                             with: .color(big ? .white : Color(white: 0.45)))
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Text("100%").font(.app(size: 10.5, weight: .medium)).foregroundStyle(TeslaDark.rowLabel)
                .chartLabelGlow().padding(.trailing, 6).padding(.top, 6)
        }
        .overlay(alignment: .bottomTrailing) {
            Text("0").font(.app(size: 10.5, weight: .medium)).foregroundStyle(TeslaDark.rowLabel)
                .chartLabelGlow().padding(.trailing, 6).padding(.bottom, 4)
        }
        .overlay {
            GeometryReader { g in
                ZStack {
                    ChargeTouch(onHold: { touched($0, width: g.size.width) }, onSwipe: swipe)
                    holdLayer(g.size, p)
                }
            }
        }
        .overlay {
            if p.isEmpty {
                Text(vehicle.loading ? "Reading the car's history…" : (vehicle.message ?? "No battery data for this period"))
                    .font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
            }
        }
    }

    /// Day: 6 AM, 12 PM, 6 PM under their lines; longer periods: the first and last day.
    private var labels: some View {
        GeometryReader { g in
            let span = max(range.end.timeIntervalSince(range.start), 1)
            if period == .day {
                ForEach([6, 12, 18], id: \.self) { hr in
                    let d = range.start.addingTimeInterval(Double(hr) * 3600)
                    Text(hr == 12 ? "12 PM" : (hr < 12 ? "\(hr) AM" : "\(hr - 12) PM"))
                        .font(.app(size: 11)).foregroundStyle(TeslaDark.rowLabel)
                        .fixedSize()
                        .position(x: g.size.width * CGFloat(d.timeIntervalSince(range.start) / span), y: 7)
                }
            } else {
                HStack {
                    Text(range.start.formatted(.dateTime.day().month(.abbreviated)))
                    Spacer()
                    Text(range.end.addingTimeInterval(-1).formatted(.dateTime.day().month(.abbreviated)))
                }
                .font(.app(size: 11)).foregroundStyle(TeslaDark.rowLabel)
                .padding(.horizontal, 20)
            }
        }
        .frame(height: 14)
    }
}

/// UIKit touch layer for the Charge Level graph: a long press that follows the finger, and a pan that only starts
/// for a sideways move (so a vertical drag goes on to scroll the page, and both can run beside the scroll view).
struct ChargeTouch: UIViewRepresentable {
    var onHold: (CGFloat?) -> Void
    var onSwipe: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pressed(_:)))
        press.minimumPressDuration = 0.25
        press.allowableMovement = 12
        press.delegate = context.coordinator
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.panned(_:)))
        pan.delegate = context.coordinator
        v.addGestureRecognizer(press)
        v.addGestureRecognizer(pan)
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) { context.coordinator.parent = self }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: ChargeTouch
        init(_ p: ChargeTouch) { parent = p }

        @objc func pressed(_ g: UILongPressGestureRecognizer) {
            switch g.state {
            case .began, .changed: parent.onHold(g.location(in: g.view).x)
            case .ended, .cancelled, .failed: parent.onHold(nil)
            default: break
            }
        }

        @objc func panned(_ g: UIPanGestureRecognizer) {
            guard g.state == .ended else { return }
            let t = g.translation(in: g.view)
            guard abs(t.x) > 50, abs(t.x) > abs(t.y) * 1.4 else { return }
            parent.onSwipe(t.x < 0 ? 1 : -1)   // finger to the left: the next (later) period
        }

        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let pan = g as? UIPanGestureRecognizer else { return true }
            let v = pan.velocity(in: pan.view)
            return abs(v.x) > abs(v.y) * 1.4
        }

        func gestureRecognizer(_ a: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith b: UIGestureRecognizer) -> Bool {
            // The page's own scroll may run beside ours; our press and pan never run together.
            !(a.view === b.view)
        }
    }
}
