import SwiftUI
import UIKit

extension View {
    /// Calls `step` with 1 (swiped left) or -1 (swiped right) without ever holding up vertical scrolling.
    @ViewBuilder func sidewaysSwipe(_ step: @escaping (Int) -> Void) -> some View {
        if #available(iOS 18.0, *) {
            gesture(SidewaysPan(step: step))
        } else {
            simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { d in
                let w = d.translation.width
                guard abs(w) > 50, abs(w) > abs(d.translation.height) * 1.4 else { return }
                step(w < 0 ? 1 : -1)
            })
        }
    }
}

/// A UIKit pan that only starts when the finger is clearly moving sideways.
@available(iOS 18.0, *)
private struct SidewaysPan: UIGestureRecognizerRepresentable {
    let step: (Int) -> Void

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let pan = g as? UIPanGestureRecognizer else { return false }
            let v = pan.velocity(in: pan.view)
            return abs(v.x) > abs(v.y) * 1.4
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let g = UIPanGestureRecognizer()
        g.maximumNumberOfTouches = 1
        g.delegate = context.coordinator
        return g
    }

    func handleUIGestureRecognizerAction(_ g: UIPanGestureRecognizer, context: Context) {
        guard g.state == .ended else { return }
        let t = g.translation(in: g.view)
        guard abs(t.x) > 50, abs(t.x) > abs(t.y) * 1.4 else { return }
        step(t.x < 0 ? 1 : -1)
    }
}
