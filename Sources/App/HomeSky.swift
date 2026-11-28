import SwiftUI

/// My Home's sky, light and weather. Picked from Home Assistant: the sun's height (sun.sun), the current
/// weather (weather.forecast_home, met.no) and the solar power.
///   1. Sun below the horizon → night.
///   2. Raining (and solar under 2 kW, so a wrong forecast can't rain on a sunny roof) → rain.
///   3. Sun under 15° → sunrise / sunset, or a cloudy low-sun sky when it's cloudy.
///   4. Sun higher → solar kW sets the sky: ≤2 overcast, ≤3 mostly cloudy, ≤4 partly cloudy, ≤5 mostly sunny, above clear.
/// Each sky has 3 photos (car charging / car plugged in / garage shut): Sources/Photos/home_skyN_K.jpg.
enum HomeSky: Int, CaseIterable {
    case night = 0, sunrise, sunset, lowSunCloudy, rain, overcast, mostlyCloudy, partlyCloudy, mostlySunny, clear

    static let rainStates: Set<String> = ["rainy", "pouring", "lightning", "lightning-rainy", "hail", "snowy-rainy"]
    static let cloudyStates: Set<String> = ["cloudy", "fog"]
    /// Sun height (degrees) below which the low-sun skies are used.
    static let lowSun = 15.0
    /// kW band tops for the high-sun skies, and how far past a top the reading must go before the sky changes.
    private static let bandTops: [Double] = [2.05, 3.05, 4.05, 5.05]
    private static let bandSkies: [HomeSky] = [.overcast, .mostlyCloudy, .partlyCloudy, .mostlySunny, .clear]
    private static let kwMargin = 0.15

    struct Reading {
        var elevation: Double?     // sun.sun elevation
        var aboveHorizon: Bool?    // sun.sun state
        var rising: Bool?          // sun.sun rising
        var weather: String?       // weather.forecast_home state
        var cloud: Double?         // cloud_coverage %
        var solarW: Double?
        var now = Date()
    }

    /// Whether to draw falling rain (also at night).
    static func raining(_ r: Reading) -> Bool {
        guard let w = r.weather, rainStates.contains(w) else { return false }
        return (r.solarW ?? 0) < 2000
    }

    static func pick(_ r: Reading, previous: HomeSky?) -> HomeSky {
        let hour = Double(Calendar.current.component(.hour, from: r.now)) + Double(Calendar.current.component(.minute, from: r.now)) / 60
        // Sun: from Home Assistant, or a Kuantan-ish clock guess if sun.sun is missing.
        let up: Bool
        let low: Bool
        let morning: Bool
        if let e = r.elevation {
            up = r.aboveHorizon ?? (e > 0)
            let wasLow = previous.map { [HomeSky.sunrise, .sunset, .lowSunCloudy].contains($0) } ?? false
            let limit = wasLow ? lowSun + 1 : lowSun
            low = e < limit
            morning = r.rising ?? (hour < 12.5)
        } else {
            up = hour >= 7 && hour < 19.4
            low = hour < 8.3 || hour >= 18.2
            morning = hour < 12.5
        }
        if !up { return .night }
        if raining(r) { return .rain }
        let cloudy = (r.weather.map { cloudyStates.contains($0) } ?? false) || (r.cloud ?? 0) >= 75
        if low { return cloudy ? .lowSunCloudy : (morning ? .sunrise : .sunset) }

        let kw = max(r.solarW ?? 0, 0) / 1000
        var band = bandTops.firstIndex { kw <= $0 } ?? bandTops.count
        // Stay on the previous band while the reading hovers around its edge.
        if let p = previous, let pb = bandSkies.firstIndex(of: p), abs(pb - band) == 1 {
            let edge = bandTops[min(pb, band)]
            if abs(kw - edge) < kwMargin { band = pb }
        }
        return bandSkies[band]
    }

    /// 1 = car charging, 2 = car plugged in / parked, 3 = garage shut (from the 9 scenario numbers).
    static func carState(scenario: Int) -> Int {
        (1...9).contains(scenario) ? (scenario - 1) % 3 + 1 : 3
    }

    func photo(carState k: Int) -> UIImage? {
        guard let u = Bundle.main.url(forResource: "home_sky\(rawValue)_\(k)", withExtension: "jpg"),
              let d = try? Data(contentsOf: u) else { return nil }
        return ScenarioPhotos.decode(d)
    }
}

extension HAState {
    func attribute(_ key: String) -> Double? {
        switch attributes[key] {
        case let n as NSNumber: return n.doubleValue
        case let d as Double: return d
        case let s as String: return Double(s)
        default: return nil
        }
    }
    func flag(_ key: String) -> Bool? {
        switch attributes[key] {
        case let b as Bool: return b
        case let n as NSNumber: return n.boolValue
        default: return nil
        }
    }
}

