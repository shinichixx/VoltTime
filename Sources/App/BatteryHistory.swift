import SwiftUI
import Network

// Build 47: battery health and cell balance kept over time.
// Health: one reading a day from Tessie. Cell balance: read in the car from the S3XY Commander's
// "Panda" Wi-Fi (the same feed Scan My Tesla uses), one parked reading a day plus the highest gap on the road.
// Everything lives in Application Support/battery-history.json and goes into backups.

struct CellReading: Codable, Equatable {
    var date: Date
    var maxV: Double
    var minV: Double
    var soc: Double?
    var parked: Bool
    var mv: Double { (maxV - minV) * 1000 }
}

struct HealthPoint: Codable, Equatable {
    var date: Date
    var percent: Double
    var capacityKWh: Double?
}

/// How a cell gap is judged (parked, above 20 %).
enum CellStatus {
    case excellent, normal, watch, check, notJudged

    init(_ r: CellReading) {
        if !r.parked || (r.soc ?? 50) < 20 { self = .notJudged; return }
        switch r.mv {
        case ..<10: self = .excellent
        case ..<20: self = .normal
        case ..<50: self = .watch
        default: self = .check
        }
    }

    var word: String {
        switch self {
        case .excellent: return "Excellent"
        case .normal: return "Normal"
        case .watch: return "Worth watching"
        case .check: return "Check over time"
        case .notJudged: return "Not judged"
        }
    }

    var color: Color {
        switch self {
        case .excellent, .normal: return TSurface.green
        case .watch: return CarColors.amber
        case .check: return CarColors.red
        case .notJudged: return Color(white: 0.45)
        }
    }

    /// Colour for the mV on the Battery row: grey unless it needs attention.
    var rowColor: Color? {
        switch self {
        case .watch: return CarColors.amber
        case .check: return CarColors.red
        default: return nil
        }
    }
}

@MainActor
final class BatteryHistory: ObservableObject {
    static let shared = BatteryHistory()

    @Published private(set) var parked: [CellReading] = []
    @Published private(set) var road: CellReading?
    @Published private(set) var health: [HealthPoint] = []

    nonisolated static var file: URL { AppData.support.appendingPathComponent("battery-history.json") }

    private struct Saved: Codable {
        var parked: [CellReading]
        var road: CellReading?
        var health: [HealthPoint]
    }

    private init() { load() }

    var latestParked: CellReading? { parked.last }

    func load() {
        guard let d = try? Data(contentsOf: Self.file), let s = try? JSONDecoder().decode(Saved.self, from: d) else { return }
        parked = s.parked.sorted { $0.date < $1.date }
        road = s.road
        health = s.health.sorted { $0.date < $1.date }
    }

    private func save() {
        let s = Saved(parked: parked, road: road, health: health)
        if let d = try? JSONEncoder().encode(s) { try? d.write(to: Self.file, options: .atomic) }
    }

    /// One parked reading a day (the latest of the day wins).
    func addParked(_ r: CellReading) {
        let cal = Calendar.current
        if let i = parked.lastIndex(where: { cal.isDate($0.date, inSameDayAs: r.date) }) { parked[i] = r } else { parked.append(r) }
        save()
    }

    /// The highest gap on the current drive (a new drive starts after 30 minutes without readings).
    func addRoad(_ r: CellReading) {
        if let old = road, r.date.timeIntervalSince(old.date) < 1800, old.mv >= r.mv {
            road = CellReading(date: r.date, maxV: old.maxV, minV: old.minV, soc: old.soc, parked: false)
        } else {
            road = r
        }
        save()
    }

    /// One health point a day.
    func addHealth(_ h: BatteryHealth) {
        guard let p = h.healthPercent else { return }
        let point = HealthPoint(date: Date(), percent: p, capacityKWh: h.capacityKWh)
        let cal = Calendar.current
        if let i = health.lastIndex(where: { cal.isDate($0.date, inSameDayAs: point.date) }) { health[i] = point } else { health.append(point) }
        save()
    }

    // MARK: Backup

    func backupData() -> Data? {
        try? JSONEncoder().encode(Saved(parked: parked, road: road, health: health))
    }

