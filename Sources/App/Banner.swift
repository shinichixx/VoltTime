import SwiftUI

/// The message that drops from the top after a button: what happened, in plain words.
struct Banner: Equatable {
    var title: String
    var detail: String? = nil
    var icon: String = "checkmark"
    var tint: Color = TSurface.green
    var spinning = false          // still sending
    var id = UUID()

    static func ok(_ title: String, _ detail: String? = nil) -> Banner { Banner(title: title, detail: detail) }

    static func sending(_ title: String) -> Banner { Banner(title: title, icon: "", tint: CarColors.muted, spinning: true) }

    /// Plain words for an error from Tessie or Home Assistant.
    static func failed(_ error: Error) -> Banner { failed(error.localizedDescription) }

    static func failed(_ text: String) -> Banner {
        let t = text.lowercased()
        if t.contains("timed out") || t.contains("timeout") || t.contains("asleep") || t.contains("408") || t.contains("offline") {
            return Banner(title: "Car didn't respond", detail: "It may be asleep. Try again.", icon: "exclamationmark", tint: CarColors.red)
        }
        if t.contains("token") || t.contains("set up") {
            return Banner(title: text, icon: "exclamationmark", tint: CarColors.amber)
        }
        return Banner(title: "Didn't work", detail: text, icon: "exclamationmark", tint: CarColors.red)
    }
}

/// Rounded pill under the status bar: tinted round icon, title, one grey line. Tap to dismiss.
struct BannerView: View {
    let banner: Banner
    var dismiss: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(banner.tint.opacity(0.22))
                if banner.spinning {
                    ProgressView().tint(.white).scaleEffect(0.8)
                } else {
                    Image(systemName: banner.icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(banner.tint)
                }
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                if let d = banner.detail {
                    Text(d).font(.system(size: 13)).foregroundStyle(Color(white: 0.6))
                }
            }
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 11)
        .padding(.trailing, 22)
        .padding(.vertical, 11)
        .frame(minHeight: 58)
        .background(
            Capsule().fill(Color(red: 44 / 255, green: 45 / 255, blue: 48 / 255))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                .shadow(color: .black.opacity(0.55), radius: 16, y: 6)
        )
        .padding(.horizontal, 24)
        .contentShape(Capsule())
        .onTapGesture(perform: dismiss)
    }
}

extension View {
    /// Shows the banner at the top of the screen, sliding down and away.
    func banner(_ b: Banner?, dismiss: @escaping () -> Void) -> some View {
        overlay(alignment: .top) {
            // Sits 8 pt under the safe area: below the clock, battery and Dynamic Island.
            GeometryReader { g in
                VStack(spacing: 0) {
                    Color.clear.frame(height: max(g.safeAreaInsets.top, 54) + 8)
                    if let b {
                        BannerView(banner: b, dismiss: dismiss)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .ignoresSafeArea(.container, edges: .top)
            }
            .allowsHitTesting(b != nil)
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: b)
    }
}
