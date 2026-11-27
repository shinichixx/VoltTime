import SwiftUI

/// Power flow on the My Home photo, like the Tesla app: the wires are plain dark conduits, and a long streak
/// (bright head, fading tail) runs along them in the direction power flows, one at a time per route.
/// A streak keeps going through the meter box: solar from the roof through the inverter and the box into the
/// house, grid from the street through the box into the house. Into the house there are two lanes:
/// green = the solar share, yellow = the grid share. Each wire section moves at the speed of the power it carries
/// (FlowSpeed), so a streak changes pace as it passes the box.
struct PowerFlowOverlay: View {
    @ObservedObject var model: MyHomeModel
    let width: CGFloat
    @Environment(\.scenePhase) private var phase
    @State private var visible = false
    @State private var clock = FlowClock()

    // Wire routes in photo pixels (scenario photos are 1179 px wide), listed in the direction of flow.
    private static let solarWire: [CGPoint] = [.init(x: 627, y: 946), .init(x: 630, y: 955), .init(x: 648, y: 990), .init(x: 648, y: 1062)]
    private static let inverterToBox: [CGPoint] = [.init(x: 679, y: 1086), .init(x: 777, y: 1058)]
    private static let boxToHouse: [CGPoint] = [.init(x: 802, y: 1052), .init(x: 934, y: 1017)]
    private static let gridToBox: [CGPoint] = [.init(x: 935, y: 1211), .init(x: 796, y: 1160), .init(x: 792, y: 1150), .init(x: 792, y: 1095)]
    private static let carCable: [CGPoint] = [
        .init(x: 325, y: 1012), .init(x: 326, y: 1050), .init(x: 330, y: 1072), .init(x: 337, y: 1092),
        .init(x: 346, y: 1102), .init(x: 352, y: 1096), .init(x: 355, y: 1082), .init(x: 358, y: 1070),
    ]
    /// The two lanes into the house, either side of the wire's centre line (photo px).
    private static let laneOffset: CGFloat = 4
    private static let photoWidth: CGFloat = 1179
    private static let photoHeight: CGFloat = 1579
    /// Photos where the charging cable is drawn lit (green); it gets repainted as a plain cable.
    private static let litCable: Set<Int> = [1, 4, 7]

    static let green = Color(red: 0.30, green: 0.95, blue: 0.45)
    static let yellow = Color(red: 1.0, green: 0.84, blue: 0.16)
    private static let pipe = Color(red: 36 / 255, green: 37 / 255, blue: 40 / 255)
    private static let pipeEdge = Color(red: 52 / 255, green: 53 / 255, blue: 57 / 255)
    private static let cable = Color(white: 0.05)   // plain black cable; the flow is drawn green on top

    /// One streak route: wire pieces joined end to end; the hop between pieces (inside the box) isn't drawn.
    private struct Route {
        let id: String
        let pieces: [[CGPoint]]   // screen points
        let watts: [Double]       // the power each piece carries (sets its speed)
        let color: Color
        var width: CGFloat = 1.5  // core line, points
    }

    var body: some View {
        ZStack {
            // The conduits, drawn once over the colours baked into the photo.
            Canvas { ctx, _ in drawConduits(&ctx) }
            TimelineView(.animation(minimumInterval: nil, paused: !visible || phase != .active)) { tl in
                Canvas { ctx, _ in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    for r in routes { draw(r, t, &ctx) }
                }
            }
        }
        .frame(width: width, height: width * Self.photoHeight / Self.photoWidth)
        .allowsHitTesting(false)
        .onAppear { visible = true }
        .onDisappear { visible = false }
    }

    private var k: CGFloat { width / Self.photoWidth }
    private func screen(_ pts: [CGPoint]) -> [CGPoint] { pts.map { CGPoint(x: $0.x * k, y: $0.y * k) } }

    private static func offset(_ pts: [CGPoint], _ o: CGFloat) -> [CGPoint] {
        guard let a = pts.first, let b = pts.last else { return pts }
        let dx = b.x - a.x, dy = b.y - a.y, l = max(hypot(dx, dy), 0.001)
        let nx = -dy / l, ny = dx / l
        return pts.map { CGPoint(x: $0.x + nx * o, y: $0.y + ny * o) }
    }
    private static let solarLane = offset(boxToHouse, -laneOffset)
    private static let gridLane = offset(boxToHouse, laneOffset)

