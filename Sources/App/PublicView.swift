import SwiftUI

/// Supercharger / public DC charger cost & time (port of Tesla-M3-Charger-Calculator).
struct PublicView: View {
    @Binding var showSettings: Bool
    @AppStorage("pub.current") private var current = "20"
    @AppStorage("pub.target") private var target = "80"
    @AppStorage("pub.speed") private var speed = "250"
    @AppStorage("pub.perMinute") private var perMinute = false
    @AppStorage("pub.rateKWh") private var rateKWh = "1.07"
    @AppStorage("pub.rateMin") private var rateMin = "1.00"
    @FocusState private var focus: String?

    var body: some View {
        let outcome = PublicMath.estimate(start: parseNumber(current), end: parseNumber(target), maxKW: parseNumber(speed),
                                          rate: parseNumber(perMinute ? rateMin : rateKWh), perMinute: perMinute)
        VStack(spacing: 0) {
            AppHeader(icon: "ev.charger.fill", title: "Tesla Model 3 LR RWD 2026",
                      subtitle: "79 kWh · 90% efficiency") {
                HeaderButton(systemName: "gearshape.fill") { showSettings = true }
            }
            ScrollView {
                VStack(spacing: 12) {
                    resultCard(outcome)
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            CardTitle(icon: "battery.75percent", title: "Battery", color: Theme.teal)
                            NumberRow(label: "Current battery level", text: $current, unit: "%", focus: $focus, key: "cur")
                            Divider()
                            NumberRow(label: "Required battery level", text: $target, unit: "%", focus: $focus, key: "tgt")
                            quickTargets
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            CardTitle(icon: "bolt.fill", title: "Charger", color: Theme.orange)
                            NumberRow(label: "Max charger speed", text: $speed, unit: "kW", focus: $focus, key: "spd")
                            HStack(spacing: 6) {
                                ForEach([60, 120, 180, 250], id: \.self) { kw in
                                    chip("\(kw) kW", selected: parseNumber(speed) == Double(kw)) { speed = "\(kw)" }
                                }
                            }
                            Divider()
                            Text("Charging cost structure").font(.system(size: 13))
                            Picker("", selection: $perMinute) {
                                Text("Per kWh (RM / kWh)").tag(false)
                                Text("Per minute (RM / min)").tag(true)
                            }
                            .pickerStyle(.segmented)
                            if perMinute {
                                NumberRow(label: "Rate per minute", text: $rateMin, unit: "RM/min", focus: $focus, key: "rate")
                            } else {
                                NumberRow(label: "Rate per kWh", text: $rateKWh, unit: "RM/kWh", focus: $focus, key: "rate")
                            }
                        }
                    }
                    Text("Time follows the Model 3 LR RWD charging curve (250 kW up to 20%, tapering to 56 kW at 80%). Cost per kWh includes 10% charging loss.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }
            }
        }
    }

    private var quickTargets: some View {
        HStack(spacing: 6) {
            ForEach([60, 70, 80, 90], id: \.self) { p in
                chip("\(p)%", selected: parseNumber(target) == Double(p)) { target = "\(p)" }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 7)
                .foregroundStyle(selected ? .white : Theme.teal)
                .background(selected ? Theme.teal : Theme.teal.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func resultCard(_ outcome: PublicMath.Outcome) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                switch outcome {
                case let .ok(minutes, cost, delivered, drawn):
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("ESTIMATED TIME").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.teal).kerning(0.6)
                            Text(Fmt.shortDuration(minutes)).font(.system(size: 34, weight: .heavy))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("TOTAL COST").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.orange).kerning(0.6)
                            Text(Fmt.rm(cost)).font(.system(size: 34, weight: .heavy)).foregroundStyle(Theme.orange)
                                .minimumScaleFactor(0.6).lineLimit(1)
                        }
                    }
                    HStack(spacing: 8) {
                        Figure(label: "Into battery", value: String(format: "%.1f kWh", delivered))
                        Figure(label: "Billed", value: perMinute ? "\(Int(minutes.rounded())) min" : String(format: "%.1f kWh", drawn))
                        Figure(label: "Avg power", value: String(format: "%.0f kW", minutes > 0 ? delivered / (minutes / 60) : 0))
                    }
                case .incomplete:
                    Text("Fill in all fields to see the time and cost.").font(.system(size: 13)).foregroundStyle(.secondary)
                case let .error(msg):
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.rouge)
                }
            }
        }
    }
}
