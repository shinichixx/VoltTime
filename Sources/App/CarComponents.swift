import SwiftUI
import UIKit

// MARK: - Car picture (built-in studio photos; the background already runs out to the page colour)

enum CarArt {
    static let folder: URL = {
        let u = AppData.support.appendingPathComponent("CarPhoto", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()

    /// On the road in D / R / N, with the cable when plugged in, otherwise parked.
    static func image(for c: CarSnapshot) -> UIImage? {
        if ["D", "R", "N"].contains(c.gear) { return UIImage(named: "car_driving.jpg") }
        return UIImage(named: c.cableConnected ? "car_plugged.jpg" : "car_parked.jpg")
    }

    /// Green energy flow along the cable while charging.
    static func showsFlow(for c: CarSnapshot) -> Bool { c.charging && c.cableConnected }

    // Cable centre line on car_plugged.jpg, from the floor to where it meets the charger handle (retraced in build 44).
    static let cablePath: [CGPoint] = [
        CGPoint(x: 0.7457, y: 1.0000), CGPoint(x: 0.7346, y: 0.9626), CGPoint(x: 0.7145, y: 0.9369), CGPoint(x: 0.6861, y: 0.9103),
        CGPoint(x: 0.6615, y: 0.8877), CGPoint(x: 0.6529, y: 0.8692), CGPoint(x: 0.6581, y: 0.8523), CGPoint(x: 0.6693, y: 0.8410),
        CGPoint(x: 0.6989, y: 0.8164), CGPoint(x: 0.7519, y: 0.7913), CGPoint(x: 0.8108, y: 0.7754), CGPoint(x: 0.8499, y: 0.7656),
        CGPoint(x: 0.8617, y: 0.7528), CGPoint(x: 0.8475, y: 0.7385), CGPoint(x: 0.8267, y: 0.7210), CGPoint(x: 0.8203, y: 0.7000),
        CGPoint(x: 0.8184, y: 0.6667), CGPoint(x: 0.8196, y: 0.6256), CGPoint(x: 0.8239, y: 0.5795), CGPoint(x: 0.8262, y: 0.5333),
        CGPoint(x: 0.8258, y: 0.5026), CGPoint(x: 0.8229, y: 0.4692), CGPoint(x: 0.8182, y: 0.4513), CGPoint(x: 0.8120, y: 0.4405),
        CGPoint(x: 0.8061, y: 0.4359),
    ]
}

/// The car picture for the current state, with the charging flow drawn on the cable.
/// The photos fade into the page on all sides by themselves, so the car is never dimmed.
struct CarScene: View {
    let car: CarSnapshot
    var body: some View {
        let img = CarArt.image(for: car)
        let aspect = img.map { $0.size.width / max($0.size.height, 1) } ?? 2.17
        ZStack {
            if let img { Image(uiImage: img).resizable().scaledToFit() }
            if CarArt.showsFlow(for: car) { ChargeFlow(kW: car.chargerPowerKW ?? 7) }
        }
        .aspectRatio(aspect, contentMode: .fit)
        // A long, soft fade into the page on every side, so the photo has no visible edge.
        .mask {
            LinearGradient(stops: Self.fade(from: 0.043, to: 0.19, and: 0.81, 0.957), startPoint: .leading, endPoint: .trailing)
                .mask { LinearGradient(stops: Self.fade(from: 0, to: 0.32, and: 0.76, 1), startPoint: .top, endPoint: .bottom) }
        }
    }

    /// Clear → solid between `a` and `b`, solid → clear between `c` and `d`, eased (smootherstep) so no band shows.
    private static func fade(from a: Double, to b: Double, and c: Double, _ d: Double) -> [Gradient.Stop] {
        let steps = (0...12).map { Double($0) / 12 }
        func ease(_ t: Double) -> Double { t * t * t * (t * (t * 6 - 15) + 10) }
        return steps.map { Gradient.Stop(color: .black.opacity(ease($0)), location: a + (b - a) * $0) }
            + steps.map { Gradient.Stop(color: .black.opacity(ease(1 - $0)), location: c + (d - c) * $0) }
    }
}

/// Green dashes travelling along the cable into the charge port.
/// Charging flow like the Tesla app: one long green streak at a time runs up the cable into the plug,
/// as thin as the cable, faster at higher charging power (1–8 kW).
struct ChargeFlow: View {
    var kW: Double = 7
    @Environment(\.scenePhase) private var phase

    var body: some View {
        GeometryReader { geo in
            let poly = CableShape.polyline(in: CGRect(origin: .zero, size: geo.size))
            TimelineView(.animation(minimumInterval: nil, paused: phase != .active)) { tl in
                Canvas { ctx, _ in draw(poly, geo.size.width, tl.date.timeIntervalSinceReferenceDate, &ctx) }
            }
        }
        .allowsHitTesting(false)
    }

    private static let green = Color(red: 0.30, green: 0.95, blue: 0.45)

    private func draw(_ pts: [CGPoint], _ width: CGFloat, _ t: Double, _ ctx: inout GraphicsContext) {
        guard pts.count > 1 else { return }
        var cum: [Double] = [0]
        for i in 1..<pts.count { cum.append(cum[i - 1] + Double(hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y))) }
        let total = cum[cum.count - 1]
        guard total > 1 else { return }
        func at(_ d: Double) -> CGPoint {
            let d = min(max(d, 0), total)
            var lo = 0, hi = cum.count - 1
            while hi - lo > 1 { let m = (lo + hi) / 2; if cum[m] <= d { lo = m } else { hi = m } }
            let seg = cum[hi] - cum[lo], r = seg > 0 ? (d - cum[lo]) / seg : 0
            return CGPoint(x: pts[lo].x + (pts[hi].x - pts[lo].x) * r, y: pts[lo].y + (pts[hi].y - pts[lo].y) * r)
        }
        let unit = Double(width / 393)
        let k = min(max(kW, 1), 8)
        let speed = (12 + (k - 1) / 7 * 34) * 1.6 * unit          // points per second
        let tail = total * 0.65
        let cycle = total + tail                                   // next streak starts once the last has gone into the plug
        let head = (t * speed).truncatingRemainder(dividingBy: cycle)
        let steps = 48
        var glow = ctx
        glow.addFilter(.blur(radius: 1.0 * unit))
        for j in 0..<steps {
            let d1 = head - tail * Double(j) / Double(steps)
            let d0 = head - tail * Double(j + 1) / Double(steps)
            if d1 < 0 { break }
            if d0 > total { continue }
            let f = 1 - Double(j) / Double(steps)
            var p = Path()
            p.move(to: at(d0)); p.addLine(to: at(min(d1, total)))
            glow.stroke(p, with: .color(Self.green.opacity(0.45 * f * f)), style: StrokeStyle(lineWidth: 2.6 * unit, lineCap: .round))
            ctx.stroke(p, with: .color(Self.green.opacity(pow(f, 1.6))), style: StrokeStyle(lineWidth: 1.5 * unit, lineCap: .round))
        }
    }
}

struct CableShape: Shape {
    /// The smoothed cable as a list of points (for running the streak along it).
    static func polyline(in r: CGRect) -> [CGPoint] {
        let pts = CarArt.cablePath.map { CGPoint(x: r.minX + $0.x * r.width, y: r.minY + $0.y * r.height) }
        guard var cur = pts.first else { return [] }
        var out = [cur]
        for i in 1..<pts.count {
            let c = pts[i - 1]
            let mid = CGPoint(x: (c.x + pts[i].x) / 2, y: (c.y + pts[i].y) / 2)
            for n in 1...10 {
                let t = CGFloat(n) / 10
                out.append(CGPoint(x: (1 - t) * (1 - t) * cur.x + 2 * (1 - t) * t * c.x + t * t * mid.x,
                                   y: (1 - t) * (1 - t) * cur.y + 2 * (1 - t) * t * c.y + t * t * mid.y))
            }
            cur = mid
        }
        out.append(pts[pts.count - 1])
        return out
    }