    /// Adds days from a backup that aren't here yet. Returns how many days were added.
    @discardableResult
    func merge(_ data: Data) -> Int {
        guard let s = try? JSONDecoder().decode(Saved.self, from: data) else { return 0 }
        let cal = Calendar.current
        var added = 0
        for r in s.parked where !parked.contains(where: { cal.isDate($0.date, inSameDayAs: r.date) }) { parked.append(r); added += 1 }
        for h in s.health where !health.contains(where: { cal.isDate($0.date, inSameDayAs: h.date) }) { health.append(h); added += 1 }
        if road == nil { road = s.road }
        parked.sort { $0.date < $1.date }
        health.sort { $0.date < $1.date }
        save()
        return added
    }
}

// MARK: - S3XY Commander (Panda over Wi-Fi)

/// Listens to the S3XY Commander's Panda feed (UDP 192.168.4.1:1338) while TesLah is open,
/// and works out the highest and lowest cell voltage.
@MainActor
final class S3XYLink: ObservableObject {
    static let shared = S3XYLink()
    static let enabledKey = "car.s3xy.enabled"
    static let ssidKey = "car.s3xy.ssid"

    enum State: Equatable { case off, waiting, receiving }

    @Published private(set) var state: State = .off
    @Published private(set) var frames = 0                 // CAN frames seen this session
    @Published private(set) var current: CellReading?      // live reading
    @Published private(set) var lastFrame: Date?
    // Build 48 diagnostics
    @Published private(set) var onWifi = false
    @Published private(set) var link = "not started"      // NWConnection state
    @Published private(set) var sent = 0
    @Published private(set) var lastError: String?
    private var monitor: NWPathMonitor?

    /// Supplied by the app: SoC and whether the car is parked, from Tessie (used when the car's own gear isn't on the feed).
    var context: () -> (soc: Double?, parked: Bool) = { (nil, true) }

    private var conn: NWConnection?
    private var heartbeat: Timer?
    private var started: Date?
    private var useAllMode = true
    private var bricks: [Int: (v: Double, at: Date)] = [:]
    private var minMax332: (max: Double, min: Double, at: Date)?
    private var canGear: Int?                               // 1 P, 2 R, 3 N, 4 D
    private var lastSaved: Date?
    private var firstGood: Date?

    var enabled: Bool { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }

    func start() {
        guard enabled else { return }
        watchWifi()
        guard conn == nil else { return }
        // No interface restriction: 192.168.4.1 routes over the Commander's Wi-Fi when the iPhone is on it.
        // (Build 47 required Wi-Fi up front, so a link made on 4G never retried and iOS never asked for local network access.)
        let c = NWConnection(host: "192.168.4.1", port: 1338, using: .udp)
        conn = c
        state = .waiting
        started = Date()
        link = "starting"
        c.stateUpdateHandler = { [weak self] st in
            Task { @MainActor in
                guard let self else { return }
                switch st {
                case .ready: self.link = "ready"; self.hello()
                case .waiting(let e): self.link = "waiting"; self.lastError = e.localizedDescription
                case .failed(let e): self.link = "failed"; self.lastError = e.localizedDescription; self.restart()
                case .preparing: self.link = "preparing"
                case .cancelled: self.link = "cancelled"
                default: break
                }
            }
        }
        c.start(queue: .global(qos: .utility))
        receive(on: c)
        hello()
        if heartbeat == nil {
            heartbeat = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        }
    }

    func stop() {
        heartbeat?.invalidate(); heartbeat = nil
        monitor?.cancel(); monitor = nil
        conn?.cancel(); conn = nil
        state = .off
        link = "stopped"
        firstGood = nil
    }

    /// "Connect now": a fresh link (and iOS asks for local network access if it hasn't yet).
    func reconnect() {
        lastError = nil
        conn?.cancel(); conn = nil
        start()
    }

    private func restart() { conn?.cancel(); conn = nil; start() }