    private func line(_ pts: [CGPoint]) -> Path {
        var p = Path()
        guard let f = pts.first else { return p }
        p.move(to: f)
        for q in pts.dropFirst() { p.addLine(to: q) }
        return p
    }

    private func drawConduits(_ ctx: inout GraphicsContext) {
        let base = StrokeStyle(lineWidth: 0, lineCap: .round, lineJoin: .round)
        func pipe(_ pts: [CGPoint], _ w: CGFloat) {
            let p = line(screen(pts))
            var s = base; s.lineWidth = (w + 3) * k
            ctx.stroke(p, with: .color(Self.pipeEdge), style: s)
            s.lineWidth = w * k
            ctx.stroke(p, with: .color(Self.pipe), style: s)
        }
        // The photo's own green glow where the inverter wire enters the box: painted over in the box's colour.
        var patch = ctx
        patch.addFilter(.blur(radius: 1.2 * k))
        patch.fill(Path(CGRect(x: 783 * k, y: 1049 * k, width: 11 * k, height: 20 * k)),
                   with: .color(Color(red: 42 / 255, green: 41 / 255, blue: 47 / 255)))
        pipe(Self.solarWire, 8)
        pipe(Self.inverterToBox, 8)
        pipe(Self.gridToBox, 8)
        // Into the house: a wider conduit holding two lanes.
        var s = base
        s.lineWidth = 16 * k; ctx.stroke(line(screen(Self.boxToHouse)), with: .color(Self.pipeEdge), style: s)
        s.lineWidth = 13 * k; ctx.stroke(line(screen(Self.boxToHouse)), with: .color(Color(red: 30 / 255, green: 31 / 255, blue: 34 / 255)), style: s)
        s.lineWidth = 5 * k
        ctx.stroke(line(screen(Self.solarLane)), with: .color(Self.pipe), style: s)
        ctx.stroke(line(screen(Self.gridLane)), with: .color(Self.pipe), style: s)
        if Self.litCable.contains(model.scenario) {
            s.lineWidth = 7.5 * k
            ctx.stroke(line(screen(Self.carCable)), with: .color(Self.cable), style: s)
        }
    }

    /// The live routes, the same split as the rest of the app: solar serves the house first, then the car,
    /// then the grid.
    private var routes: [Route] {
        let s = max(model.solarW ?? 0, 0)
        let g = model.gridW ?? 0
        let c = model.connected ? max(model.carW ?? 0, 0) : 0
        let house = max(s + g - c, 0)
        let houseSolar = min(house, s)
        let houseGrid = max(house - houseSolar, 0)
        let th = 50.0
        let solarIn = [screen(Self.solarWire), screen(Self.inverterToBox)]
        var out: [Route] = []
        var solarUsed = false
        if s > th, houseSolar > th {
            out.append(Route(id: "solarHome", pieces: solarIn + [screen(Self.solarLane)], watts: [s, s, houseSolar], color: Self.green))
            solarUsed = true
        }
        if g < -th {   // exporting: solar runs on out to the street
            out.append(Route(id: "export", pieces: solarIn + [screen(Array(Self.gridToBox.reversed()))], watts: [s, s, -g], color: Self.green))
            solarUsed = true
        }
        if s > th, !solarUsed {   // solar going only to the car
            out.append(Route(id: "solarCar", pieces: solarIn, watts: [s, s], color: Self.green))
        }
        if g > th {
            out.append(Route(id: "import", pieces: [screen(Self.gridToBox), screen(Self.gridLane)],   // always on through the box into the house
                             watts: [g, houseGrid > th ? houseGrid : g], color: Self.yellow))
        }
        if c > th {
            out.append(Route(id: "car", pieces: [screen(Self.carCable)], watts: [c], color: Self.green))
        }
        return out
    }