/// Falling rain over the house and the power flow (the labels and their lines stay above it).
/// Three depths: many thin faint far drops, medium drops, a few long near drops; small splashes on the ground.
struct RainOverlay: View {
    let width: CGFloat
    @Environment(\.scenePhase) private var phase
    @State private var visible = false

    private struct Drop { let x, y0, len, alpha: Double; let speed: Double; let lw: Double }
    private struct Splash { let x, y, phase: Double }
    // Photo pixels (photos are 1179 × 1579).
    private static let top = 87.0, span = 1300.0
    private static let drops: [Drop] = {
        var g = SeededRandom(seed: 3)
        var out: [Drop] = []
        for (count, depth, len, lw, alpha) in [(420, 1.0, 18.0...34.0, 1.0, 0.14...0.29),
                                                 (240, 2.0, 40.0...70.0, 2.0, 0.24...0.45),
                                                 (60, 3.0, 80.0...120.0, 3.0, 0.28...0.47)] {
            for _ in 0..<count {
                out.append(Drop(x: g.next(in: -100...1330), y0: g.next(in: 0...span), len: g.next(in: len),
                                alpha: g.next(in: alpha), speed: depth * span, lw: lw))
            }
        }
        return out
    }()
    private static let splashes: [Splash] = {
        var g = SeededRandom(seed: 11)
        return (0..<70).map { _ in Splash(x: g.next(in: 40...1140), y: g.next(in: 1217...1377), phase: g.next(in: 0...1)) }
    }()
    private static let colour = Color(red: 205 / 255, green: 220 / 255, blue: 235 / 255)

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !visible || phase != .active)) { tl in
            Canvas { ctx, _ in
                let t = tl.date.timeIntervalSinceReferenceDate
                let k = width / 1179
                for d in Self.drops {
                    let y = Self.top + (d.y0 + d.speed * t).truncatingRemainder(dividingBy: Self.span)
                    let x = d.x - (y - Self.top) * 0.25
                    var a = d.alpha
                    if y > Self.top + Self.span - 100 { a *= max(0, (Self.top + Self.span - y) / 100) }
                    var p = Path()
                    p.move(to: CGPoint(x: x * k, y: y * k))
                    p.addLine(to: CGPoint(x: (x - d.len * 0.25) * k, y: (y + d.len) * k))
                    ctx.stroke(p, with: .color(Self.colour.opacity(a)), lineWidth: d.lw * k)
                }
                for s in Self.splashes {
                    let f = ((t + s.phase).truncatingRemainder(dividingBy: 1)) / 0.4   // 0.4 s per splash, once a second
                    guard f < 1 else { continue }
                    let rx = 6 + 26 * f
                    let r = CGRect(x: (s.x - rx) * k, y: (s.y - rx * 0.25) * k, width: 2 * rx * k, height: 0.5 * rx * k)
                    ctx.stroke(Path(ellipseIn: r), with: .color(Self.colour.opacity(0.43 * (1 - f))), lineWidth: 2 * k)
                }
            }
        }
        .frame(width: width, height: width * 1579 / 1179)
        .allowsHitTesting(false)
        .onAppear { visible = true }
        .onDisappear { visible = false }
    }
}

/// The thin lines from each figure down to its part of the house. Drawn above the rain, with the labels.
struct HouseGuideLines: View {
    let width: CGFloat
    // Photo pixels: x, from y, to y (Wall Connector, Solar, Home, Grid).
    private static let lines: [(CGFloat, CGFloat, CGFloat)] = [(342, 344, 966), (596.5, 344, 829), (926, 344, 979), (936.5, 1232, 1412)]

    var body: some View {
        Canvas { ctx, _ in
            let k = width / 1179
            for (x, a, b) in Self.lines {
                var p = Path()
                p.move(to: CGPoint(x: x * k, y: a * k))
                p.addLine(to: CGPoint(x: x * k, y: b * k))
                ctx.stroke(p, with: .linearGradient(Gradient(stops: [.init(color: .white.opacity(0), location: 0),
                                                                       .init(color: .white.opacity(0.25), location: 0.04),
                                                                       .init(color: .white.opacity(0.25), location: 1)]),
                                                    startPoint: CGPoint(x: x * k, y: a * k), endPoint: CGPoint(x: x * k, y: b * k)),
                           lineWidth: 1)
            }
        }
        .frame(width: width, height: width * 1579 / 1179)
        .allowsHitTesting(false)
    }
}

/// Small repeatable random numbers, so the rain looks the same every time.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> Double {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return Double(state >> 11) / Double(1 << 53)
    }
    mutating func next(in r: ClosedRange<Double>) -> Double { r.lowerBound + (r.upperBound - r.lowerBound) * next() }
}
