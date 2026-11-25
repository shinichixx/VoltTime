import SwiftUI

/// Filled icons for the Energy page (floating bar and Energy Flow tables), drawn in the Tesla app's style:
/// a house, the car from the front, the sun over a solar panel, and a pylon. Each is sized by what you see
/// (its own outline), so they line up and look the same size side by side.
struct FlowGlyph: View {
    enum Kind { case all, home, car, solar, grid }

    let kind: Kind
    var color: Color = TeslaDark.rowIcon
    /// Visible height, capped so no icon is wider than `maxWidth`.
    var height: CGFloat = 14
    var maxWidth: CGFloat = 17

    /// The drawn outline in the 64-unit drawing space.
    private var box: CGRect {
        switch kind {
        case .all: return CGRect(x: 10, y: 10, width: 44, height: 44)
        case .home: return CGRect(x: 8, y: 8, width: 48, height: 48)
        case .car: return CGRect(x: 6, y: 17, width: 52, height: 36)
        case .solar: return CGRect(x: 8, y: 3, width: 48, height: 53)
        case .grid: return CGRect(x: 8, y: 2, width: 48, height: 60)
        }
    }

    var body: some View {
        let b = box
        let s = min(height / b.height, maxWidth / b.width)
        Canvas { ctx, _ in
            ctx.scaleBy(x: s, y: s)
            ctx.translateBy(x: -b.minX, y: -b.minY)
            draw(&ctx)
        }
        .frame(width: b.width * s, height: b.height * s)
    }

    private func poly(_ pts: [(CGFloat, CGFloat)]) -> Path {
        var p = Path()
        guard let f = pts.first else { return p }
        p.move(to: CGPoint(x: f.0, y: f.1))
        for q in pts.dropFirst() { p.addLine(to: CGPoint(x: q.0, y: q.1)) }
        p.closeSubpath()
        return p
    }

    private func draw(_ ctx: inout GraphicsContext) {
        let c = GraphicsContext.Shading.color(color)
        switch kind {
        case .all:
            for a in 0..<2 {
                for b in 0..<2 {
                    ctx.fill(Path(roundedRect: CGRect(x: 10 + CGFloat(a) * 24, y: 10 + CGFloat(b) * 24, width: 20, height: 20), cornerRadius: 4), with: c)
                }
            }
        case .home:
            ctx.fill(poly([(32, 8), (56, 30), (51, 30), (51, 56), (13, 56), (13, 30), (8, 30)]), with: c)
        case .car:
            ctx.fill(poly([(14, 30), (19, 17), (45, 17), (50, 30)]), with: c)
            ctx.fill(Path(roundedRect: CGRect(x: 6, y: 28, width: 52, height: 18), cornerRadius: 7), with: c)
            ctx.fill(Path(roundedRect: CGRect(x: 9, y: 44, width: 8, height: 9), cornerRadius: 2), with: c)
            ctx.fill(Path(roundedRect: CGRect(x: 47, y: 44, width: 8, height: 9), cornerRadius: 2), with: c)
            var cut = ctx
            cut.blendMode = .destinationOut
            cut.fill(poly([(18, 29), (22, 20), (42, 20), (46, 29)]), with: .color(.black))   // windscreen
            cut.fill(poly([(10, 33), (21, 35), (20, 38), (11, 37)]), with: .color(.black))   // headlights
            cut.fill(poly([(54, 33), (43, 35), (44, 38), (53, 37)]), with: .color(.black))
        case .solar:
            var sun = Path()
            sun.addArc(center: CGPoint(x: 32, y: 24), radius: 10, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            sun.closeSubpath()
            ctx.fill(sun, with: c)
            var rays = Path()
            for deg in stride(from: 180.0, through: 360.0, by: 45.0) {
                let r = deg * .pi / 180
                rays.move(to: CGPoint(x: 32 + cos(r) * 14, y: 24 + sin(r) * 14))
                rays.addLine(to: CGPoint(x: 32 + cos(r) * 20, y: 24 + sin(r) * 20))
            }
            ctx.stroke(rays, with: c, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            // Panel: 3 rows × 4 columns, wider at the front.
            let tl = CGPoint(x: 16, y: 28), tr = CGPoint(x: 48, y: 28), bl = CGPoint(x: 8, y: 56), br = CGPoint(x: 56, y: 56)
            func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }
            for r in 0..<3 {
                for col in 0..<4 {
                    let t0 = CGFloat(r) / 3, t1 = CGFloat(r + 1) / 3, u0 = CGFloat(col) / 4, u1 = CGFloat(col + 1) / 4
                    let l0 = lerp(tl, bl, t0), r0 = lerp(tr, br, t0), l1 = lerp(tl, bl, t1), r1 = lerp(tr, br, t1)
                    let pts = [lerp(l0, r0, u0), lerp(l0, r0, u1), lerp(l1, r1, u1), lerp(l1, r1, u0)]
                    let cx = (pts[0].x + pts[2].x) / 2, cy = (pts[0].y + pts[2].y) / 2
                    let shrunk = pts.map { (cx + ($0.x - cx) * 0.82, cy + ($0.y - cy) * 0.78) }
                    ctx.fill(poly(shrunk), with: c)
                }
            }
        case .grid:
            var p = Path()
            func line(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat)) {
                p.move(to: CGPoint(x: a.0, y: a.1)); p.addLine(to: CGPoint(x: b.0, y: b.1))
            }
            p.addPath(poly([(32, 4), (37, 12), (32, 20), (27, 12)]))
            line((10, 22), (54, 22)); line((14, 34), (50, 34))
            line((10, 22), (14, 28)); line((54, 22), (50, 28))
            line((27, 16), (16, 60)); line((37, 16), (48, 60))
            line((25, 22), (42, 34)); line((39, 22), (22, 34))
            line((22, 34), (45, 48)); line((42, 34), (19, 48))
            line((19, 48), (48, 60)); line((45, 48), (16, 60))
            ctx.stroke(p, with: c, style: StrokeStyle(lineWidth: 4.6, lineCap: .round, lineJoin: .round))
        }
    }
}
