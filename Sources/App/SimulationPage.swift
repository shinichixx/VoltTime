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
                Picker("", selection: $kind) {
                    Text("Home charging").tag(0)
                    Text("Public charging").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.top, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 4)

            if kind == 0 {
                SimulateView(model: home)
            } else {
                PublicView()
            }
        }
        .background(TeslaDark.bg.ignoresSafeArea())
    }
}
