import SwiftUI

/// Supercharger / public DC charger cost & time (port of Tesla-M3-Charger-Calculator).
struct PublicView: View {
    @AppStorage("pub.current") private var current = "20"
    @AppStorage("pub.target") private var target = "80"
    @AppStorage("pub.speed") private var speed = "250"
    @AppStorage("pub.perMinute") private var perMinute = false
    @AppStorage("pub.rateKWh") private var rateKWh = "1.07"
    @AppStorage("pub.rateMin") private var rateMin = "1.00"
    @FocusState private var focus: String?

    private static let targets = [60, 70, 80, 90]
    private static let speeds = [60, 120, 180, 250]

    var body: some View {
        let outcome = PublicMath.estimate(start: parseNumber(current), end: parseNumber(target), maxKW: parseNumber(speed),
                                          rate: parseNumber(perMinute ? rateMin : rateKWh), perMinute: perMinute)
        ScrollView {
            VStack(spacing: 0) {
                hero(outcome)

                TCaption(text: "Battery")
                TRow("Current level", icon: "battery.25percent") {
                    TNumberField(text: $current, unit: "%", focus: $focus, key: "cur")
                }
                TRow("Required level", icon: "battery.100percent", last: true) {
                    TNumberField(text: $target, unit: "%", focus: $focus, key: "tgt")
                } below: {
                    TSegment(items: Self.targets.map { "\($0)%" },
                             selected: Self.targets.firstIndex { parseNumber(target) == Double($0) }) {
                        target = "\(Self.targets[$0])"
                    }
                }

                TCaption(text: "Charger")
                TRow("Max charger speed", icon: "bolt") {
                    TNumberField(text: $speed, unit: "kW", focus: $focus, key: "spd")
                } below: {
                    TSegment(items: Self.speeds.map { "\($0) kW" },
                             selected: Self.speeds.firstIndex { parseNumber(speed) == Double($0) }) {
                        speed = "\(Self.speeds[$0])"
                    }
                }
                TRow("Billed by", icon: "doc.plaintext") {
                    EmptyView()
                } below: {
                    TSegment(items: ["Per kWh", "Per minute"], selected: perMinute ? 1 : 0) { perMinute = $0 == 1 }
                }
                TRow("Rate", icon: "banknote", last: true) {
                    if perMinute {
                        TNumberField(text: $rateMin, unit: "RM/min", focus: $focus, key: "rate")
                    } else {
                        TNumberField(text: $rateKWh, unit: "RM/kWh", focus: $focus, key: "rate")
                    }
                }

                Text("Model 3 LR RWD 2026 · 79 kWh · 90% efficiency. Follows the charging curve: 250 kW up to 20%, tapering to 56 kW at 80%. Cost per kWh includes 10% charging loss.")
                    .font(.system(size: 11)).foregroundStyle(TeslaDark.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
            }
            .padding(.bottom, 90)   // room to scroll the last row above the page dots
        }
        .scrollDismissesKeyboard(.interactively)
        .background(TSurface.page)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }
            }
        }
    }

    @ViewBuilder private func hero(_ outcome: PublicMath.Outcome) -> some View {
        switch outcome {
        case let .ok(minutes, cost, delivered, drawn):
            VStack(spacing: 0) {
                HStack {
                    Text("ESTIMATED TIME").kerning(0.8)
                    Spacer()
                    Text("TOTAL COST").kerning(0.8)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(TeslaDark.rowLabel)
                .padding(.horizontal, 20)
                .padding(.top, 26)
                .padding(.bottom, 6)

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    let m = Int(minutes.rounded())
                    if m < 60 {
                        Text("\(m)").font(.system(size: 54, weight: .thin))
                        Text("min").font(.system(size: 17, weight: .light)).foregroundStyle(TeslaDark.rowLabel)
                    } else {
                        Text(Fmt.shortDuration(minutes)).font(.system(size: 42, weight: .thin))
                    }
                    Spacer()
                    Text(Fmt.rm(cost)).font(.system(size: 36, weight: .light)).foregroundStyle(Theme.orange)
                        .minimumScaleFactor(0.6).lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

                TStats(items: [
                    TStat(value: String(format: "%.1f", delivered), unit: "kWh", caption: "Into battery"),
                    perMinute ? TStat(value: "\(Int(minutes.rounded()))", unit: "min", caption: "Billed")
                              : TStat(value: String(format: "%.1f", drawn), unit: "kWh", caption: "Billed"),
                    TStat(value: String(format: "%.0f", minutes > 0 ? delivered / (minutes / 60) : 0), unit: "kW", caption: "Avg power"),
                ])
            }
        case .incomplete:
            Text("Fill in all fields to see the time and cost.")
                .font(.system(size: 13)).foregroundStyle(TeslaDark.rowLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 26)
        case let .error(msg):
            Label(msg, systemImage: "exclamationmark.triangle")
                .font(.system(size: 13)).foregroundStyle(Theme.rouge)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 26)
        }
    }
}
