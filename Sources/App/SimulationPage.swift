import SwiftUI

/// Second page (swipe left from My Home): what-if calculators. Nothing is sent to the car.
struct SimulationPage: View {
    @ObservedObject var home: HomeModel
    @AppStorage("sim.kind") private var kind = 0

    var body: some View {
        GeometryReader { geo in
        VStack(spacing: 0) {
            // Title and line exactly where My Car / My Home put theirs (24 pt down, 7% in; line at 58 pt).
            ZStack(alignment: .topLeading) {
                Text("Simulation")
                    .font(.app(size: 27, weight: .semibold))
                    .kerning(-0.3)
                    .foregroundStyle(.white)
                    .padding(.top, 24)
                Text("Nothing is sent to the car")
                    .font(.app(size: 15))
                    .foregroundStyle(TeslaDark.rowLabel)
                    .padding(.top, 58)
            }
            .padding(.leading, geo.size.width * 0.07)
            .frame(maxWidth: .infinity, alignment: .leading)
            TSegment(items: ["Home charging", "Public charging"], selected: kind) { kind = $0 }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 4)

            Group {
                if kind == 0 {
                    SimulateView(model: home)
                } else {
                    PublicView()
                }
            }
            .ignoresSafeArea(.container, edges: .bottom)   // cards scroll all the way to the screen edge
        }
        }
        // No background of its own: the house behind the pager shows through while swiping in (same colour as before).
    }
}
