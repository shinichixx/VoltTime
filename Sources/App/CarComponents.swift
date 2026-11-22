import SwiftUI
import UIKit

// MARK: - Car picture (built-in studio photos; the background already runs out to the page colour)

enum CarArt {
    static let folder: URL = {
        let u = AppData.support.appendingPathComponent("CarPhoto", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()

    /// No cable when parked or driving, with the cable when plugged in.
    static func image(for c: CarSnapshot) -> UIImage? {
        let plugged = c.cableConnected && !["D", "R", "N"].contains(c.gear)
        return UIImage(named: plugged ? "car_plugged.jpg" : "car_parked.jpg")
    }

    /// Green energy flow along the cable while charging.
    static func showsFlow(for c: CarSnapshot) -> Bool { c.charging && c.cableConnected }

    /// The cable in car_plugged.jpg, from the floor end to the charge port (0…1 of the picture).
    static let cablePath: [CGPoint] = [
        CGPoint(x: 0.7473, y: 1.0000), CGPoint(x: 0.7351, y: 0.9613), CGPoint(x: 0.7135, y: 0.9345), CGPoint(x: 0.6857, y: 0.9078),
        CGPoint(x: 0.6610, y: 0.8864), CGPoint(x: 0.6523, y: 0.8677), CGPoint(x: 0.6564, y: 0.8510), CGPoint(x: 0.6672, y: 0.8377),
        CGPoint(x: 0.6980, y: 0.8142), CGPoint(x: 0.7505, y: 0.7888), CGPoint(x: 0.8091, y: 0.7742), CGPoint(x: 0.8461, y: 0.7648),
        CGPoint(x: 0.8554, y: 0.7541), CGPoint(x: 0.8430, y: 0.7407), CGPoint(x: 0.8245, y: 0.7220), CGPoint(x: 0.8186, y: 0.7006),
        CGPoint(x: 0.8186, y: 0.6405), CGPoint(x: 0.8220, y: 0.6004), CGPoint(x: 0.8261, y: 0.5603), CGPoint(x: 0.8276, y: 0.5202),
        CGPoint(x: 0.8258, y: 0.4801), CGPoint(x: 0.8198, y: 0.4534), CGPoint(x: 0.8091, y: 0.4300),
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
            if CarArt.showsFlow(for: car) { ChargeFlow() }
        }
        .aspectRatio(aspect, contentMode: .fit)
    }
}

/// Green dashes travelling along the cable into the charge port.
struct ChargeFlow: View {
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let phase = -CGFloat((t * 30).truncatingRemainder(dividingBy: 16))
            CableShape()
                .stroke(Color(red: 0, green: 226 / 255, blue: 134 / 255),
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round, dash: [6, 10], dashPhase: phase))
                .shadow(color: Color(red: 0, green: 226 / 255, blue: 134 / 255).opacity(0.9), radius: 3)
        }
        .allowsHitTesting(false)
    }
}

struct CableShape: Shape {
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
                            Image(systemName: c == .gate && model.gateSent ? "dot.radiowaves.up.forward" : c.icon(model.car))
                                .font(.system(size: 21, weight: plain ? .medium : .light))
                                .foregroundStyle(plain ? TeslaApp.icon : c.tint(model.car))
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