    func path(in r: CGRect) -> Path {
        var p = Path()
        let pts = CarArt.cablePath.map { CGPoint(x: r.minX + $0.x * r.width, y: r.minY + $0.y * r.height) }
        guard let first = pts.first else { return p }
        p.move(to: first)
        // smooth through the points (midpoint quad curves)
        for i in 1..<pts.count {
            let mid = CGPoint(x: (pts[i - 1].x + pts[i].x) / 2, y: (pts[i - 1].y + pts[i].y) / 2)
            p.addQuadCurve(to: mid, control: pts[i - 1])
        }
        p.addLine(to: pts[pts.count - 1])
        return p
    }
}

// MARK: - Drawn icons (Tesla app style)

/// Battery with three heat waves rising out of it: grey when off, red while preconditioning.
struct PreconditionGlyph: View {
    var on: Bool
    var size: CGFloat = 24
    var color: Color = TeslaApp.icon
    var body: some View {
        Canvas { ctx, sz in
            let u = sz.width / 24
            let lw = 1.7 * u
            var shell = Path(roundedRect: CGRect(x: 2.5 * u, y: 12.5 * u, width: 16 * u, height: 9 * u), cornerRadius: 2.2 * u)
            shell.addRoundedRect(in: CGRect(x: 19.6 * u, y: 15.2 * u, width: 1.8 * u, height: 3.6 * u), cornerSize: CGSize(width: 0.8 * u, height: 0.8 * u))
            let c = on ? CarColors.red : color
            ctx.stroke(shell, with: .color(c), lineWidth: lw)
            for x in [7.0, 10.5, 14.0] {
                var w = Path()
                w.move(to: CGPoint(x: x * u, y: 18.5 * u))
                w.addCurve(to: CGPoint(x: x * u, y: 10.5 * u), control1: CGPoint(x: (x - 2.2) * u, y: 16 * u), control2: CGPoint(x: (x + 2.2) * u, y: 13 * u))
                w.addCurve(to: CGPoint(x: x * u, y: 2.5 * u), control1: CGPoint(x: (x - 2.2) * u, y: 8 * u), control2: CGPoint(x: (x + 2.2) * u, y: 5 * u))
                ctx.stroke(w, with: .color(c), style: StrokeStyle(lineWidth: lw, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
    }
}

/// Sentry: grey outer ring, inner dot that turns red when Sentry is on (Tesla app).
struct SentryGlyph: View {
    var on: Bool
    var size: CGFloat = 24
    var color: Color = TeslaApp.icon
    var body: some View {
        ZStack {
            Circle().stroke(color, lineWidth: size * 0.075)
                .frame(width: size * 0.88, height: size * 0.88)
            Circle().fill(on ? Color(red: 232 / 255, green: 52 / 255, blue: 52 / 255) : color)
                .frame(width: size * 0.5, height: size * 0.5)
        }
        .frame(width: size, height: size)
    }
}

/// ☰, a little smaller than the system one (Tesla app top right).
struct MenuGlyph: View {
    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { _ in Capsule().fill(Color(white: 0.88)).frame(width: 18, height: 1.5) }
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
}

// MARK: - Top-down car with tyres (real Model 3 proportions: 4720 × 1848 mm, wheelbase 2875, track 1584)

struct TyreDiagram: View {
    let colors: [Color]    // FL FR RL RR
    var lengthPt: CGFloat = 108

    static let L: CGFloat = 4720, Wb: CGFloat = 1848, Wm: CGFloat = 2089
    static let WB: CGFloat = 2875, OF: CGFloat = 868, TRACK: CGFloat = 1584, TW: CGFloat = 235, TD: CGFloat = 669

    var body: some View {
        let L = Self.L, Wb = Self.Wb, Wm = Self.Wm, WB = Self.WB, OF = Self.OF, TRACK = Self.TRACK, TW = Self.TW, TD = Self.TD
        let k = lengthPt / L
        Canvas { ctx, sz in
            let mx = sz.width / 2
            let hw = Wb / 2 * k, hm = Wm / 2 * k, Lp = L * k
            let fa = OF * k, ra = (OF + WB) * k, tx = TRACK / 2 * k
            func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: mx + x, y: y) }
            var body = Path()
            body.move(to: P(-hw * 0.80, Lp * 0.035))
            body.addCurve(to: P(hw * 0.80, Lp * 0.035), control1: P(-hw * 0.55, 0), control2: P(hw * 0.55, 0))
            body.addCurve(to: P(hw, Lp * 0.22), control1: P(hw * 0.97, Lp * 0.07), control2: P(hw, Lp * 0.14))
            body.addLine(to: P(hw, Lp * 0.86))
            body.addCurve(to: P(0, Lp), control1: P(hw, Lp * 0.95), control2: P(hw * 0.85, Lp))
            body.addCurve(to: P(-hw, Lp * 0.86), control1: P(-hw * 0.85, Lp), control2: P(-hw, Lp * 0.95))
            body.addLine(to: P(-hw, Lp * 0.22))
            body.addCurve(to: P(-hw * 0.80, Lp * 0.035), control1: P(-hw, Lp * 0.14), control2: P(-hw * 0.97, Lp * 0.07))
            ctx.fill(body, with: .color(Color(white: 0.085)))
            ctx.stroke(body, with: .color(Color(white: 0.29)), lineWidth: 1.3)
            let tyres: [(CGFloat, CGFloat)] = [(-1, fa), (1, fa), (-1, ra), (1, ra)]
            for (i, t) in tyres.enumerated() {
                let r = CGRect(x: mx + t.0 * tx - TW * k / 2, y: t.1 - TD * k / 2, width: TW * k, height: TD * k)
                ctx.fill(Path(roundedRect: r, cornerRadius: 1.6), with: .color(colors[i]))
            }
            let glass = Color(red: 0.17, green: 0.20, blue: 0.25)
            func quad(_ y0: CGFloat, _ c0: CGFloat, _ y1: CGFloat, _ c1: CGFloat, _ w0: CGFloat, _ w1: CGFloat, _ col: Color) {
                var p = Path()
                p.move(to: P(-hw * w0, Lp * y0)); p.addQuadCurve(to: P(hw * w0, Lp * y0), control: P(0, Lp * c0))
                p.addLine(to: P(hw * w1, Lp * y1)); p.addQuadCurve(to: P(-hw * w1, Lp * y1), control: P(0, Lp * c1))
                p.closeSubpath(); ctx.fill(p, with: .color(col))
            }
            quad(0.30, 0.25, 0.42, 0.40, 0.82, 0.76, glass)
            quad(0.43, 0.41, 0.64, 0.655, 0.76, 0.76, Color(red: 0.12, green: 0.14, blue: 0.17))
            quad(0.65, 0.665, 0.78, 0.81, 0.76, 0.80, glass)
            let my = Lp * 0.31
            for s in [-1.0, 1.0] as [CGFloat] {
                var m = Path()
                m.move(to: P(s * hw, my)); m.addLine(to: P(s * hm, my + 1)); m.addLine(to: P(s * hm, my + 3.5)); m.addLine(to: P(s * hw, my + 3.5)); m.closeSubpath()
                ctx.fill(m, with: .color(Color(white: 0.29)))
                var h = Path(); h.move(to: P(s * hw * 0.78, Lp * 0.05)); h.addQuadCurve(to: P(s * hw * 0.2, Lp * 0.03), control: P(s * hw * 0.45, Lp * 0.025))
                ctx.stroke(h, with: .color(.white), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                var tl = Path(); tl.move(to: P(s * hw * 0.85, Lp * 0.955)); tl.addQuadCurve(to: P(s * hw * 0.15, Lp * 0.985), control: P(s * hw * 0.4, Lp * 0.985))
                ctx.stroke(tl, with: .color(CarColors.red), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
        }
        .frame(width: Wm * k + 4, height: L * k)
    }

    /// Where the axles are, for lining up the pressure numbers.
    var frontAxle: CGFloat { Self.OF * lengthPt / Self.L }
    var rearAxle: CGFloat { (Self.OF + Self.WB) * lengthPt / Self.L }
}


// MARK: - Quick controls

struct ControlStrip: View {
    @ObservedObject var model: CarModel
    var count = 6
    var plain = false   // View 2: grey icons, no outline

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(model.controls.prefix(count))) { c in
                Button { model.tap(c) } label: {
                    ZStack {
                        if model.busy == c {
                            ProgressView().tint(.white)
                        } else if c == .precondition {
                            PreconditionGlyph(on: model.car.preconditioning, size: 27)
                                .shadow(color: .black.opacity(0.55), radius: 4)
                        } else if c == .sentry {
                            SentryGlyph(on: model.car.sentry, size: 23)
                                .shadow(color: .black.opacity(0.55), radius: 4)
                        } else {
                            Group {
                                if c == .gate && model.gateSent {
                                    GateGlyph(size: 21 * 1.15, color: TSurface.green)   // signal sent: glows green for a moment
                                        .shadow(color: TSurface.green.opacity(0.7), radius: 6)
                                } else {
                                    ControlIcon(control: c, car: model.car, size: 21,
                                                color: plain ? TeslaApp.icon : c.tint(model.car),
                                                weight: plain ? .medium : .light)
                                }
                            }
                                .shadow(color: plain ? .black.opacity(0.55) : .clear, radius: 4)   // readable on the car photo
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(c.title)
            }
        }
        .padding(.horizontal, plain ? 0 : 6)
        .background {
            if !plain { Capsule().strokeBorder(CarColors.line, lineWidth: 1) }
        }
    }
}


// MARK: - Frunk and window glyphs (drawn like the Tesla app's)

/// Side view of the car's nose; the hood lifts when the frunk is open. Drawn centred in its frame.
struct FrunkShape: Shape {
    var open: Bool
    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 270
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.midX + (x - 155) * k, y: rect.midY + (y - 160) * k) }
        var path = Path()
        path.move(to: p(70, 230)); path.addLine(to: p(33, 224)); path.addLine(to: p(27, 152))
        path.addCurve(to: p(205, 120), control1: p(85, 126), control2: p(155, 120))
        path.addLine(to: p(283, 78))
        path.move(to: p(197, 230)); path.addLine(to: p(283, 230))
        if open {
            path.move(to: p(67, 32)); path.addCurve(to: p(205, 120), control1: p(125, 42), control2: p(175, 80))
        }
        let c = p(135, 220)
        path.addEllipse(in: CGRect(x: c.x - 48 * k, y: c.y - 48 * k, width: 96 * k, height: 96 * k))
        return path
    }
}

struct FrunkGlyph: View {
    var open: Bool
    var size: CGFloat = 24
    var color: Color = TeslaApp.icon
    var body: some View {
        FrunkShape(open: open)
            .stroke(color, style: StrokeStyle(lineWidth: size * 24 / 270, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}

/// A door: the glass fills the window when closed, drops with a gap at the top when vented.
struct WindowGlyph: View {
    var open: Bool
    var size: CGFloat = 24
    var color: Color = TeslaApp.icon
    var body: some View {
        Canvas { ctx, sz in
            let k = min(sz.width, sz.height) / 250
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * k, y: y * k) }
            var door = Path()
            door.move(to: p(13, 110)); door.addLine(to: p(93, 17)); door.addLine(to: p(215, 17))
            door.addQuadCurve(to: p(235, 37), control: p(235, 17))
            door.addLine(to: p(235, 223)); door.addQuadCurve(to: p(221, 237), control: p(235, 237))
            door.addLine(to: p(27, 237)); door.addQuadCurve(to: p(13, 223), control: p(13, 237))
            door.closeSubpath()
            door.move(to: p(13, 131)); door.addLine(to: p(235, 131))
            let style = StrokeStyle(lineWidth: 24 * k, lineCap: .round, lineJoin: .round)
            ctx.stroke(door, with: .color(color), style: style)
            var glass = Path()
            if open {
                glass.move(to: p(29, 127)); glass.addLine(to: p(111, 55)); glass.addLine(to: p(221, 55))
                glass.addLine(to: p(221, 131)); glass.addLine(to: p(25, 131)); glass.closeSubpath()
                ctx.fill(glass, with: .color(color))
            } else {
                glass.move(to: p(13, 110)); glass.addLine(to: p(93, 17)); glass.addLine(to: p(215, 17))
                glass.addQuadCurve(to: p(235, 37), control: p(235, 17))
                glass.addLine(to: p(235, 131)); glass.addLine(to: p(13, 131)); glass.closeSubpath()
                ctx.fill(glass, with: .color(color)); ctx.stroke(glass, with: .color(color), style: style)
            }
        }
        .frame(width: size * 0.92, height: size * 0.92)
        .frame(width: size, height: size)
    }
}

/// The icon for any button: Tesla-style drawings for frunk, windows, sentry; SF Symbols for the rest.
struct ControlIcon: View {
    let control: CarControl
    let car: CarSnapshot
    var size: CGFloat = 21
    var color: Color = TeslaApp.icon
    var weight: Font.Weight = .light
    var body: some View {
        switch control {
        case .frunk: FrunkGlyph(open: car.frunkOpen, size: size * 1.4, color: color)
        case .gate: GateGlyph(size: size * 1.15, color: color)
        case .windows: WindowGlyph(open: car.anyWindowOpen, size: size * 1.1, color: color)
        default: Image(systemName: control.icon(car)).font(.system(size: size, weight: weight)).foregroundStyle(color)
        }
    }
}

/// Picket gate (autogate): five pickets, the middle one tallest, two rails.
struct GateGlyph: View {
    var size: CGFloat = 24
    var color: Color = TeslaApp.icon
    var body: some View {
        Canvas { ctx, sz in
            let k = min(sz.width, sz.height) / 74
            let ox = (sz.width - 69 * k) / 2, oy = (sz.height - 70 * k) / 2
            func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
                ctx.fill(Path(roundedRect: CGRect(x: ox + x * k, y: oy + y * k, width: w * k, height: h * k), cornerRadius: 1.5 * k), with: .color(color))
            }
            for (i, top) in [14.0, 6, 0, 6, 14].enumerated() { r(CGFloat(i) * 15, CGFloat(top), 9, 70 - CGFloat(top)) }
            r(0, 26, 69, 8); r(0, 52, 69, 8)
        }
        .frame(width: size, height: size)
    }
}
