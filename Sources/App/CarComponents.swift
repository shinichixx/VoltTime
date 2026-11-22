import SwiftUI
import UIKit

// MARK: - Car picture (your photo, or the built-in illustration)

enum CarArt {
    static let sourceKey = "car.photo.source"      // "photo" or "illustration"
    static let fadeKey = "car.photo.fade"          // 0…1
    static let brightKey = "car.photo.bright"      // -0.3…0.3
    static let scaleKey = "car.photo.scale"        // 0.7…1.4
    static let offsetKey = "car.photo.offsetY"     // points
    static let blurPlateKey = "car.photo.blurPlate"

    static var folder: URL {
        let u = AppData.support.appendingPathComponent("CarPhoto", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static var photoURL: URL { folder.appendingPathComponent("car.png") }            // background removed, ready to show
    static var chargingURL: URL { folder.appendingPathComponent("car-charging.png") }

    static var usesPhoto: Bool {
        UserDefaults.standard.string(forKey: sourceKey) == "photo" && FileManager.default.fileExists(atPath: photoURL.path)
    }

    static func image(charging: Bool) -> UIImage? {
        if usesPhoto {
            if charging, let c = UIImage(contentsOfFile: chargingURL.path) { return c }
            return UIImage(contentsOfFile: photoURL.path)
        }
        return UIImage(named: "car_sedan")
    }

    static var title: UIImage? { UIImage(named: "title_ultra_rouge") }
}

/// Car picture with its edges faded into the page (left, right, top and bottom).
struct FadedCar: View {
    let image: UIImage?
    /// Pass values to preview unsaved settings; otherwise the saved ones are used (and followed live).
    var fadeOverride: Double? = nil
    var brightOverride: Double? = nil
    @AppStorage(CarArt.fadeKey) private var savedFade = 0.55
    @AppStorage(CarArt.brightKey) private var savedBright = 0.0

    init(image: UIImage?, fade: Double? = nil, bright: Double? = nil) {
        self.image = image
        self.fadeOverride = fade
        self.brightOverride = bright
    }

    private var fade: Double { fadeOverride ?? savedFade }
    private var bright: Double { brightOverride ?? savedBright }

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .brightness(bright)
                .mask {
                    let f = max(0.001, fade)
                    ZStack {
                        LinearGradient(stops: [.init(color: .clear, location: 0),
                                               .init(color: .black, location: 0.30 * f),
                                               .init(color: .black, location: 1 - 0.26 * f),
                                               .init(color: .clear, location: 1)],
                                       startPoint: .leading, endPoint: .trailing)
                    }
                    .mask {
                        LinearGradient(stops: [.init(color: .clear, location: 0),
                                               .init(color: .black, location: 0.12 * f),
                                               .init(color: .black, location: 1 - 0.42 * f),
                                               .init(color: .clear, location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                }
        }
    }
}

// MARK: - Battery ring (View 1)

/// 100-tick ring. Amber = charge now, dim amber = room to the limit, white pointer = limit.
/// Drag anywhere on the ring to move the limit (50–100%); the centre fades to the limit and its range.
struct BatteryRing: View {
    let soc: Double
    let limit: Double
    let rangeKm: Double?
    let kmPerPercent: Double?
    let onSet: (Double) -> Void

    @State private var dragLimit: Double?
    @State private var showLimit = false
    @State private var lastHaptic = -1

    private var shownLimit: Double { dragLimit ?? limit }
    private var low: Bool { soc < 20 }
    private var socColor: Color { low ? CarColors.amber : TSurface.green }

    var body: some View {
        GeometryReader { g in
            let size = min(g.size.width, g.size.height)
            let k = size / 220
            ZStack {
                Canvas { ctx, sz in
                    let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                    func pt(_ r: CGFloat, _ p: Double) -> CGPoint {
                        let a = (p * 3.6 - 90) * .pi / 180
                        return CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
                    }
                    for i in 0..<100 {
                        let major = i % 25 == 0
                        var path = Path()
                        path.move(to: pt((major ? 95 : 98) * k, Double(i)))
                        path.addLine(to: pt(104 * k, Double(i)))
                        let col: Color = Double(i) < soc ? socColor
                            : (Double(i) < shownLimit ? (major ? Color(red: 0.42, green: 0.33, blue: 0.19) : Color(red: 0.23, green: 0.18, blue: 0.09))
                               : (major ? Color(white: 0.35) : CarColors.line))
                        ctx.stroke(path, with: .color(col), style: StrokeStyle(lineWidth: (major ? 2 : 1.4) * k, lineCap: .round))
                    }
                    let r = 80 * k
                    var track = Path(); track.addArc(center: c, radius: r, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
                    ctx.stroke(track, with: .color(Color(white: 0.08)), lineWidth: 14 * k)
                    var room = Path()
                    room.addArc(center: c, radius: r, startAngle: .degrees(soc * 3.6 - 90), endAngle: .degrees(shownLimit * 3.6 - 90), clockwise: false)
                    ctx.stroke(room, with: .color(Color(red: 0.18, green: 0.14, blue: 0.08)), lineWidth: 14 * k)
                    var now = Path()
                    now.addArc(center: c, radius: r, startAngle: .degrees(-90), endAngle: .degrees(max(soc, 0.5) * 3.6 - 90), clockwise: false)
                    ctx.stroke(now, with: .color(socColor), style: StrokeStyle(lineWidth: 14 * k, lineCap: .round))
                    // limit line + pointer
                    var line = Path(); line.move(to: pt(72 * k, shownLimit)); line.addLine(to: pt(88 * k, shownLimit))
                    ctx.stroke(line, with: .color(.white), lineWidth: 2 * k)
                    var tri = Path()
                    tri.move(to: pt(108 * k, shownLimit)); tri.addLine(to: pt(117 * k, shownLimit - 1.3)); tri.addLine(to: pt(117 * k, shownLimit + 1.3)); tri.closeSubpath()
                    ctx.fill(tri, with: .color(.white))
                    let knob = pt(r, shownLimit)
                    ctx.fill(Path(ellipseIn: CGRect(x: knob.x - 6 * k, y: knob.y - 6 * k, width: 12 * k, height: 12 * k)), with: .color(.white))
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - 64 * k, y: c.y - 64 * k, width: 128 * k, height: 128 * k)), with: .color(Color(white: 0.04)))
                }
                centre(k: k, limitMode: false).opacity(showLimit ? 0 : 1)
                centre(k: k, limitMode: true).opacity(showLimit ? 1 : 0)
            }
            .frame(width: size, height: size)
            .position(x: g.size.width / 2, y: g.size.height / 2)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { v in
                        let c = CGPoint(x: g.size.width / 2, y: g.size.height / 2)
                        var p = (atan2(v.location.y - c.y, v.location.x - c.x) * 180 / .pi + 90 + 360).truncatingRemainder(dividingBy: 360) / 3.6
                        if p < 50 { p = p < 25 ? 100 : 50 }
                        let r = p.rounded()
                        if Int(r) != lastHaptic { UISelectionFeedbackGenerator().selectionChanged(); lastHaptic = Int(r) }
                        dragLimit = Double(r)
                        withAnimation(.easeInOut(duration: 0.25)) { showLimit = true }
                    }
                    .onEnded { _ in
                        if let d = dragLimit { onSet(d) }
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(900))
                            withAnimation(.easeInOut(duration: 0.35)) { showLimit = false }
                            try? await Task.sleep(for: .milliseconds(400))
                            dragLimit = nil
                        }
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder private func centre(k: CGFloat, limitMode: Bool) -> some View {
        let pct = limitMode ? shownLimit : soc
        let km: Double? = limitMode ? kmPerPercent.map { $0 * shownLimit } : rangeKm
        VStack(spacing: 0) {
            Text(limitMode ? "CHARGE LIMIT" : (low ? "LOW" : "BATTERY"))
                .font(.system(size: 11 * k, weight: .medium)).kerning(1)
                .foregroundStyle(limitMode ? Color(white: 0.78) : (low ? CarColors.amber : CarColors.muted))
            HStack(alignment: .top, spacing: 1) {
                Text("\(Int(pct.rounded()))").font(.system(size: 50 * k, weight: .ultraLight)).kerning(-2)
                Text("%").font(.system(size: 15 * k)).foregroundStyle(CarColors.muted).padding(.top, 9 * k)
            }
            .foregroundStyle(.white)
            Rectangle().fill(CarColors.line).frame(width: 44 * k, height: 1)
            Text(km.map { "\(Int($0.rounded())) km" } ?? "— km")
                .font(.system(size: 19 * k)).foregroundStyle(.white).padding(.top, 5 * k)
        }
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

// MARK: - Battery health cells

struct HealthCells: View {
    let health: Double?   // %

    var body: some View {
        GeometryReader { g in
            let w = g.size.width - 8
            HStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7).strokeBorder(Color(white: 0.23), lineWidth: 1.5)
                    HStack(spacing: 1.5) {
                        ForEach(0..<10, id: \.self) { j in
                            let f = min(max((health ?? 0) / 10 - Double(j), 0), 1)
                            GeometryReader { c in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2.5).fill(CarColors.healthLost)
                                    RoundedRectangle(cornerRadius: 2.5).fill(TSurface.green).frame(width: c.size.width * f)
                                }
                            }
                        }
                    }
                    .padding(4)
                }
                .frame(width: w)
                RoundedRectangle(cornerRadius: 1.5).fill(Color(white: 0.23)).frame(width: 4, height: 12).padding(.leading, 2)
            }
        }
        .frame(height: 30)
    }
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
                        } else {
                            Image(systemName: c.icon(model.car))
                                .font(.system(size: 21, weight: plain ? .regular : .light))
                                .foregroundStyle(plain ? TeslaApp.grey : c.tint(model.car))
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

/// Small red round icon badge at the top of View 1 cards.
struct CardBadge: View {
    let icon: String
    let title: String
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Color(red: 0.165, green: 0.063, blue: 0.071)).frame(width: 24, height: 24)
                .overlay(Image(systemName: icon).font(.system(size: 12, weight: .medium)).foregroundStyle(CarColors.red))
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            Spacer(minLength: 0)
        }
    }
}

struct OutlineCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(CarColors.line, lineWidth: 1))
    }
}
