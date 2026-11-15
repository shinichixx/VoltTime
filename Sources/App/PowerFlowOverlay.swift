import SwiftUI

/// Glowing pulses running along the wires in the My Home photo, in the direction power flows.
/// Drawn in code over the existing photos (no video), speed follows the power, colour follows the source:
/// green = solar, yellow = grid, mixed wires get a matching share of each.
struct PowerFlowOverlay: View {
    @ObservedObject var model: MyHomeModel
    let width: CGFloat
    @Environment(\.scenePhase) private var phase
    @State private var visible = false

    // Wire routes in photo pixels (scenario photos are 1179 px wide), listed in the direction of flow.
    private static let solarWire: [CGPoint] = [.init(x: 630, y: 955), .init(x: 648, y: 990), .init(x: 648, y: 1062)]
    private static let inverterToBox: [CGPoint] = [.init(x: 679, y: 1086), .init(x: 777, y: 1058)]
    private static let boxToHouse: [CGPoint] = [.init(x: 802, y: 1052), .init(x: 934, y: 1017)]
    private static let gridToBox: [CGPoint] = [.init(x: 935, y: 1211), .init(x: 796, y: 1160), .init(x: 792, y: 1150), .init(x: 792, y: 1095)]
    private static let carCable: [CGPoint] = [
        .init(x: 325, y: 1012), .init(x: 326, y: 1050), .init(x: 330, y: 1072), .init(x: 337, y: 1092),
        .init(x: 346, y: 1102), .init(x: 352, y: 1096), .init(x: 355, y: 1082), .init(x: 358, y: 1070),
    ]
    private static let photoWidth: CGFloat = 1179
    private static let photoHeight: CGFloat = 1579

    static let green = Color(red: 0.30, green: 0.95, blue: 0.45)
    static let yellow = Color(red: 1.0, green: 0.84, blue: 0.16)

    private struct Flow {
        let points: [CGPoint]   // screen points
        let watts: Double
        let greenShare: Double  // 0 = all grid (yellow), 1 = all solar (green)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !visible || phase != .active)) { tl in
            Canvas { ctx, _ in
                let t = tl.date.timeIntervalSinceReferenceDate
                for f in flows { draw(f, t, &ctx) }
            }
        }
        .frame(width: width, height: width * Self.photoHeight / Self.photoWidth)
        .allowsHitTesting(false)
        .onAppear { visible = true }
        .onDisappear { visible = false }
    }

    private func screen(_ pts: [CGPoint]) -> [CGPoint] {
        let k = width / Self.photoWidth
        return pts.map { CGPoint(x: $0.x * k, y: $0.y * k) }
    }

    /// The live flows (watts), the same split as the rest of the app: solar serves the house first, then the car.
    private var flows: [Flow] {
        let s = max(model.solarW ?? 0, 0)
        let g = model.gridW ?? 0
        let c = model.connected ? max(model.carW ?? 0, 0) : 0
        let house = max(s + g - c, 0)
        let threshold = 50.0
        var out: [Flow] = []
        if s > threshold {
            out.append(Flow(points: screen(Self.solarWire), watts: s, greenShare: 1))
            out.append(Flow(points: screen(Self.inverterToBox), watts: s, greenShare: 1))
        }
        if g > threshold {
            out.append(Flow(points: screen(Self.gridToBox), watts: g, greenShare: 0))
        } else if g < -threshold {
            out.append(Flow(points: screen(Array(Self.gridToBox.reversed())), watts: -g, greenShare: 1))
        }
        if house > threshold {
            out.append(Flow(points: screen(Self.boxToHouse), watts: house, greenShare: min(house, s) / house))
        }
        if c > threshold {
            let carSolar = min(c, max(s - house, 0))
            out.append(Flow(points: screen(Self.carCable), watts: c, greenShare: carSolar / c))
        }
        return out
    }

    /// Fixed speed bands (so pulses don't jump every time the reading changes a little).
    private func speed(_ watts: Double) -> Double {
        let scale = Double(width / 393)
        switch watts {
        case ..<1000: return 14 * scale
        case ..<3000: return 22 * scale
        case ..<6000: return 32 * scale
        default: return 42 * scale
        }
    }

    private func draw(_ f: Flow, _ t: Double, _ ctx: inout GraphicsContext) {
        let pts = f.points
        guard pts.count > 1 else { return }
        var lengths: [Double] = []
        for i in 0..<(pts.count - 1) { lengths.append(Double(hypot(pts[i + 1].x - pts[i].x, pts[i + 1].y - pts[i].y))) }
        let total = lengths.reduce(0, +)
        guard total > 1 else { return }

        func point(_ d: Double) -> CGPoint {
            var d = d
            for (i, l) in lengths.enumerated() {
                if d <= l {
                    let r = l > 0 ? d / l : 0
                    return CGPoint(x: pts[i].x + (pts[i + 1].x - pts[i].x) * r, y: pts[i].y + (pts[i + 1].y - pts[i].y) * r)
                }
                d -= l
            }
            return pts[pts.count - 1]
        }

        let unit = Double(width / 393)
        let gap = 24 * unit
        let travelled = t * speed(f.watts)
        let newest = Int(floor(travelled / gap))
        let oldest = Int(floor((travelled - total) / gap))
        for m in oldest...newest {
            let head = travelled - Double(m) * gap
            guard head >= 0, head <= total else { continue }
            // Golden-ratio spread so a 30 % solar wire shows ~3 in 10 pulses green, evenly mixed; a pulse keeps its colour.
            var frac = (Double(m) * 0.6180339887).truncatingRemainder(dividingBy: 1)
            if frac < 0 { frac += 1 }
            let color = frac < f.greenShare ? Self.green : Self.yellow

            var glow = ctx
            glow.addFilter(.blur(radius: 3.5 * unit))
            let hp = point(head)
            let gr = 4.2 * unit
            glow.fill(Path(ellipseIn: CGRect(x: hp.x - gr, y: hp.y - gr, width: gr * 2, height: gr * 2)), with: .color(color.opacity(0.75)))

            for j in 0..<8 {
                let q = head - Double(j) * 1.5 * unit
                if q < 0 { break }
                let p = point(q)
                let r = (2.3 - Double(j) * 0.17) * unit
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .color(color.opacity(1 - Double(j) / 8)))
            }
        }
    }
}
