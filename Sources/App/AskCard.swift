import SwiftUI

/// Centre card asking "Where are you going tomorrow?" when the app is open on a charging night and it's still
/// unanswered. GPS / TSET answer straight away, Others opens the slider, Not now hides it until tomorrow evening.
struct AskCard: View {
    @ObservedObject var model: HomeModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { }   // keep taps off the page behind
            VStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 10) {
                        Image(systemName: "bolt.house.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color(red: 0.84, green: 0.08, blue: 0.18))
                            .clipShape(RoundedRectangle(cornerRadius: 11))
                        Text("Where are you going tomorrow?")
                            .font(.system(size: 17, weight: .semibold))
                            .multilineTextAlignment(.center)
                        Text(subtitle)
                            .font(.system(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                    }
                    .frame(maxWidth: .infinity)
                    Button { model.dismissAsk() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(TeslaDark.rowLabel)
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                HStack(spacing: 8) {
                    choice("GPS", "73%", highlighted: true) {
                        Task { await model.answerFromCard("GPS", limit: HomeModel.gpsLimit) }
                    }
                    choice("TSET", "63%", highlighted: false) {
                        Task { await model.answerFromCard("TSET", limit: HomeModel.tsetLimit) }
                    }
                    choice("Others", "Slider", highlighted: false) { model.showLimitSheet = true }
                }
                .padding(.top, 16)
                .disabled(model.settingLimit)
                Button("Not now") { model.dismissAsk() }
                    .font(.system(size: 14))
                    .foregroundStyle(TeslaDark.labelGrey)
                    .padding(.top, 14)
                Text("No answer by 10 pm = GPS 73%")
                    .font(.system(size: 10.5)).foregroundStyle(TeslaDark.dim)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 14)
            .frame(width: 300)
            .background(Color(red: 0.12, green: 0.12, blue: 0.13))
            .clipShape(RoundedRectangle(cornerRadius: 22))
        }
    }

    private var subtitle: String {
        let soc = model.liveSoc.map { "Ultra Rouge is at \(Int($0.rounded()))%" } ?? "Ultra Rouge is plugged in"
        return "\(soc) · ready by \(Fmt.clock(minutes: model.readyMinutes))"
    }

    private func choice(_ name: String, _ detail: String, highlighted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(name).font(.system(size: 15, weight: .semibold))
                Text(detail).font(.system(size: 11))
                    .foregroundStyle(highlighted ? Color.white.opacity(0.85) : TeslaDark.rowLabel)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(highlighted ? Color(white: 0.30) : Color(white: 0.17))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
