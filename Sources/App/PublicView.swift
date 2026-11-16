import SwiftUI

/// Supercharger / public DC charger cost & time (port of Tesla-M3-Charger-Calculator).
struct PublicView: View {
    @AppStorage("pub.current") private var current = "20"
    @AppStorage("pub.target") private var target = "80"
    @AppStorage("pub.speed") private var speed = "250"
    @AppStorage("pub.perMinute") private var perMinute = false
    @AppStorage("pub.rateKWh") private var rateKWh = "1.07"
    @AppStorage("pub.rateMin") private var rateMin = "1.00"

    private static let targets = [60, 70, 80, 90]

    static func outcome(current: String, target: String, speed: String, perMinute: Bool, rateKWh: String, rateMin: String) -> PublicMath.Outcome {
        PublicMath.estimate(start: parseNumber(current), end: parseNumber(target), maxKW: parseNumber(speed),
                            rate: parseNumber(perMinute ? rateMin : rateKWh), perMinute: perMinute)
    }

    private var now: Double { parseNumber(current) ?? 0 }
    private var goal: Double { parseNumber(target) ?? 0 }

    var body: some View {
        let o = Self.outcome(current: current, target: target, speed: speed, perMinute: perMinute, rateKWh: rateKWh, rateMin: rateMin)
        ScrollView {
            VStack(spacing: 0) {
                hero(o)

                TBatteryBar(now: now, limit: max(goal, now), range: 1...100) { target = "\(Int($0))" }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                HStack {
                    (Text("\(Int(now))%").foregroundStyle(.white) + Text(" arriving"))
                    Spacer()
                    (Text("Charge to ") + Text("\(Int(goal))%").foregroundStyle(.white))
                }
                .font(.system(size: 13))
                .foregroundStyle(TeslaDark.rowLabel)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                TSegment(items: Self.targets.map { "\($0)%" }, selected: Self.targets.firstIndex { goal == Double($0) }) {
                    target = "\(Self.targets[$0])"
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 18)

                TRow("Arriving with", icon: "battery.25percent") {
                    HStack(spacing: 10) {
                        TValue(value: "\(Int(now))%")
                        TStepper(value: arrivingBinding, range: 0...95, step: 5)
                    }
                }
                NavigationLink {
                    PublicChargerPage(current: current, target: target, speed: $speed, perMinute: $perMinute,
                                      rateKWh: $rateKWh, rateMin: $rateMin)
                } label: {
                    TRow("Charger", icon: "bolt", last: true) {
                        HStack(spacing: 8) {
                            Text(chargerSummary).font(.system(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(TeslaDark.dim)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 90)   // room to scroll the last row above the page dots
        }
        .background(TSurface.page)
    }

    private var chargerSummary: String {
        let kw = parseNumber(speed).map { "\(Int($0)) kW" } ?? "— kW"
        return perMinute ? "\(kw) · RM \(rateMin)/min" : "\(kw) · RM \(rateKWh)/kWh"
    }

    /// Steps of 5 from wherever it is now (12 → 17 → 22…), never below 0.
    private var arrivingBinding: Binding<Int> {
        Binding(
            get: { Int(now) },
            set: { current = "\(max(0, min(99, $0)))" }
        )
    }

    @ViewBuilder private func hero(_ outcome: PublicMath.Outcome) -> some View {
        VStack(alignment: .leading, spacing: 0) {
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

            switch outcome {
            case let .ok(minutes, cost, delivered, _):
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    let m = Int(minutes.rounded())
                    if m < 60 {
                        Text("\(m)").font(.system(size: 54, weight: .thin))
                        Text("min").font(.system(size: 17, weight: .light)).foregroundStyle(TeslaDark.rowLabel)
                    } else {
                        Text(Fmt.shortDuration(minutes)).font(.system(size: 42, weight: .thin))
                    }
                    Spacer()
                    Text(Fmt.rm(cost)).font(.system(size: 34, weight: .light)).foregroundStyle(Theme.orange)
                        .minimumScaleFactor(0.6).lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                Text(String(format: "+%.1f kWh at %.0f kW average", delivered, minutes > 0 ? delivered / (minutes / 60) : 0))
                    .font(.system(size: 13))
                    .foregroundStyle(TeslaDark.rowLabel)
                    .padding(.horizontal, 20)
            case .incomplete:
                Text("Fill in the charger speed and price to see the time and cost.")
                    .font(.system(size: 13)).foregroundStyle(TeslaDark.rowLabel)
                    .padding(.horizontal, 20)
            case let .error(msg):
                Label(msg, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 13)).foregroundStyle(Theme.rouge)
                    .padding(.horizontal, 20)
            }
        }
    }
}

/// Public charging → Charger: speed, price and the detailed numbers.
struct PublicChargerPage: View {
    let current: String
    let target: String
    @Binding var speed: String
    @Binding var perMinute: Bool
    @Binding var rateKWh: String
    @Binding var rateMin: String
    @FocusState private var focus: String?

    private static let speeds = [60, 120, 180, 250]

    var body: some View {
        let o = PublicView.outcome(current: current, target: target, speed: speed, perMinute: perMinute, rateKWh: rateKWh, rateMin: rateMin)
        ScrollView {
            VStack(spacing: 0) {
                TCaption(text: "Charger")
                TRow("Max speed", icon: "bolt") {
                    TNumberField(text: $speed, unit: "kW", focus: $focus, key: "spd")
                } below: {
                    TSegment(items: Self.speeds.map { "\($0)" },
                             selected: Self.speeds.firstIndex { parseNumber(speed) == Double($0) }) {
                        speed = "\(Self.speeds[$0])"
                    }
                }
                TRow("Price", icon: "banknote", last: true) {
                    if perMinute {
                        TNumberField(text: $rateMin, unit: "RM/min", focus: $focus, key: "rate")
                    } else {
                        TNumberField(text: $rateKWh, unit: "RM/kWh", focus: $focus, key: "rate")
                    }
                } below: {
                    TSegment(items: ["Per kWh", "Per minute"], selected: perMinute ? 1 : 0) { perMinute = $0 == 1 }
                }

                TCaption(text: "Numbers")
                if case let .ok(minutes, cost, delivered, drawn) = o {
                    TRow("Into battery") { TValue(value: String(format: "%.1f", delivered), unit: "kWh") }
                    TRow("Billed") {
                        perMinute ? TValue(value: "\(Int(minutes.rounded()))", unit: "min")
                                  : TValue(value: String(format: "%.1f", drawn), unit: "kWh")
                    }
                    TRow("Average power") { TValue(value: String(format: "%.0f", minutes > 0 ? delivered / (minutes / 60) : 0), unit: "kW") }
                    TRow("Time") { TValue(value: Fmt.shortDuration(minutes)) }
                    TRow("Cost", last: true) { TValue(value: Fmt.rm(cost), color: Theme.orange) }
                } else {
                    TRow("Fill in the speed and price", last: true) { EmptyView() }
                }

                Text("Model 3 LR RWD 2026 · 79 kWh · 90% efficiency. Follows the charging curve: 250 kW up to 20%, tapering to 56 kW at 80%. Cost per kWh includes 10% charging loss.")
                    .font(.system(size: 11)).foregroundStyle(TeslaDark.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                Spacer(minLength: 40)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .teslaPage("Charger", black: true)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }
            }
        }
    }
}