    /// Start again whenever the iPhone joins or leaves a Wi-Fi network.
    private func watchWifi() {
        guard monitor == nil else { return }
        let m = NWPathMonitor(requiredInterfaceType: .wifi)
        m.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let now = path.status == .satisfied
                if now != self.onWifi { self.onWifi = now; self.restart() }
            }
        }
        m.start(queue: .global(qos: .utility))
        monitor = m
    }

    private func hello() {
        // "ehllo" asks for every frame; "hello" is the filtered mode some servers expect: alternate until frames arrive.
        let word = useAllMode ? "ehllo" : "hello"
        conn?.send(content: Data(word.utf8), completion: .contentProcessed { [weak self] err in
            Task { @MainActor in
                guard let self else { return }
                if let err { self.lastError = err.localizedDescription } else { self.sent += 1 }
            }
        })
    }

    private func tick() {
        hello()
        if let l = lastFrame, Date().timeIntervalSince(l) < 6 { state = .receiving } else {
            state = .waiting
            firstGood = nil
            if let s = started, Date().timeIntervalSince(s) > 10, Date().timeIntervalSince(lastFrame ?? .distantPast) > 10 {
                if frames == 0 { useAllMode.toggle() }
                restart()   // nothing for 10 s: a fresh link (restart sets started again)
            }
        }
        evaluate()
    }

    private nonisolated func receive(on c: NWConnection) {
        c.receiveMessage { [weak self] data, _, _, error in
            if let data, !data.isEmpty { Task { @MainActor in self?.parse(data) } }
            if error == nil { self?.receive(on: c) }
        }
    }

    private func parse(_ d: Data) {
        let b = [UInt8](d)
        var i = 0
        let now = Date()
        while i + 16 <= b.count {
            let f1 = UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
            let f2 = UInt32(b[i + 4]) | UInt32(b[i + 5]) << 8 | UInt32(b[i + 6]) << 16 | UInt32(b[i + 7]) << 24
            let id = Int(f1 >> 21)
            let len = Int(f2 & 0x0F)
            let p = Array(b[(i + 8)..<(i + 8 + min(len, 8))])
            frame(id, p, now)
            i += 16
        }
        if i > 0 { frames += i / 16; lastFrame = now; state = .receiving }
    }

    private func frame(_ id: Int, _ p: [UInt8], _ now: Date) {
        switch id {
        case 0x332 where p.count >= 4 && p[0] & 0x03 == 1:          // BattBrickMinMax, voltages (2 mV steps)
            let maxRaw = (Int(p[0]) >> 2 | Int(p[1]) << 6) & 0xFFF
            let minRaw = (Int(p[2]) | Int(p[3]) << 8) & 0xFFF
            let mx = Double(maxRaw) * 0.002, mn = Double(minRaw) * 0.002
            if (2.5...4.45).contains(mx), (2.5...4.45).contains(mn), mx >= mn { minMax332 = (mx, mn, now) }
        case 0x401 where p.count == 8:                              // BrickVoltages: 3 bricks per frame, 0.1 mV
            let base = Int(p[0]) * 3
            for k in 0..<3 {
                let raw = Int(p[2 + k * 2]) | Int(p[3 + k * 2]) << 8
                let v = Double(raw) * 0.0001
                if (2.5...4.45).contains(v), base + k < 120 { bricks[base + k] = (v, now) }
            }
        case 0x118 where p.count >= 3:                              // DI_systemStatus: gear at bit 21
            let g = (Int(p[2]) >> 5) & 0x07
            if (1...4).contains(g) { canGear = g }
        default: break
        }
    }

    /// Builds a reading from the freshest data and saves it (parked: once a minute, the latest of the day wins).
    private func evaluate() {
        let now = Date()
        var mx: Double?, mn: Double?
        let fresh = bricks.values.filter { now.timeIntervalSince($0.at) < 20 }
        if fresh.count >= 90 {
            mx = fresh.map(\.v).max(); mn = fresh.map(\.v).min()
        } else if let m = minMax332, now.timeIntervalSince(m.at) < 10 {
            mx = m.max; mn = m.min
        }
        guard let mx, let mn else { return }
        let ctx = context()
        let parked = canGear.map { $0 == 1 } ?? ctx.parked
        let r = CellReading(date: now, maxV: mx, minV: mn, soc: ctx.soc, parked: parked)
        current = r
        if firstGood == nil { firstGood = now }
        guard let f = firstGood, now.timeIntervalSince(f) >= 3 else { return }   // let the numbers settle
        if parked {
            if lastSaved == nil || now.timeIntervalSince(lastSaved!) > 60 {
                BatteryHistory.shared.addParked(r)
                lastSaved = now
            }
        } else {
            BatteryHistory.shared.addRoad(r)
        }
    }
}

