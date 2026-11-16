import SwiftUI

/// Second page (swipe left from My Home): what-if calculators. Nothing is sent to the car.
struct SimulationPage: View {
    @ObservedObject var home: HomeModel
    @AppStorage("sim.kind") private var kind = 0

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Simulation")
                    .font(.system(size: 27, weight: .semibold))
                    .kerning(-0.3)
                    .foregroundStyle(.white)
                Text("Nothing is sent to the car")
                    .font(.system(size: 15))
                    .foregroundStyle(TeslaDark.rowLabel)
                TSegment(items: ["Home charging", "Public charging"], selected: kind) { kind = $0 }
                    .padding(.top, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 20)
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
        .background(TSurface.page.ignoresSafeArea())
    }
}
