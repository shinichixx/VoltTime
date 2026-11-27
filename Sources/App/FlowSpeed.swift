import SwiftUI

/// One speed rule for every power-flow streak (My Car and My Home): the same power moves at the same speed.
/// 12 kW (and anything above) runs at 112 points per second on a 393 pt wide screen.
/// Below 0.5 kW the streak moves at half the curve's speed.
enum FlowSpeed {
    private static let curve: [(kW: Double, v: Double)] = [(0, 20), (1, 28), (3, 42), (7, 62), (12, 80)]

    static func pointsPerSecond(watts: Double) -> Double {
        let k = min(max(watts / 1000, 0), 12)
        var v = curve[curve.count - 1].v
        for i in 1..<curve.count where k <= curve[i].kW {
            let a = curve[i - 1], b = curve[i]
            v = a.v + (b.v - a.v) * (k - a.kW) / (b.kW - a.kW)
            break
        }
        return v * 112 / 80 * (watts < 500 ? 0.5 : 1)   // a trickle crawls at half pace
    }
}

/// Where each streak has got to. It moves on by speed × elapsed time, so a new power reading changes
/// the speed without making the streak jump.
final class FlowClock {
    private var heads: [String: (t: Double, x: Double)] = [:]

    /// The new position of streak `key`; `step` moves the old position on by the elapsed seconds.
    func advance(_ key: String, to t: Double, step: (Double, Double) -> Double) -> Double {
        let old = heads[key] ?? (t, 0)
        let x = step(old.x, min(max(t - old.t, 0), 0.1))
        heads[key] = (t, x)
        return x
    }
}
