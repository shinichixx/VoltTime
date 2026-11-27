import SwiftUI

/// Where a tap on the house photo goes. Corners are in photo pixels (the scenario photos are 1179 px wide);
/// all nine photos share the same house.
struct HouseTapAreas {
    let photo: Int
    let width: CGFloat
    /// Top of the photo in the tapped view's coordinates.
    let top: CGFloat

    /// Photos with the car in the garage; in 3, 6 and 9 the door is shut, so there's nothing to tap there.
    static let photosWithCar: Set<Int> = [1, 2, 4, 5, 7, 8]
    private static let photoWidth: CGFloat = 1179

    private static let car: [[(CGFloat, CGFloat)]] = [
        [(352, 1073), (385, 1043), (450, 1003), (500, 992), (540, 998), (540, 1193), (500, 1193), (440, 1178), (360, 1143)],
    ]
    private static let solar: [[(CGFloat, CGFloat)]] = [
        [(268, 594), (703, 523), (824, 678), (390, 760)],
        [(465, 778), (912, 692), (1048, 856), (604, 954)],
    ]
    private static let windows: [[(CGFloat, CGFloat)]] = [
        [(146, 681), (300, 720), (300, 780), (146, 738)],        // upper left
        [(82, 810), (243, 858), (243, 996), (82, 946)],          // lower left
        [(934, 946), (1060, 916), (1060, 1060), (934, 1086)],    // right of the meter box
    ]
    private static let grid: [[(CGFloat, CGFloat)]] = [
        [(755, 1093), (830, 1093), (832, 1148), (955, 1193), (945, 1238), (790, 1193), (755, 1158)],
    ]

    private var areas: [(EnergyComponent, Path)] {
        guard ScenarioPhotos.numbers.contains(photo) else { return [] }   // no photo yet
        var list: [(EnergyComponent, [[(CGFloat, CGFloat)]])] = [(.solar, Self.solar), (.home, Self.windows), (.grid, Self.grid)]
        if Self.photosWithCar.contains(photo) { list.append((.vehicle, Self.car)) }
        let k = width / Self.photoWidth
        return list.flatMap { c, polygons in
            polygons.map { corners in
                var p = Path()
                p.addLines(corners.map { CGPoint(x: $0.0 * k, y: top + $0.1 * k) })
                p.closeSubpath()
                return (c, p)
            }
        }
    }

    /// Everything tappable, as one shape.
    var shape: Path {
        var all = Path()
        for (_, p) in areas { all.addPath(p) }
        return all
    }

    func component(at point: CGPoint) -> EnergyComponent? {
        areas.first { $0.1.contains(point) }?.0
    }
}