// MARK: - Graph with press-and-slide

/// A line over time. Press and slide to see the value and date at that point; "start" and "Today" at the ends.
struct HistoryGraph: View {
    struct Point: Identifiable { let id = UUID(); let date: Date; let value: Double }
    let points: [Point]
    let lo: Double
    let hi: Double
    let guides: [Double]
    let color: Color
    let startLabel: String
    let format: (Double) -> String
    var guideLabel: (Double) -> String = { String(format: "%g", $0) }

    @State private var scrub: Int?

    private static let dateFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "d MMM yyyy"; return f }()

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { g in
                let w = g.size.width - 34, h = g.size.height
                let t0 = points.first?.date.timeIntervalSince1970 ?? 0
                let span = max((points.last?.date.timeIntervalSince1970 ?? 1) - t0, 1)
                let xy: (Point) -> CGPoint = { p in
                    CGPoint(x: points.count == 1 ? w : w * (p.date.timeIntervalSince1970 - t0) / span,
                            y: h - h * (p.value - lo) / max(hi - lo, 0.0001))
                }
                ZStack(alignment: .topLeading) {
                    ForEach(guides, id: \.self) { v in
                        let y = h - h * (v - lo) / max(hi - lo, 0.0001)
                        Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y)) }
                            .stroke(Color(white: 0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        Text(guideLabel(v)).font(.app(size: 9)).foregroundStyle(TeslaDark.rowLabel)
                            .position(x: w + 18, y: y)
                    }
                    Path { p in
                        for (i, pt) in points.enumerated() { if i == 0 { p.move(to: xy(pt)) } else { p.addLine(to: xy(pt)) } }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    if let last = points.last {
                        Circle().fill(color).frame(width: 6, height: 6).position(xy(last))
                    }
                    if let i = scrub, points.indices.contains(i) {
                        let p = xy(points[i])
                        Path { q in q.move(to: CGPoint(x: p.x, y: 0)); q.addLine(to: CGPoint(x: p.x, y: h)) }
                            .stroke(Color(white: 0.45), lineWidth: 1)
                        Circle().fill(.white).frame(width: 8, height: 8).position(p)
                        let label = format(points[i].value) + " · " + Self.dateFmt.string(from: points[i].date)
                        Text(label).font(.app(size: 11, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Color(white: 0.28)))
                            .fixedSize()
                            .position(x: min(max(p.x, 70), w - 40), y: max(p.y - 22, 10))
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            guard !points.isEmpty else { return }
                            let x = min(max(v.location.x, 0), w)
                            scrub = points.indices.min { abs(xy(points[$0]).x - x) < abs(xy(points[$1]).x - x) }
                        }
                        .onEnded { _ in scrub = nil }
                )
            }
            HStack {
                Text(startLabel); Spacer(); Text("Today").padding(.trailing, 34)
            }
            .font(.app(size: 9.5, weight: .medium)).foregroundStyle(TeslaDark.rowLabel)
        }
    }
}

/// 6 W / 6 M / 1 Y / All
struct RangePicker: View {
    let options: [(String, Int?)]        // label, days back (nil = all)
    @Binding var selected: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                Button { selected = i } label: {
                    Text(options[i].0)
                        .font(.app(size: 12, weight: i == selected ? .semibold : .medium))
                        .foregroundStyle(i == selected ? .white : TeslaDark.rowLabel)
                        .frame(maxWidth: .infinity).frame(height: 22)
                        .background(RoundedRectangle(cornerRadius: 7).fill(i == selected ? Color(white: 0.31) : .clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.19)))
    }

    static func cutoff(_ days: Int?) -> Date? {
        guard let d = days else { return nil }
        return Calendar.current.date(byAdding: .day, value: -d, to: Date())
    }
}