    private func draw(_ r: Route, _ t: Double, _ ctx: inout GraphicsContext) {
        // Join the pieces; the hop from one piece to the next is counted (so the streak takes its time
        // crossing the box) but not drawn.
        var pts: [CGPoint] = []
        var drawn: [Bool] = []   // per segment
        var speeds: [Double] = []   // per segment, points per second
        for (n, piece) in r.pieces.enumerated() where piece.count > 1 {
            let v = FlowSpeed.pointsPerSecond(watts: r.watts[n]) * Double(width / 393)
            speeds += Array(repeating: v, count: piece.count - (pts.isEmpty ? 1 : 0))
            if !pts.isEmpty { drawn.append(false) }   // the hop from the last piece
            pts.append(piece[0])
            for q in piece.dropFirst() { pts.append(q); drawn.append(true) }
        }
        guard pts.count > 1 else { return }
        var cum: [Double] = [0]
        for i in 1..<pts.count { cum.append(cum[i - 1] + Double(hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y))) }
        let total = cum[cum.count - 1]
        guard total > 1 else { return }
        func seg(_ d: Double) -> Int {
            var lo = 0, hi = cum.count - 1
            while hi - lo > 1 { let m = (lo + hi) / 2; if cum[m] <= d { lo = m } else { hi = m } }
            return lo
        }
        func at(_ d: Double) -> CGPoint {
            let d = min(max(d, 0), total)
            let i = seg(d), l = cum[i + 1] - cum[i], q = l > 0 ? (d - cum[i]) / l : 0
            return CGPoint(x: pts[i].x + (pts[i + 1].x - pts[i].x) * q, y: pts[i].y + (pts[i + 1].y - pts[i].y) * q)
        }

        let unit = Double(width / 393)
        let tail = total * 0.45
        // Distance ⇄ travel time, so every part of the streak moves at the speed of the wire it is on.
        var times: [Double] = [0]
        for i in 1..<cum.count { times.append(times[i - 1] + (cum[i] - cum[i - 1]) / speeds[i - 1]) }
        let first = speeds[0], last = speeds[speeds.count - 1], end = times[times.count - 1]
        func time(_ d: Double) -> Double {
            if d >= total { return end + (d - total) / last }
            let i = seg(max(d, 0))
            return times[i] + (d - cum[i]) / speeds[i]
        }
        func distance(_ s: Double) -> Double {
            if s <= 0 { return s * first }
            if s >= end { return total + (s - end) * last }
            var i = 0
            while i < times.count - 2, times[i + 1] <= s { i += 1 }
            return cum[i] + (s - times[i]) * speeds[i]
        }
        // The position is kept as a distance, so new readings change the speed without a jump.
        // The next streak starts once this one has gone.
        let head = clock.advance(r.id, to: t) { x, dt in
            let next = distance(time(x) + dt)
            return distance(time(next) - tail / ((first + last) / 2)) >= total ? 0 : next
        }
        let headTime = time(head)
        let tailTime = tail / ((first + last) / 2)
        let steps = 48
        var glow = ctx
        glow.addFilter(.blur(radius: 1.6 * unit))
        for j in 0..<steps {
            let d1 = min(distance(headTime - tailTime * Double(j) / Double(steps)), total)
            let d0 = max(distance(headTime - tailTime * Double(j + 1) / Double(steps)), 0)
            if d1 <= 0 { break }
            if d0 >= total { continue }
            // Split at segment ends so a hop (inside the box) is skipped cleanly.
            var a = d0
            while a < d1 {
                let i = min(seg(a), drawn.count - 1)
                let b = min(d1, cum[i + 1])
                if drawn[i], b > a {
                    let f = 1 - Double(j) / Double(steps)
                    var p = Path()
                    p.move(to: at(a)); p.addLine(to: at(b))
                    glow.stroke(p, with: .color(r.color.opacity(0.5 * f * f)), style: StrokeStyle(lineWidth: (r.width + 1.6) * unit, lineCap: .round))
                    ctx.stroke(p, with: .color(r.color.opacity(pow(f, 1.6))), style: StrokeStyle(lineWidth: r.width * unit, lineCap: .round))
                }
                if b <= a { break }
                a = b + 1e-6
            }
        }
    }
}
